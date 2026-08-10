
/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * test_conv2.c: Adjustable HDL conv application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include "mem_conv.h"
#include <xstatus.h>

// Config
 #define FIFO_DEPTH 512
 // Image dimensions — hardcoded in kernel
 #define IMG_WIDTH   3840 //128, 500, 1920, 3840, 7680
 #define IMG_HEIGHT  2160 //128, 500, 1080, 2160, 4320
 #define IMG_SIZE    (IMG_WIDTH * IMG_HEIGHT)

 //const char srcImg[] = "logo.txt"; //house, droid, logo, dolphin, duck
 const char srcImg[] = "dolphin.bif"; //house, droid, logo, dolphin, duck
 //const char dstImg[] = "logoOut.txt";
 const char dstImg[] = "dolphin.bof";
 const char timeLog[] = "conDt.txt";

 #define BASE_ADDR    XPAR_XMYCONV2FULL_0_BASEADDR

 

// Instances
static FIL fil;
FRESULT res;
UINT NumBytesRead;

// Consts
TCHAR *Path = "0:/";
XTime tHWStart,tHWEnd,tSWStart,tSWEnd;

int main ()
{

	// Enabling caches
    Xil_DCacheEnable();
    Xil_ICacheEnable();

    xil_printf("AXI4-Full Pipelined 2D Convolution Peripheral: Test\n\r");
    //baseaddr = 0x7AA00000; // Due to a bug, in some cases the XPAR_MYPIXFULL_0_S00_AXI_BASEADDR is incorrect.

    xil_printf("Peripheral: Base address is 0x%08x\n\r", BASE_ADDR);

    // ---- Pointers to DDR buffers ----
    u32  *src_buf   = (u32 *) calloc (IMG_SIZE/sizeof(u32), sizeof(u32));
    if (src_buf == NULL) {xil_printf("(main): src not enough memory\r\n"); return -1;}
    
    u32  *dst_buf   = (u32 *) calloc (IMG_SIZE/sizeof(u32), sizeof(u32));
    if (dst_buf == NULL) {xil_printf("(main): dst not enough memory\r\n"); return -1;}
    u32 pixelsRead;

    // ---- Load input image ----
    // Try SD card first
    if (load_sd_to_memory(srcImg, (u8*)src_buf, &pixelsRead, 1) != XST_SUCCESS) {
        xil_printf("SD load failed\r\n");
        return -1;
    }

    // ---- Flush caches before DMA ----
    Xil_DCacheFlushRange((INTPTR)src_buf,   IMG_SIZE * sizeof(u8));
    Xil_DCacheFlushRange((INTPTR)dst_buf,   IMG_SIZE * sizeof(u8));

    xil_printf("Starting HW IP (%dx%d) ...\r\n", IMG_WIDTH, IMG_HEIGHT);

    // ---- Start and wait ----
    XTime_GetTime(&tHWStart);
    Window2D(IMG_WIDTH, IMG_HEIGHT, (u8*)src_buf, dst_buf);

    XTime_GetTime(&tHWEnd);
    xil_printf("HW IP done.\r\n");

    // ---- Invalidate cache to read result from DDR ----
    Xil_DCacheInvalidateRange((INTPTR)dst_buf, IMG_SIZE * sizeof(u8));

    // ---- Save result to SD card ----
    if ((write_data_to_sd(dstImg, (u8*)dst_buf, IMG_SIZE, 1)) != XST_SUCCESS) {
        xil_printf("SD save failed\r\n");
        return -1;
    }

    // ---- Quick sanity check: print a few output pixels ----
    xil_printf("First 5 output pixels:");
    for (int i = 0; i < 5; i++)
        xil_printf(" %d", dst_buf[i]);
    xil_printf("\r\n");

    xil_printf("Last 5 output pixels:");
    for (int i = 0; i < 5; i++)
        xil_printf(" %d", dst_buf[(IMG_SIZE - 5) + i]);
    xil_printf("\r\n");

    XTime_GetTime(&tSWStart);
    xil_printf("Running SW \r\n");
    filter2d_SW((u8*)src_buf, kernel_hardcode, (u8*)dst_buf, IMG_HEIGHT, IMG_WIDTH);
    XTime_GetTime(&tSWEnd);

    Xil_DCacheDisable();
    Xil_ICacheDisable();

    xil_printf("=== Saving run ===\r\n");
    res = timePrint();
    xil_printf("=== Done ===\r\n");
    free(src_buf);
    free(dst_buf);
    return 0;
}

FRESULT timePrint()
{
    char buffer[256];
    FIL writeFil;
    FRESULT res;
    UINT bytes_written;
    sprintf(buffer, "Size %dx%d: HDL IP time %.2f us, SW time %.2f us\r\n",\
            IMG_HEIGHT, IMG_WIDTH,\
			1.0*(tHWEnd-tHWStart)/(COUNTS_PER_SECOND/1000000),\
			1.0*(tSWEnd-tSWStart)/(COUNTS_PER_SECOND/1000000));
    
    res = f_mount(&fs, "0:/", 1);
    if (res != FR_OK) {
        xil_printf("ERROR: f_mount for run failed (%d)\r\n", res);
        return res;
    }

    // Open or create the file for writing
    res = f_open(&writeFil, timeLog, FA_WRITE | FA_OPEN_APPEND);
    if (res != FR_OK) {
        f_close(&fil);
        f_mount(NULL, Path, 0);
        return res;
    }
    
    // Write the text to the end of the file
    res = f_write(&writeFil, buffer, strlen(buffer), &bytes_written);

    // Close the file to save the data
    f_close(&writeFil);
    f_mount(NULL, Path, 0);

    xil_printf(buffer);

    return res;
}


void filter2d_SW(
		uint8_t* img_in,
		char* kernel,
		uint8_t* img_out,
		int rows,
		int cols
)
{
    int local_kernel[KERNEL_DIM * KERNEL_DIM];
    for (int k=0; k < KERNEL_DIM * KERNEL_DIM; k++) 
    {
        local_kernel[k] = kernel[k];
    } 

    for (int r = 1; r < rows-1; r++)
    {
        for (int c = 1; c < cols-1; c++)
        {
        	int img_temp=0;
    		for(int i=0; i<KERNEL_DIM; i++){
    			for(int j=0; j<KERNEL_DIM; j++){
    				 img_temp += img_in[(r+i-1)*IMG_WIDTH + c+j-1] * local_kernel[i*KERNEL_DIM+j];
    			}
    		}
    		img_out[(r-1)*(IMG_WIDTH-2)+c-1] = img_temp;
        }
    }
}


void Window2D(
        int      width,
        int       height,
        uint8_t* img_in,
        uint32_t* img_out)
{
    // Line buffers - used to store [KERNEL_DIM-1] entire lines of pixels
    // Width dimension sized for padded image
    uint8_t LineBuffer[KERNEL_DIM-1][width + KERNEL_DIM - 1];
    // Sliding window of [KERNEL_DIM][KERNEL_DIM] pixels
    struct window Window;

    // Input is not padded but windows must contain padding 
    const int pad_r = KERNEL_DIM / 2;  // 1 for 3x3
    const int pad_c = KERNEL_DIM / 2;  // 1 for 3x3
    const int padded_height = height + 2 * pad_r;
    const int padded_width  = width  + 2 * pad_c;

    int num_windows = 0;
    int num_fifo_chunks = 0; 

    static int col_ptr = 0;
    static int row_ptr = 0;
    int ramp_up = padded_width*(KERNEL_DIM-1)+(KERNEL_DIM-1);
    int num_pixels = padded_width*padded_height;


    for (int n=0; n<num_pixels; n++)
    {

        bool is_pad = (row_ptr < pad_r) || (row_ptr >= height + pad_r) ||
                      (col_ptr < pad_c) || (col_ptr >= width  + pad_c);
        uint8_t new_pixel = is_pad ? (u8)0 : img_in[n];

        // Shift the window and add a column of new pixels from the line buffer
        for(int i = 0; i < KERNEL_DIM; i++) {
            for(int j = 0; j < KERNEL_DIM-1; j++) {
                Window.pix[i][j] = Window.pix[i][j+1];
            }
            Window.pix[i][KERNEL_DIM-1] = (i<KERNEL_DIM-1) ? LineBuffer[i][col_ptr] : new_pixel;
        }

        // Shift pixels in the line buffer column, add the newest pixel
        for(int i = 0; i < KERNEL_DIM-1; i++) {
            LineBuffer[i][col_ptr] = LineBuffer[i+1][col_ptr];
        }
        LineBuffer[KERNEL_DIM-2][col_ptr] = new_pixel;

        // Output once the sliding window has fully ramped up (line buffers filled
        // and horizontal window primed), then emit every pixel except the last
        // FILTER_H_SIZE-1 positions of each row (right-border ramp-down).
        if (n >= ramp_up && col_ptr >= KERNEL_DIM-1) {
            writeToBuffer(Window);
            num_windows++;
        }

        if (num_windows == FIFO_DEPTH)
        {
            num_windows = 0;
            saveBuffer(img_out, num_windows, num_fifo_chunks);
            num_fifo_chunks++;
        }
    
        // Update the pointers
        if (col_ptr==(padded_width-1)) {
            col_ptr = 0; 
            row_ptr++;
        } else {
            col_ptr++;
        }
    }

    // Save the left over buffers 
    saveBuffer(img_out, num_windows, num_fifo_chunks);
}

void writeToBuffer(struct window currWindow) {
    u32 line1, line2, line3;

    line1 = (currWindow.pix[0][0] << 24) | (currWindow.pix[0][1] << 16)
             | (currWindow.pix[0][1] << 8) | (currWindow.pix[1][0]);
    line1 = (currWindow.pix[1][1] << 24) | (currWindow.pix[1][2] << 16)
             | (currWindow.pix[2][0] << 8) | (currWindow.pix[2][1]);
    line2 = 0x000000FF & currWindow.pix[2][2];  
    
    MYCONV2FULL_mWriteMemory(BASE_ADDR, line1);
    MYCONV2FULL_mWriteMemory(BASE_ADDR, line2);
    MYCONV2FULL_mWriteMemory(BASE_ADDR, line3);
}

void saveBuffer(
        uint32_t* dst,
        int numOfBuffers,
        int numOfChunks)
{
    for (int j=0; j < numOfBuffers; j++){
        dst[numOfChunks*FIFO_DEPTH + j] = MYCONV2FULL_mReadMemory(BASE_ADDR + j*4);
    }
}
