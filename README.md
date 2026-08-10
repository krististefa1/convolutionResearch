# Convolution Research
- Storage repo for research code and data (currently Summer 2026)

## Projects
### HDL Research
- Files comprising HDL AXI-Full Kernel as given in [[Tutorial - Unit 4.pdf]]
- Source files are VHDL files and Zynq application code 

### HLS Research
- Current work on convolution using the Zynq and HLS 
- Aspects improved/changed from the sample:
	- Use of MAX sizes to allow semi-dynamic processor app code 
	- No border loss on the output 
	- Rework of const defines to allow dynamic code
- Allows for different images based on a set of defines

### Sample Optimized 
- Sample HLS code, notebook, and image provided by Xilinx
- Uses parallelism techniques on a static image of 128 x 128

### Matlab/Images 
- Miscellaneous Matlab scripts and the images used for testing:
	- house - 128x128
	- droid - 500x500
	- logo - 1920 x 1080
	- dolphin - 3840 x 2160
	- duck - 7680 x 4320