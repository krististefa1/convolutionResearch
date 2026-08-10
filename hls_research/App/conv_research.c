/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * conv_research.c: Adjustable conv application
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
#include <xil_printf.h>
#include <xstatus.h>


// Config
 
 // Image dimensions — hardcoded in kernel
 #define KERNEL_DIM 9
 #define KERNEL_SPACE (KERNEL_DIM * KERNEL_DIM)
 #define IMG_WIDTH   7680 //128, 500, 1920, 3840, 7680
 #define IMG_HEIGHT  4320 //128, 500, 1080, 2160, 4320
 #define IMG_SIZE    (IMG_WIDTH * IMG_HEIGHT)

 //const char srcImg[] = "logo.txt"; //house, droid, logo, dolphin, duck
 const char srcImg[] = "duck.bif"; //house, droid, logo, dolphin, duck
 //const char dstImg[] = "logoOut.txt";
 const char dstImg[] = "duck.bof";
 const char timeLog[] = "conDt.txt";
 
 // DDR buffer addresses (pick unused regions in your memory map)
 // These must be in a cacheable/DMA-accessible region.

 #define SRC_BASE_ADDR    0x10000000
 #define DST_BASE_ADDR    (SRC_BASE_ADDR + 0x2000000) //32 MB
 #define KERNEL_BASE_ADDR  (DST_BASE_ADDR + 0x2000000) //32 MB
 

// Instances
static FIL fil;
FRESULT res;
UINT NumBytesRead;

// Consts
TCHAR *Path = "0:/";
XTime tHWStart,tHWEnd,tSWStart,tSWEnd;

int main ()
{
    XFilter2d_accel filter2d_accel_inst;
    int status;
    init_platform();
    xil_printf("\r\n=== filter2d_accel Host ===\r\n");

    // ---- Initialize the filter2d_accel IP driver ----
    status = XFilter2d_accel_Initialize(&filter2d_accel_inst, XPAR_FILTER2D_ACCEL_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: XFilter2d_accel_Initialize failed (%d)\r\n", status);
        return -1;
    }
    xil_printf("filter2d_accel IP initialized.\r\n");

    // ---- Pointers to DDR buffers ----
    u8  *src_buf   = (u8  *)SRC_BASE_ADDR;
    u8  *dst_buf   = (u8  *)DST_BASE_ADDR;
    char *kernel_buf = (char *)KERNEL_BASE_ADDR;
    u32 pixelsRead;

    // ---- Load input image ----
    // Try SD card first
    if (load_sd_to_memory(srcImg, src_buf, &pixelsRead, 1) != XST_SUCCESS) {
        xil_printf("SD load failed\r\n");
        return -1;
    }

    // ---- Copy kernel coefficients into DDR ----
    memcpy(kernel_buf, kernel_identity9, KERNEL_SPACE * sizeof(u8));

    // ---- Clear destination ----
    memset(dst_buf, 0, IMG_SIZE * sizeof(u8));

    // ---- Flush caches before DMA ----
    Xil_DCacheFlushRange((INTPTR)src_buf,   IMG_SIZE * sizeof(u8));
    Xil_DCacheFlushRange((INTPTR)kernel_buf, KERNEL_SPACE * sizeof(char));
    Xil_DCacheFlushRange((INTPTR)dst_buf,   IMG_SIZE * sizeof(u8));

    // ---- Program the IP ----
    XFilter2d_accel_Set_src(&filter2d_accel_inst,   (u64)SRC_BASE_ADDR);
    XFilter2d_accel_Set_dst(&filter2d_accel_inst,   (u64)DST_BASE_ADDR);
    //XFilter2d_accel_opt_Set_kernel(&filter2d_accel_inst, (u64)KERNEL_BASE_ADDR);
    XFilter2d_accel_Set_height(&filter2d_accel_inst,  (u32)IMG_HEIGHT);
    XFilter2d_accel_Set_width(&filter2d_accel_inst,  (u32)IMG_WIDTH);
    XFilter2d_accel_Write_kernel_Bytes(&filter2d_accel_inst, 0, kernel_buf, KERNEL_SPACE * sizeof(char));
    xil_printf("Starting filter2d_accel IP (%dx%d) w/K:%d  ...\r\n", IMG_WIDTH, IMG_HEIGHT, KERNEL_DIM);

    // ---- Start and wait ----
    XTime_GetTime(&tHWStart);
    XFilter2d_accel_Start(&filter2d_accel_inst);

    // Poll until done
    while (!XFilter2d_accel_IsDone(&filter2d_accel_inst))
        ;
    XTime_GetTime(&tHWEnd);
    xil_printf("filter2d_accel IP done.\r\n");

    // ---- Invalidate cache to read result from DDR ----
    Xil_DCacheInvalidateRange((INTPTR)dst_buf, IMG_SIZE * sizeof(char));

    // ---- Save result to SD card ----
    if ((write_data_to_sd(dstImg, dst_buf, IMG_SIZE, 1)) != XST_SUCCESS) {
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
    sprintf(buffer, "Size %dx%d w/K (%d): HW time %.2f us, SW time %.2f us\r\n",\
            IMG_HEIGHT, IMG_WIDTH, KERNEL_DIM,\
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
    char local_kernel[KERNEL_DIM * KERNEL_DIM];
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