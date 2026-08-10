// Copyright (C) 2024 Advanced Micro Devices, Inc
//
// SPDX-License-Identifier: MIT

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "filter2d.h"
#define totalSize MAX_IMAGE_HEIGHT * MAX_IMAGE_WIDTH

#include <iostream>
using namespace std;

int main()
{
    unsigned char* input = (unsigned char*)malloc(totalSize);
    unsigned char* output= (unsigned char*)malloc(totalSize);
    int gold;
    int in;

    int imgheight = 500;
    int imgwidth = 500;
    int imageSize = imgheight * imgwidth;

    // char kernel[49] =
    // {0, 0, 0, 0, 0, 0, 0,
    // 0, 0, 0, 0, 0, 0, 0,
    // 0, 0, 0, 0, 0, 0, 0,
    // 0, 0, 0, 1, 0, 0, 0,
    // 0, 0, 0, 0, 0, 0, 0,
    // 0, 0, 0, 0, 0, 0, 0,
    // 0, 0, 0, 0, 0, 0, 0};
    // char kernel[25] =
    // {0, 0, 0, 0, 0,
    // 0, 0, 0, 0, 0,
    // 0, 0, 1, 0, 0,
    // 0, 0, 0, 0, 0};

    char kernel[81] =
    {0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 1, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0};
    
    //const char kernel[9] = {0,0,0,0,1,0,0,0,0};
    
    FILE * fp = fopen("src.txt","r");
//    FILE * fpo = fopen("dst.txt","r");
    FILE * fpo = fopen("filter2d_out.txt","r");
    FILE * fpoo = fopen("dst.txt","w");
    
    for(int i=0; i<imageSize; i++)
    {
        fscanf(fp, "%d", &in);
        input[i] = in;
    }

	filter2d_accel(kernel, imgheight, imgwidth, input,output);
    
    int tf = 0;
    unsigned char out_temp =0;
    bool faultFound = false;

    for(int i=0; i<imageSize; i++)
    {
        fscanf(fpo, "%d", &gold);
        fprintf(fpoo, "%d\n", output[i]);

        if ((output[i] - gold != 0) && (faultFound == false))
        {
            tf = 1;
            out_temp = output[i];
            faultFound = true;
            fprintf(stdout,"\n **** %d ****   \n",i);
            fprintf(stdout,"\n  ** out %d **   \n",out_temp);
            fprintf(stdout,"\n  ** gold %d **   \n",gold);

        }        
    }

    fclose(fp);
    fclose(fpo);
    fclose(fpoo);

    if (tf == 1)
    {
        fprintf(stdout, "*******************************************\n");
        fprintf(stdout, "FAIL: Output DOES NOT match the golden output\n");
        fprintf(stdout, "*******************************************\n");
        return 1;
    } 
    else 
    {
        fprintf(stdout, "*******************************************\n");
        fprintf(stdout, "PASS: The output matches the golden output!\n");
        fprintf(stdout, "*******************************************\n");
        return 0;
    }
    free(input);
    free(output);
}