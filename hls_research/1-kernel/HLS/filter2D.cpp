// Copyright (C) 2024 Advanced Micro Devices, Inc
//
// SPDX-License-Identifier: MIT

#include <iostream>
using namespace std;
#include <math.h>
#include "filter2d.h"
#include "hls_stream.h"
#include "hls_print.h"

#define K FILTER_H_SIZE

// Line buffers - used to store [FILTER_W_SIZE-1] entire lines of pixels
// Width dimension sized for padded image
static U8 LineBuffer[FILTER_W_SIZE-1][MAX_IMAGE_WIDTH + FILTER_H_SIZE - 1];

void ReadFromMem(
        int       width,
        int       height,
        const char        *coeffs,
        hls::stream<char>   &coeff_stream,
        U8 *src,
        hls::stream<U8>     &pixel_stream)
{
    assert(width <= MAX_IMAGE_WIDTH);
    assert(height <= MAX_IMAGE_HEIGHT);

    unsigned num_coefs = FILTER_W_SIZE * FILTER_H_SIZE;
    read_coefs: for (int i=0; i<num_coefs; i++) {
        coeff_stream.write(coeffs[i]);
    }

    if (width%64)
    {
        // Not a multiple of 64    
    }
    else 
    {
        width = (width/64)*64; // Makes compiler see that width is a multiple of 64, enables auto-widening
    }

    read_image: for (int n = 0; n < height * width; n++) {
#pragma HLS LOOP_TRIPCOUNT max=(MAX_IMAGE_HEIGHT)*(MAX_IMAGE_WIDTH)
#pragma HLS PIPELINE II=1
        U8 pix = src[n];
        pixel_stream.write(pix);
        
    }
}

void WriteToMem(
        int     width,
        int     height,

        hls::stream<U8>     &pixel_stream,
        U8         *dst)
{
    assert(width <= MAX_IMAGE_WIDTH);
    assert(height <= MAX_IMAGE_HEIGHT);

    write_image: for (int n = 0; n < height * width; n++) {
#pragma HLS LOOP_TRIPCOUNT max=MAX_IMAGE_HEIGHT*MAX_IMAGE_WIDTH
#pragma HLS PIPELINE II=1
        U8 pix = pixel_stream.read();
        dst[n] = pix;
    }
}


// width and height here are the image
void Window2D(
        int      width,
        int       height,
        hls::stream<U8>      &pixel_stream,
        hls::stream<window>     &window_stream)
{

    #pragma HLS ARRAY_PARTITION variable=LineBuffer dim=1 complete
    #pragma HLS DEPENDENCE variable=LineBuffer inter false
    #pragma HLS DEPENDENCE variable=LineBuffer intra false

    // Sliding window of [FILTER_V_SIZE][FILTER_H_SIZE] pixels
    window Window;

    // Input is not padded but windows must contain padding 
    const int pad_r = FILTER_W_SIZE / 2;  
    const int pad_c = FILTER_H_SIZE / 2;  
    const int padded_height = height + 2 * pad_r;
    const int padded_width  = width  + 2 * pad_c;

    static unsigned col_ptr = 0;
    static unsigned row_ptr = 0;
    unsigned ramp_up = padded_width*(FILTER_W_SIZE-1)+(FILTER_H_SIZE-1);
    unsigned num_pixels = padded_width*padded_height;

    const unsigned max_iterations = (MAX_IMAGE_WIDTH+2)*(MAX_IMAGE_HEIGHT+2);

    update_window: for (int n=0; n<num_pixels; n++)
    {
        #pragma HLS LOOP_TRIPCOUNT max=max_iterations
        #pragma HLS PIPELINE II=1

        bool is_pad = (row_ptr < pad_r) || (row_ptr >= height + pad_r) ||
                      (col_ptr < pad_c) || (col_ptr >= width  + pad_c);
        U8 new_pixel = is_pad ? (U8)0 : pixel_stream.read();

        // Shift the window and add a column of new pixels from the line buffer
        for(int i = 0; i < FILTER_W_SIZE; i++) {
            for(int j = 0; j < FILTER_H_SIZE-1; j++) {
                Window.pix[i][j] = Window.pix[i][j+1];
            }
            Window.pix[i][FILTER_H_SIZE-1] = (i<FILTER_W_SIZE-1) ? LineBuffer[i][col_ptr] : new_pixel;
        }

        // Shift pixels in the line buffer column, add the newest pixel
        for(int i = 0; i < FILTER_W_SIZE-1; i++) {
            LineBuffer[i][col_ptr] = LineBuffer[i+1][col_ptr];
        }
        LineBuffer[FILTER_W_SIZE-2][col_ptr] = new_pixel;

        // Output once the sliding window has fully ramped up (line buffers filled
        // and horizontal window primed), then emit every pixel except the last
        // FILTER_H_SIZE-1 positions of each row (right-border ramp-down).
        if (n >= ramp_up && col_ptr >= FILTER_H_SIZE-1) {
            window_stream.write(Window);
        }

        // Update the pointers
        if (col_ptr==(padded_width-1)) {
            col_ptr = 0; 
            row_ptr++;
        } else {
            col_ptr++;
        }
    }
}

void Filter2D(
        int      width,
        int      height,

        hls::stream<char>   &coeff_stream,
        hls::stream<window>  &window_stream,
        hls::stream<U8>     &pixel_stream )
{
    assert(width  <= MAX_IMAGE_WIDTH);
    assert(height <= MAX_IMAGE_HEIGHT);

    // Filtering coefficients
    char coeffs[FILTER_W_SIZE][FILTER_H_SIZE];
#pragma HLS ARRAY_PARTITION variable=coeffs complete dim=0

    // Load the coefficients into local storage
    load_coefs: for (char i=0; i<FILTER_W_SIZE; i++) {
        for (char j=0; j<FILTER_H_SIZE; j++) {
#pragma HLS PIPELINE II=1
            coeffs[i][j] = coeff_stream.read();
        }
    }

    // Process the incoming stream of pixel windows
    Loop1: for (int y = 0; y < height; y++)
#pragma HLS LOOP_TRIPCOUNT max=MAX_IMAGE_HEIGHT
    {
        Loop2: for (int x = 0; x < width; x++)
        {
#pragma HLS LOOP_TRIPCOUNT max=MAX_IMAGE_WIDTH
#pragma HLS PIPELINE II=1
            // Read a 2D window of pixels
            window w = window_stream.read();

            // Apply filter to the 2D window
            short sum = 0;
            Loop3: for(int row=0; row<FILTER_W_SIZE; row++)
//#pragma HLS PIPELINE
            {
                Loop4: for(int col=0; col<FILTER_H_SIZE; col++)

//#pragma HLS PIPELINE
                {
                    U8 pixel;
                    pixel = w.pix[row][col];
                    sum += (short)pixel*(short)coeffs[row][col];
                }
            }
            unsigned char outpix = MIN(MAX(sum,0), 255);
            pixel_stream.write(outpix);
        }
    }
}

extern "C" {

void filter2d_accel(
        char kernel[FILTER_W_SIZE*FILTER_H_SIZE],
        int height,
        int width,
        U8 src[MAX_IMAGE_WIDTH*MAX_IMAGE_HEIGHT],
        U8 dst[MAX_IMAGE_WIDTH*MAX_IMAGE_HEIGHT]
)
{
#pragma HLS INTERFACE mode=m_axi bundle=msrc  port=src
#pragma HLS INTERFACE mode=m_axi bundle=msrc  port=dst
#pragma HLS INTERFACE mode=s_axilite port=kernel bundle=CTRL
#pragma HLS INTERFACE mode=s_axilite port=height bundle=CTRL
#pragma HLS INTERFACE mode=s_axilite port=width bundle=CTRL
#pragma HLS INTERFACE mode=s_axilite port=return bundle=CTRL

#pragma HLS DATAFLOW

    // Stream of pixels from kernel input to filter, and from filter to output
    hls::stream<char,3>      coefs_stream;
    hls::stream<U8,2>        pixel_stream;
    hls::stream<window,3>    window_stream;
    hls::stream<U8,64>       output_stream;

    // Read image data from global memory, zero-pad borders, and stream pixels out
    ReadFromMem(width, height, kernel, coefs_stream, src, pixel_stream);

    // Form valid HxV windows over the padded pixel stream
    Window2D(width, height, pixel_stream, window_stream);

    // Apply filter coefficients to each window
    Filter2D(width, height, coefs_stream, window_stream, output_stream);

    // Write full-size output back to global memory
    WriteToMem(width, height, output_stream, dst);
}

}
