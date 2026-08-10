/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * mem_conv.c: Optimized Memory based convolution
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


// Config
 
 // Image dimensions — hardcoded in kernel
 #define KERNEL_DIM 3
 #define IMG_WIDTH   128
 #define out_IMG_WIDTH (IMG_WIDTH-2)
 #define IMG_HEIGHT  128
 #define out_IMG_HEIGHT (IMG_HEIGHT-2)
 #define IMG_SIZE    (IMG_WIDTH * IMG_HEIGHT)
 #define out_IMG_SIZE (out_IMG_WIDTH * out_IMG_HEIGHT)
 
 // DDR buffer addresses (pick unused regions in your memory map)
 // These must be in a cacheable/DMA-accessible region.
 #define SRC_BASE_ADDR    0x10000000
 #define DST_BASE_ADDR    0x10200000
 #define KERNEL_BASE_ADDR  0x10400000
 

// Instances
static FIL fil;
static FATFS fs;
FRESULT res;
UINT NumBytesRead;

// Consts
TCHAR *Path = "0:/";
static char srcImg[] = "sample.txt";
static char dstImg[] = "conOut.txt";
static char timeLog[] = "optDt.txt";
XTime tHWStart,tHWEnd,tSWStart,tSWEnd;



int fileRead(u8* input) 
{
    char line[IMG_WIDTH * 4 + 2]; //(grayscale + space) + fgets space
    res = f_mount(&fs, "0:/", 1);
    if (res != FR_OK) {
        xil_printf("ERROR: f_mount failed (%d)\r\n", res);
        return -1;
    }
 
    res = f_open(&fil, srcImg, FA_READ);
    if (res != FR_OK) {
        xil_printf("ERROR: cannot open %s (%d)\r\n", srcImg, res);
        f_mount(NULL, Path, 0);
        return -1;
    }

    int pixelCount = 0;
    while (f_gets(line, sizeof(line), &fil) != NULL && pixelCount < IMG_SIZE) {
        char *pixel = strtok(line, " \t\r\n");
        while (pixel != NULL && pixelCount < IMG_SIZE){
            int clip = atoi(pixel);
            if (clip < 0) { clip = 0;} 
            if (clip > 255) {clip = 255;}
            input[pixelCount++] = clip;
            pixel = strtok(NULL, " \t\r\n");
        }
    }
    
    f_close(&fil);
    f_mount(NULL, Path, 0);
 
    if (pixelCount != IMG_SIZE) {
        xil_printf("ERROR: read %u / %u bytes\r\n", pixelCount, IMG_SIZE);
        return -1;
    }
    
    return 0;
}

int fileWrite(u8* output)
{
    res = f_mount(&fs, "0:/", 1);
    if (res != FR_OK) {
        xil_printf("ERROR: f_mount failed (%d)\r\n", res);
        return -1;
    }
 
    res = f_open(&fil, dstImg, FA_CREATE_ALWAYS|FA_WRITE);
    if (res != FR_OK) {
        xil_printf("ERROR: cannot open for writing %s (%d)\r\n", dstImg, res);
        f_mount(NULL, Path, 0);
        return -1;
    }

    for (int i = 0; i < out_IMG_HEIGHT; i++) {
        for (int j = 0; j < out_IMG_WIDTH; j++) {
            if (j > 0) f_printf(&fil, " "); //spaces
            f_printf(&fil, "%d", output[i * out_IMG_WIDTH + j]);
        }
        f_printf(&fil, "\n");
    }
    
    f_close(&fil);
    f_mount(NULL, Path, 0);
 
    xil_printf("Saved %s (%dx%d)\r\n", dstImg, out_IMG_WIDTH, out_IMG_HEIGHT);

    return 0;
}

int main ()
{
    XFilter2d_accel_opt filter2d_accel_inst;
    int status;
    init_platform();
    xil_printf("\r\n=== filter2d_accel Host ===\r\n");

    // ---- Initialize the filter2d_accel IP driver ----
    status = XFilter2d_accel_opt_Initialize(&filter2d_accel_inst, XPAR_FILTER2D_ACCEL_OPT_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: XFilter2d_accel_Initialize failed (%d)\r\n", status);
        return -1;
    }
    xil_printf("filter2d_accel IP initialized.\r\n");

    // ---- Pointers to DDR buffers ----
    u8  *src_buf   = (u8  *)SRC_BASE_ADDR;
    u8  *dst_buf   = (u8  *)DST_BASE_ADDR;
    char *kernel_buf = (char *)KERNEL_BASE_ADDR;

    // ---- Load input image ----
    // Try SD card first
    if (fileRead(src_buf) != 0) {
        xil_printf("SD load failed\r\n");
    }

    // ---- Copy kernel coefficients into DDR ----
    memcpy(kernel_buf, kernel_identity, 9 * sizeof(u8));

    // ---- Clear destination ----
    memset(dst_buf, 0, out_IMG_SIZE * sizeof(u8));

    // ---- Flush caches before DMA ----
    Xil_DCacheFlushRange((INTPTR)src_buf,   IMG_SIZE * sizeof(u8));
    Xil_DCacheFlushRange((INTPTR)kernel_buf, 9 * sizeof(char));
    Xil_DCacheFlushRange((INTPTR)dst_buf,   out_IMG_SIZE * sizeof(u8));

    // ---- Program the IP ----
    XFilter2d_accel_opt_Set_src(&filter2d_accel_inst,   (u64)SRC_BASE_ADDR);
    XFilter2d_accel_opt_Set_dst(&filter2d_accel_inst,   (u64)DST_BASE_ADDR);
    //XFilter2d_accel_opt_Set_kernel(&filter2d_accel_inst, (u64)KERNEL_BASE_ADDR);
    XFilter2d_accel_opt_Set_height(&filter2d_accel_inst,  (u32)IMG_HEIGHT);
    XFilter2d_accel_opt_Set_width(&filter2d_accel_inst,  (u32)IMG_WIDTH);
    XFilter2d_accel_opt_Write_kernel_Bytes(&filter2d_accel_inst, 0, kernel_buf, 9 * sizeof(char));
    xil_printf("Starting filter2d_accel IP (%dx%d) ...\r\n", IMG_WIDTH, IMG_HEIGHT);

    // ---- Start and wait ----
    XTime_GetTime(&tHWStart);
    XFilter2d_accel_opt_Start(&filter2d_accel_inst);

    // Poll until done
    while (!XFilter2d_accel_opt_IsDone(&filter2d_accel_inst))
        ;
    XTime_GetTime(&tHWEnd);
    xil_printf("filter2d_accel IP done.\r\n");

    // ---- Invalidate cache to read result from DDR ----
    Xil_DCacheInvalidateRange((INTPTR)dst_buf, out_IMG_SIZE * sizeof(int));

    // ---- Save result to SD card ----
    fileWrite(dst_buf);

    // ---- Quick sanity check: print a few output pixels ----
    xil_printf("First 5 output pixels:");
    for (int i = 0; i < 5; i++)
        xil_printf(" %d", dst_buf[i]);
    xil_printf("\r\n");

    xil_printf("Last 5 output pixels:");
    for (int i = 0; i < 5; i++)
        xil_printf(" %d", dst_buf[(out_IMG_SIZE - 5) + i]);
    xil_printf("\r\n");

    XTime_GetTime(&tSWStart);
    xil_printf("Running SW \r\n");
    filter2d_SW(src_buf, kernel_buf, dst_buf, IMG_HEIGHT, IMG_WIDTH);
    XTime_GetTime(&tSWEnd);

    xil_printf("=== Saving run ===\r\n");
    res = timePrint();
    xil_printf("=== Done ===\r\n");
    cleanup_platform();
    return 0;
}

FRESULT timePrint()
{
    char buffer[256];
    FIL writeFil;
    FRESULT res;
    UINT bytes_written;
    sprintf(buffer, "HW time %.2f us, SW time %.2f us\r\n",\
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