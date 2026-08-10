/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * sobel_app.c: Adjustable 2-kernel conv application
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

#include "sobel_app.h"
#include <xil_printf.h>
#include <xstatus.h>


// Config
 
 // Image dimensions — hardcoded in kernel
 #define KERNEL_DIM 3
 #define KERNEL_SPACE (KERNEL_DIM * KERNEL_DIM)

#define LOGO //mono, faro, buho, logo

#ifdef LOGO
 #define IMG_WIDTH   1920 
 #define IMG_HEIGHT  1080 
 const char srcImg[] = "logo.bif"; 
 const char dstImg[] = "logo.bof";
#endif

#ifdef BUHO
 #define IMG_WIDTH   1920 
 #define IMG_HEIGHT  566 
 const char srcImg[] = "buho.bif"; 
 const char dstImg[] = "buho.bof";
#endif

#ifdef FARO
 #define IMG_WIDTH   768 
 #define IMG_HEIGHT  512 
 const char srcImg[] = "faro.bif"; 
 const char dstImg[] = "faro.bof";
#endif

#ifdef MONO
 #define IMG_WIDTH   512 
 #define IMG_HEIGHT  512 
 const char srcImg[] = "mono.bif"; 
 const char dstImg[] = "mono.bof";
#endif

 #define IMG_SIZE    (IMG_WIDTH * IMG_HEIGHT)
 const char timeLog[] = "conDt.txt";
 
 // DDR buffer addresses (pick unused regions in your memory map)
 // These must be in a cacheable/DMA-accessible region.

 #define SRC_BASE_ADDR    0x10000000
 #define DST_BASE_ADDR    (SRC_BASE_ADDR + 0x2000000) //32 MB
 #define KERNEL_A_BASE_ADDR  (DST_BASE_ADDR + 0x2000000) //32 MB
 #define KERNEL_B_BASE_ADDR (KERNEL_A_BASE_ADDR + 0x200) // 512 B
 

// Instances
static FIL fil;
FRESULT res;
UINT NumBytesRead;

// Consts
TCHAR *Path = "0:/";
XTime tHWStart,tHWEnd,tSWStart,tSWEnd;

int main ()
{
    XSobel2d_accel sobel2d_accel_inst;
    int status;
    init_platform();
    xil_printf("\r\n=== sobel2d_accel Host ===\r\n");

    // ---- Initialize the sobel2d_accel IP driver ----
    status = XSobel2d_accel_Initialize(&sobel2d_accel_inst, XPAR_SOBEL2D_ACCEL_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: XSobel2d_accel_Initialize failed (%d)\r\n", status);
        return -1;
    }
    xil_printf("sobel2d_accel IP initialized.\r\n");

    // ---- Pointers to DDR buffers ----
    u8  *src_buf   = (u8  *)SRC_BASE_ADDR;
    u8  *dst_buf   = (u8  *)DST_BASE_ADDR;
    char *kernelA_buf = (char *)KERNEL_A_BASE_ADDR;
    char *kernelB_buf = (char *)KERNEL_B_BASE_ADDR;
    u32 pixelsRead;

    // ---- Load input image ----
    // Try SD card first
    if (load_sd_to_memory(srcImg, src_buf, &pixelsRead, 1) != XST_SUCCESS) {
        xil_printf("SD load failed\r\n");
        return -1;
    }

    // ---- Copy kernel coefficients into DDR ----
    memcpy(kernelA_buf, sobel3_A, KERNEL_SPACE * sizeof(u8));
    memcpy(kernelB_buf, sobel3_B, KERNEL_SPACE * sizeof(u8));

    // ---- Clear destination ----
    memset(dst_buf, 0, IMG_SIZE * sizeof(u8));

    // ---- Flush caches before DMA ----
    Xil_DCacheFlushRange((INTPTR)src_buf,   IMG_SIZE * sizeof(u8));
    Xil_DCacheFlushRange((INTPTR)kernelA_buf, KERNEL_SPACE * sizeof(char));
    Xil_DCacheFlushRange((INTPTR)kernelB_buf, KERNEL_SPACE * sizeof(char));
    Xil_DCacheFlushRange((INTPTR)dst_buf,   IMG_SIZE * sizeof(u8));

    // ---- Program the IP ----
    XSobel2d_accel_Set_src(&sobel2d_accel_inst,   (u64)SRC_BASE_ADDR);
    XSobel2d_accel_Set_dst(&sobel2d_accel_inst,   (u64)DST_BASE_ADDR);
    //XSobel2d_accel_opt_Set_kernel(&sobel2d_accel_inst, (u64)KERNEL_BASE_ADDR);
    XSobel2d_accel_Set_height(&sobel2d_accel_inst,  (u32)IMG_HEIGHT);
    XSobel2d_accel_Set_width(&sobel2d_accel_inst,  (u32)IMG_WIDTH);
    XSobel2d_accel_Write_kernelA_Bytes(&sobel2d_accel_inst, 0, kernelA_buf, KERNEL_SPACE * sizeof(char));
    XSobel2d_accel_Write_kernelB_Bytes(&sobel2d_accel_inst, 0, kernelB_buf, KERNEL_SPACE * sizeof(char));
    xil_printf("Starting sobel2d_accel IP (%dx%d) w/K:%d  ...\r\n", IMG_WIDTH, IMG_HEIGHT, KERNEL_DIM);

    // ---- Start and wait ----
    XTime_GetTime(&tHWStart);
    XSobel2d_accel_Start(&sobel2d_accel_inst);

    // Poll until done
    while (!XSobel2d_accel_IsDone(&sobel2d_accel_inst))
        ;
    XTime_GetTime(&tHWEnd);
    xil_printf("sobel2d_accel IP done.\r\n");

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
    sobel2d_SW(src_buf, kernelA_buf, kernelB_buf, dst_buf, IMG_HEIGHT, IMG_WIDTH);
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
    sprintf(buffer, "Sobel 2D: Size %dx%d w/K (%d): HW time %.2f us, SW time %.2f us\r\n",\
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


void sobel2d_SW(
		uint8_t* img_in,
		char* kernelA,
        char* kernelB,
		uint8_t* img_out,
		int rows,
		int cols
)
{
    char local_kernelA[KERNEL_DIM * KERNEL_DIM];
    char local_kernelB[KERNEL_DIM * KERNEL_DIM];
    for (int k=0; k < KERNEL_DIM * KERNEL_DIM; k++) 
    {
        local_kernelA[k] = kernelA[k];
        local_kernelB[k] = kernelB[k];
    } 

    for (int r = 1; r < rows-1; r++)
    {
        for (int c = 1; c < cols-1; c++)
        {
        	int img_tempX=0;
            int img_tempY=0;
    		for(int i=0; i<KERNEL_DIM; i++){
    			for(int j=0; j<KERNEL_DIM; j++){
    				img_tempX += img_in[(r+i-1)*IMG_WIDTH + c+j-1] * local_kernelA[i*KERNEL_DIM+j];
                    img_tempY += img_in[(r+i-1)*IMG_WIDTH + c+j-1] * local_kernelB[i*KERNEL_DIM+j];
    			}
    		}
    		img_out[(r-1)*(IMG_WIDTH-2)+c-1] = (ABS(img_tempX)+ ABS(img_tempY));
        }
    }
}