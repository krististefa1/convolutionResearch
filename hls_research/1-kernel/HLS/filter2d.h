// Copyright (C) 2024 Advanced Micro Devices, Inc
//
// SPDX-License-Identifier: MIT

typedef unsigned char U8;

#pragma once

#include <stdio.h>
#include <string.h>
#include <assert.h>

#define MAX_IMAGE_WIDTH     7680
#define MAX_IMAGE_HEIGHT    4320

#define FILTER_W_SIZE		3
#define FILTER_H_SIZE		3

#ifndef MIN
#define MIN(a,b) ((a<b)?a:b)
#endif
#ifndef MAX
#define MAX(a,b) ((a<b)?b:a)
#endif

struct window {
	U8 pix[FILTER_W_SIZE][FILTER_H_SIZE];
};

extern "C" {

void filter2d_accel(
		char kernel[FILTER_W_SIZE*FILTER_H_SIZE],
		int height,
		int width,

		U8 src[MAX_IMAGE_WIDTH*MAX_IMAGE_HEIGHT],
		U8 dst[MAX_IMAGE_WIDTH*MAX_IMAGE_HEIGHT]
);


}

