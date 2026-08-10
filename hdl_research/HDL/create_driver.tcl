proc create_driver {args} {
	set ip_name ""
	set overwrite_yaml 0
	set write_cmake 1
	set type "basic"
	set force_driver 0
	set xsa ""
	set repo ""
	set required "" 
	set metadata_source xsa
	set get_ip_names 0
	set driver_src ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
		if {[lindex $args $i] == "-compat"} {
			set compat [lindex $args [expr {$i + 1}]]
		}
		if {[lindex $args $i] == "-overwrite_yaml"} {
			set overwrite_yaml 1
		}
		if {[lindex $args $i] == "-force_driver"} {
			set force_driver 1
		}
		if {[lindex $args $i] == "-get_ip_names"} {
			set get_ip_names 1
		}
		if {[lindex $args $i] == "-xsa"} {
			set xsa [lindex $args [expr {$i + 1}]]
		}
		if {[lindex $args $i] == "-repo"} {
			set repo [lindex $args [expr {$i + 1}]]
		}
		if {[lindex $args $i] == "-required"} {
			set required [lindex $args [expr {$i + 1}]]
		}
		if {[lindex $args $i] == "-driver_src"} {
			set driver_src [lindex $args [expr {$i + 1}]]
		}
		if {[lindex $args $i] == "-type"} {
			set type [lindex $args [expr {$i + 1}]]
			if {$type != "advanced" && $type != "basic"} {
				puts "Error: Unexpected value for -type: ${type}. Supported values are basic or advanced"
				puts "		 Use help -create_driver for more info"
				return ""
			}
		}
    }
	
	if {$xsa == ""} {
		puts "Error: The XSA is needed to extract the hardware metadata"
		puts "Example -xsa /path/to/xsa"
		return ""
	}
	
	if {$get_ip_names == 1} {
		hsi::open_hw_design $xsa
		set proc [lindex [hsi::get_cells -hier -filter {IP_TYPE==PROCESSOR} ] 0] 
		puts "Info: IP Names on $proc in XSA are:"
		set ip_list ""
		foreach cell [hsi::get_mem_ranges -of_objects [lindex [hsi::get_cells -hier -filter {IP_TYPE==PROCESSOR} ] 0]] {
			if {[common::get_property IS_PL [hsi::get_cells -hier $cell]] == 1} {
				lappend ip_list [common::get_property IP_NAME [hsi::get_cells -hier $cell]]
			}
		}
		hsi::close_hw_design [hsi::current_hw_design]
		return $ip_list
	}
	
	if {$type == "basic"} {
		puts "Info: -type is set to basic (default). Use -type to change this. Supported values are basic or advanced"
	}
	
	if {$ip_name == ""} {
		puts "Error: No -ip_name provided. Use -get_ip_names -xsa path/to/xsa to get a list of ip_names for your XSA"
		return ""
	}
	
	if {$repo == ""} {
		puts "Info: No -repo passed."
		set driver_repo repo/XilinxProcessorIPLib/drivers
		if {![file exists $driver_repo]} {
			file mkdir $driver_repo
		}
		puts "Info: Setting driver repo to $driver_repo"
	} else {
		set driver_repo ${repo}/XilinxProcessorIPLib/drivers
		puts "Info: Creating repo structure at $driver_repo"
		file mkdir $driver_repo 
	}
	
	set driver ${driver_repo}/${ip_name}_v1_0
	if {![file exists $driver]} {
		file mkdir ${driver}/data
		file mkdir ${driver}/src
		file mkdir ${driver}/examples		
	} else {
		if {$force_driver != 1} {
			puts "Warning: $driver already exists. Use -force_driver to force the overwrite"
			return ""
		}
	}
	
	if {$driver_src != ""} {
		set driver_files [glob -nocomplain -directory $driver_src -type f *.c *.h]
		if {$driver_files != ""} {
			foreach driver_file $driver_files {
				if {[regexp {selftest} $driver_file]} {
					file copy $driver_file ${driver}/examples
				}
			}
		} else {
			puts "Info: No Valid .c or .h found at $driver_src"
		}
	} 
	
	set yaml [glob -nocomplain -directory ${driver}/data -type f *.yaml]
	if {$yaml != "" && $overwrite_yaml == 0} {
		puts "Warning: There is a YAML file in ${driver}/data. Use the -overwrite_yaml to force overwrite"
		return ""
	}
		
	# Get the compatible string. 
	puts "Info: Using metadata from $metadata_source to extract compatibility string"
	set compat [get_compat -xsa $xsa -ip_name $ip_name]

	#Get Required
	set default_required {compatible reg}
	set config "X[string toupper [string range $ip_name 0 0]][string range $ip_name 1 end]_Config"
	if {$required != ""} {
		foreach req [split $required] {
			lappend default_required $reg
		}
	}
	
	if {[has_connected_interrupt -open_xsa -xsa $xsa -ip_name $ip_name] == 1} {
		lappend default_required "interrupts"
		lappend default_required "interrupt-parent"
	}
 			
	#Get Examples
	set examples [glob -nocomplain -directory ${driver}/examples -type f *.c]
		
	#Create YAML
	set yaml ${driver}/data/${ip_name}.yaml
	if {$type == "advanced"} {
		gen_yaml -yaml $yaml -compat $compat -config $config -required $default_required -examples $examples
	} else {
		gen_yaml -yaml $yaml -compat $compat -examples $examples
	}


	#Create init files
	if {$type == "advanced"} {	
		generate_init -driver $driver -ip_name $ip_name
		generate_header -driver $driver -ip_name $ip_name
		generate_source -driver $driver -ip_name $ip_name
	}
	
	set config_file ${driver}/src/x${ip_name}_g.c
	set fileId [open $config_file "w"]
	close $fileId
	puts "Info: dummy $config_file is generated"

	
		
	#Create CMakeLists.txt
	if {$write_cmake == 1} {
		generate_cmake -driver $driver -ip_name $ip_name -overwrite_cmake -driver_src $driver_src
	}
}

proc gen_yaml {args} {
	set yaml ""
	set compat ""
	set required ""
	set examples ""
	set config ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-yaml"} {
            set yaml [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-compat"} {
            set compat [lindex $args [expr {$i + 1}]]
        }
	    if {[lindex $args $i] == "-required"} {
            set required [lindex $args [expr {$i + 1}]]
        }
	    if {[lindex $args $i] == "-examples"} {
            set examples [lindex $args [expr {$i + 1}]]
        }
	    if {[lindex $args $i] == "-config"} {
            set config [lindex $args [expr {$i + 1}]]
        }
    }
	
	if {$yaml == ""} {
		puts "Error: No yaml passed to gen_yaml"
		return ""
	}

	if {$compat == ""} {
		puts "Error: No compat passed to gen_yaml"
		return ""
	}

	set systemTime [clock seconds]
	set date [clock format $systemTime -format %D]
	set year [clock format $systemTime -format %Y]
	
	set fileId [open $yaml "w"]
	puts $fileId "# Copyright (C) $year Advanced Micro Devices, Inc.  All rights reserved."
	puts $fileId "# Copyright (c) 2021 Xilinx, Inc.  All rights reserved."
	puts $fileId "# SPDX-License-Identifier: MIT"
	puts $fileId "%YAML 1.2"
	puts $fileId "---"
	puts $fileId "title: Bindings for [string toupper [file rootname [file tail $yaml]]]"
	puts $fileId ""
	puts $fileId "maintainers:"
	puts $fileId "  - firstname lastname <firstname.lastname@amd.com>"
	puts $fileId ""
	puts $fileId "type: driver"
	puts $fileId ""
	puts $fileId "properties:"
	puts $fileId "  compatible:"
	puts $fileId "    OneOf:"
	puts $fileId "      - items:"
	puts $fileId "        - enum:"
	foreach compat_string $compat {
		puts $fileId "          - ${compat_string}"
	}
	puts $fileId "  reg:"
	puts $fileId "    description: Add a description here"
	puts $fileId ""
	if {$config != ""} {
		puts $fileId "config:"
		puts $fileId "    - $config"
	}
	puts $fileId ""
	if {$required != ""} {
		puts $fileId "required:"
		foreach req $required {
			puts $fileId "    - $req"
		}
	} else {
		puts $fileId "additionalProperties:"
		puts $fileId "    - reg"
	}
	puts $fileId ""
	puts $fileId "examples:"
	foreach example $examples {
		puts $fileId "  [file tail $example]"
		puts $fileId "    - reg" 
	}
	puts $fileId "..."
	close $fileId
	puts "Info: $yaml created"
}

proc get_vlnv {args} {
	set vivado_install ""
	set driver_name ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-vivado_install"} {
            set vivado_install [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
    }
	
	if {$ip_name == ""} {
		puts "Error: No ip name passed. Use the -ip_name"
		return ""
	}
	
	if {$vivado_install == ""} {
		puts "Error: The -vivado_install is needed to extract the VLNV metadata"
		puts "Example -vivado_install /proj/xbuilds/2023.2_daily_latest/installs/lin64/Vivado/2023.2"
		return ""
	}
	
	set xlnx_ips [glob -nocomplain -directory ${vivado_install}/data/ip/xilinx -type d *]
	if {$xlnx_ips != ""} {
		set vendor ""
		set name ""
		set version ""
		foreach xlnx_ip $xlnx_ips {
			set fp [open ${xlnx_ip}/component.xml r]
			set file_data [read $fp]
			close $fp
			set data [split $file_data "\n"]
			foreach line $data {
				if {[regexp {<spirit:vendor>} $line]} {
					set vendor [string map {<spirit:vendor> "" </spirit:vendor> ""} [string trim $line]]
				}
				if {[regexp {<spirit:name>} $line]} {
					set name [string map {<spirit:name> "" </spirit:name> ""} [string trim $line]]
				}
				if {[regexp {<spirit:version>} $line]} {
					set version [string map {<spirit:version> "" </spirit:version> ""} [string trim $line]]
					break;
				}
			}
			if {$vendor != "" && $name != "" && $version != ""} {
				if {$name == $ip_name} {
					return "${vendor}:${name}:${version}"
				}
			}
		}
	} else {
		puts "Error: No IP found at ${vivado_install}/data/ip Please verify the path and try again."
	}
	
	return ""
}

proc has_connected_interrupt {args} {
	set ip_name ""
	set xsa ""
	set open_xsa 0
	set has_connected_interrupt 0
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-xsa"} {
            set xsa [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-open_xsa"} {
            set open_xsa 1
        }
    }
	
	if {$ip_name == ""} {
		puts "Error: No -ip_name passed to get_interrupts"
		return ""
	}
	

	if {$open_xsa == 1} {
		if {$xsa == ""} {
			puts "Error: No XSA passed to get_interrupts"
			return ""
		}
		hsi::open_hw_design $xsa
	}
	
	set cell [hsi::get_cells -hier -filter IP_NAME==$ip_name]
	if {$cell == ""} {
		puts "Error: No IP with name $ip_name is found in XSA"
		return ""
	}
	
	foreach interrupt_pin [hsi::get_pins -of_objects [hsi::get_cells $cell] -filter {TYPE==INTERRUPT&&DIRECTION==O}] {
		set net [hsi::get_nets -of_objects $interrupt_pin]
		if { [llength $net] != 0} {
			puts "Info: Interrupt connected on pin $interrupt_pin on $cell"
			set has_connected_interrupt 1
		}
	}
	
	if {$open_xsa == 1} {
		hsi::close_hw_design [hsi::current_hw_design]
	}
	
	return $has_connected_interrupt
}

#These functions should not be called by themselves as I didnt put in arg checks
proc get_compat {args} {
	set data ""
	set ip_name ""
	set xsa ""
	set vivado_install ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-data"} {
            set data [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-xsa"} {
            set xsa [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-vivado_install"} {
            set vivado_install [lindex $args [expr {$i + 1}]]
        }
    }
	

	if {$ip_name == ""} {
		foreach line $data {
			if {[regexp {supported_peripherals} $line]} {
				 set supported_peripherals [split [string range [string trim [lindex [split [string trim $line] "="] end]] 1 end-2]]
			}
		}
	} else {
		set supported_peripherals $ip_name
	}

	if {$vivado_install != ""} {
		set compat_string ""
		puts "Info: Finding VLNV for IP below:"
		foreach supported_peripheral $supported_peripherals {
			puts "* $supported_peripheral"
			set vlnv [get_vlnv -vivado_install $vivado_install -ip_name $supported_peripheral]
			if {$vlnv != ""} {
				set vlnv_data [split $vlnv ":"]
				if {[lindex $vlnv_data 0] == "xilinx.com" || [lindex $vlnv_data 0] == "user.org"} {
					set name [string map {_ -} [lindex $vlnv_data 2]]
					set ver [lindex $vlnv_data 3]
					lappend compat_string "xlnx,${name}-${ver}"
				} else {
					puts "Error: This is not a Xilinx IP. This is [lindex $vlnv_data 0]."
					return ""
				}
			}
		}
	} elseif {$xsa != ""} {
		hsi::open_hw_design $xsa
		set compat_string ""
		puts "Info: Finding VLNV for IP below:"
		foreach supported_peripheral $supported_peripherals {
			puts "* $supported_peripheral"
			set vlnv [common::get_property VLNV [hsi::get_cells -hier * -filter IP_NAME==$supported_peripheral]]
			if {$vlnv != ""} {
				set vlnv_data [split $vlnv]
				set vlnv_data [split [lindex $vlnv_data 0] ":"]
				set name [string map {_ -} [lindex $vlnv_data 2]]
				set ver [lindex $vlnv_data 3]
				lappend compat_string "xlnx,${name}-${ver}"
			}
		}
		hsi::close_hw_design [hsi::current_hw_design]	
	} else {
		puts "Error: User needs to provide either the -vivado_install or -xsa to extract the compatible string. If this is custom IP, then use the XSA"
		return 0
	}	

	return $compat_string
}

proc is_active {args} {
	set data ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-data"} {
            set data [lindex $args [expr {$i + 1}]]
        }
    }	
	
	foreach line $data {
		if {[regexp {driver_state} $line] && [regexp {ACTIVE} $line]} {
			return 1
		}
	}
	
	return 0
}

proc get_config {args} {
	set tcl ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-tcl"} {
            set tcl [lindex $args [expr {$i + 1}]]
        }
    }

	if {$tcl != ""} {
		set fp [open $tcl r]
		set file_data [read $fp]
		close $fp
		set data [split $file_data "\n"]
		foreach line $data {
			if {[regexp {define_config_file} $line]} {
				set tcl_data [split [string trim $line]]
				return [lindex $tcl_data 3]
			}
		}		
	} else {
		puts "Error: No drive tcl file found"
	}
	
	puts "Warning: No define_config_file found in ${tcl}. Defaulting to driver name: [file rootname [file tail $tcl]]"
	return " X[file rootname [file tail $tcl]] "
}

proc get_required {args} {
	set tcl ""
	set required ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-tcl"} {
            set tcl [lindex $args [expr {$i + 1}]]
        }
    }

	if {$tcl != ""} {
		set fp [open $tcl r]
		set file_data [read $fp]
		close $fp
		set data [split $file_data "\n"]
		foreach line $data {
			if {[regexp {define_config_file} $line]} {
				set tcl_data [split [string trim $line]]
				for {set i 7} {$i < [llength $tcl_data]} {incr i} {
					lappend required "xlnx,[string tolower [string range [lindex $tcl_data $i] 1 end-1]]"
				}
			}
		}		
		
	} else {
		puts "Error: No drive tcl file found"
	}
	
	return $required
}

proc generate_header {args} {
	set ip_name ""
	set driver ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-driver"} {
            set driver [lindex $args [expr {$i + 1}]]
        }
    }
	
	set header_file ${driver}/src/x${ip_name}.h 
	set driver_file [string tolower [file rootname [file tail $header_file]]]
	set driver_name X[string toupper [string range $ip_name 0 0]][string range $ip_name 1 end]
	
	set systemTime [clock seconds]
	set date [clock format $systemTime -format %D]
	set year [clock format $systemTime -format %Y]
	
	set fileId [open $header_file "w"]		
	puts $fileId "\/******************************************************************************"
	puts $fileId "* Copyright (C) 2015 - $year Xilinx, Inc. All rights reserved."
	puts $fileId "* Copyright 2022-${year} Advanced Micro Devices, Inc. All Rights Reserved."
	puts $fileId "* SPDX-License-Identifier: MIT"
	puts $fileId "******************************************************************************\/"
	puts $fileId ""
	puts $fileId "\/*****************************************************************************\/"
	puts $fileId "\/**"
	puts $fileId "*"
	puts $fileId "* @file ${driver_file}.h"
	puts $fileId "* @addtogroup ${driver_name} Overview"
	puts $fileId "* @\{"
	puts $fileId "* @details"
	puts $fileId "*"
	puts $fileId "* <pre>"
	puts $fileId "* MODIFICATION HISTORY:"
	puts $fileId "*"
	puts $fileId "* Ver Who Date     Changes"
	puts $fileId "* --- --- -------- ----------------------------------------------------"
	puts $fileId "* 1.0 name $date Initial release"
	puts $fileId "* </pre>"
	puts $fileId "*"
	puts $fileId "******************************************************************************/"
	puts $fileId ""
	puts $fileId "#ifndef [string toupper $driver_name]_H"
	puts $fileId "#define [string toupper $driver_name]_H"
	puts $fileId ""
	puts $fileId ""
	puts $fileId "#ifdef __cplusplus"
	puts $fileId "extern \"C\" \{"
	puts $fileId "#endif"
	puts $fileId ""
	puts $fileId "\/***************************** Include Files *********************************\/"
	puts $fileId ""
	puts $fileId "#include \"xil_types.h\""
	puts $fileId "#include \"xil_assert.h\""
	puts $fileId "#include \"xstatus.h\""
	puts $fileId ""
	puts $fileId "\/************************** Constant Definitions *****************************\/"
	puts $fileId ""
	puts $fileId "\/**************************** Type Definitions *******************************\/"
	puts $fileId "\/**"
	puts $fileId "* This typedef contains configuration information for the device"
	puts $fileId "*\/"
	puts $fileId "typedef struct \{"
	puts $fileId "#ifndef SDT"
	puts $fileId "	u16 DeviceId;"
	puts $fileId "#else"
	puts $fileId "	char *Name;"
	puts $fileId "#endif"
	puts $fileId "	UINTPTR BaseAddress;"
	puts $fileId "\} ${driver_name}_Config;"
	puts $fileId ""
	puts $fileId "\/**"
	puts $fileId "* The ${driver_name} driver instance data. The user is required to allocate a"
	puts $fileId "* variable of this type for every ${driver_name} device in the system. A pointer"
	puts $fileId "* to a variable of this type is then passed to the driver API functions."
	puts $fileId "*\/"
	puts $fileId "typedef struct \{"
	puts $fileId "	UINTPTR BaseAddress;"
	puts $fileId "	u32 IsReady;"
	puts $fileId "\} ${driver_name};"
	puts $fileId ""	
	puts $fileId "\/***************** Macros (Inline Functions) Definitions *********************\/"
	puts $fileId ""
	puts $fileId "\/************************** Function Prototypes ******************************\/"
	puts $fileId ""
	puts $fileId "\/**"
	puts $fileId "* Initialization functions in ${driver_name}_sinit.c"
	puts $fileId "*\/"
	puts $fileId "#ifndef SDT"
	puts $fileId "int ${driver_name}_Initialize(${driver_name} *InstancePtr, u16 DeviceId);"
	puts $fileId "${driver_name}_Config *${driver_name}_LookupConfig(u16 DeviceId);"
	puts $fileId "#else"
	puts $fileId "int ${driver_name}_Initialize(${driver_name} *InstancePtr, UINTPTR BaseAddress);"
	puts $fileId "${driver_name}_Config *${driver_name}_LookupConfig(UINTPTR BaseAddress);"
	puts $fileId "#endif"
	puts $fileId ""
	puts $fileId "\/**"
	puts $fileId "* API Basic functions implemented in [string tolower $driver_name].c"
	puts $fileId "*\/"
	puts $fileId "int ${driver_name}_CfgInitialize(${driver_name} *InstancePtr, ${driver_name}_Config * Config,"
	puts $fileId "		UINTPTR EffectiveAddr);"
	puts $fileId ""
	puts $fileId "#ifdef __cplusplus"
	puts $fileId "\}"
	puts $fileId "#endif"
	puts $fileId ""
	puts $fileId "#endif"
	close $fileId
	puts "Info: $header_file is generated"
}

proc generate_source {args} {
	set ip_name ""
	set driver ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-driver"} {
            set driver [lindex $args [expr {$i + 1}]]
        }
    }
	
	set source_file ${driver}/src/x${ip_name}.c 
	set driver_file [string tolower [file rootname [file tail $source_file]]]
	set driver_name X[string toupper [string range $ip_name 0 0]][string range $ip_name 1 end]
	
	set systemTime [clock seconds]
	set date [clock format $systemTime -format %D]
	set year [clock format $systemTime -format %Y]
	
	set fileId [open $source_file "w"]		
	puts $fileId "\/******************************************************************************"
	puts $fileId "* Copyright (C) 2015 - $year Xilinx, Inc. All rights reserved."
	puts $fileId "* Copyright 2022-${year} Advanced Micro Devices, Inc. All Rights Reserved."
	puts $fileId "* SPDX-License-Identifier: MIT"
	puts $fileId "******************************************************************************\/"
	puts $fileId ""
	puts $fileId "\/*****************************************************************************\/"
	puts $fileId "\/**"
	puts $fileId "*"
	puts $fileId "* @file ${driver_file}.c"
	puts $fileId "* @addtogroup ${driver_name} Overview"
	puts $fileId "* @\{"
	puts $fileId "* @details"
	puts $fileId "*"
	puts $fileId "* <pre>"
	puts $fileId "* MODIFICATION HISTORY:"
	puts $fileId "*"
	puts $fileId "* Ver Who Date     Changes"
	puts $fileId "* --- --- -------- ----------------------------------------------------"
	puts $fileId "* 1.0 name $date Initial release"
	puts $fileId "* </pre>"
	puts $fileId "*"
	puts $fileId "******************************************************************************/"
	puts $fileId ""
	puts $fileId ""
	puts $fileId "\/***************************** Include Files *********************************\/"
	puts $fileId ""
	puts $fileId "#include \"[string tolower ${driver_name}.h]\""
	puts $fileId "#include \"xstatus.h\""
	puts $fileId ""
	puts $fileId "\/************************** Constant Definitions *****************************\/"
	puts $fileId ""
	puts $fileId "\/**************************** Type Definitions *******************************\/"
	puts $fileId ""	
	puts $fileId "\/***************** Macros (Inline Functions) Definitions *********************\/"
	puts $fileId ""
	puts $fileId "\/************************** Variable Definitions *****************************\/"
	puts $fileId ""
	puts $fileId "\/************************** Function Prototypes ******************************\/"
	puts $fileId ""
	puts $fileId "\/*****************************************************************************\/"
	puts $fileId ""
	puts $fileId "\/**"
	puts $fileId "* Initialize the ${driver_name} instance provided by the caller based on the"
	puts $fileId "* given configuration data."
	puts $fileId "*"
	puts $fileId "* Nothing is done except to initialize the InstancePtr."
	puts $fileId "*\/"
    puts $fileId "\/*****************************************************************************\/"
	puts $fileId "int ${driver_name}_CfgInitialize(${driver_name} * InstancePtr, ${driver_name}_Config * Config,"
	puts $fileId "			UINTPTR EffectiveAddr)"
	puts $fileId "\{"
	puts $fileId "	\/* Assert arguments *\/"
	puts $fileId "	Xil_AssertNonvoid(InstancePtr != NULL);"
	puts $fileId ""
	puts $fileId "	\/* Set some default values. *\/"
	puts $fileId "	InstancePtr->BaseAddress = EffectiveAddr;"
	puts $fileId ""
	puts $fileId "	\/*"
	puts $fileId "	 * Indicate the instance is now ready to use, initialized without error"
	puts $fileId "	 *\/"
	puts $fileId "	InstancePtr->IsReady = XIL_COMPONENT_IS_READY;"
	puts $fileId "	return (XST_SUCCESS);"
	puts $fileId "\}"
	
	close $fileId
	puts "Info: $source_file is generated"
}

proc generate_init {args} {
	set ip_name ""
	set driver ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-driver"} {
            set driver [lindex $args [expr {$i + 1}]]
        }
    }
	
	set sinit_file ${driver}/src/x${ip_name}_sinit.c 
	set driver_file [string tolower [file rootname [file tail $sinit_file]]]
	set driver_name X[string toupper [string range $ip_name 0 0]][string range $ip_name 1 end]
	
	set systemTime [clock seconds]
	set date [clock format $systemTime -format %D]
	set year [clock format $systemTime -format %Y]
	
	set fileId [open $sinit_file "w"]		
	puts $fileId "\/******************************************************************************"
	puts $fileId "* Copyright (C) 2015 - $year Xilinx, Inc. All rights reserved."
	puts $fileId "* Copyright 2022-${year} Advanced Micro Devices, Inc. All Rights Reserved."
	puts $fileId "* SPDX-License-Identifier: MIT"
	puts $fileId "******************************************************************************\/"
	puts $fileId ""
	puts $fileId "\/*****************************************************************************\/"
	puts $fileId "\/**"
	puts $fileId "*"
	puts $fileId "* @file ${driver_file}.c"
	puts $fileId "* @addtogroup ${driver_name} Overview"
	puts $fileId "* @\{"
	puts $fileId "*"
	puts $fileId "* This file contains the implementation of the Subsystem"
	puts $fileId "* driver's static initialization functionality."
	puts $fileId "*"
	puts $fileId "* <pre>"
	puts $fileId "* MODIFICATION HISTORY:"
	puts $fileId "*"
	puts $fileId "* Ver Who Date     Changes"
	puts $fileId "* --- --- -------- ----------------------------------------------------"
	puts $fileId "* 1.0 name $date Initial release"
	puts $fileId "* </pre>"
	puts $fileId "*"
	puts $fileId "******************************************************************************/"
	puts $fileId ""
	puts $fileId "\/***************************** Include Files *********************************\/"
	puts $fileId ""
	puts $fileId "#include \"xparameters.h\""
	puts $fileId "#include \"[string tolower ${driver_name}.h]\""
	puts $fileId ""
	puts $fileId "\/************************** Constant Definitions *****************************\/"
	puts $fileId ""
	puts $fileId "\/**************************** Type Definitions *******************************\/"
	puts $fileId ""
	puts $fileId "\/***************** Macros (Inline Functions) Definitions *********************\/"
	puts $fileId ""
	puts $fileId "\/************************** Function Prototypes ******************************\/"
	puts $fileId ""
	puts $fileId "\/************************** Variable Definitions *****************************\/"
	puts $fileId ""
	puts $fileId "extern ${driver_name}_Config ${driver_name}_ConfigTable\[\];"
	puts $fileId ""
	puts $fileId "\/************************** Function Definitions ******************************\/"
	puts $fileId ""
	puts $fileId "\/*****************************************************************************\/"
	puts $fileId "\/**"
	puts $fileId "* This function looks for the device configuration based on the unique device"
	puts $fileId "* ID. The table ${driver_name}_ConfigTable\[\] contains the configuration information"
	puts $fileId "* for each instance of the device in the system."
	puts $fileId "*"
	puts $fileId "* @param	DeviceId is the unique device ID of the device being looked up"
	puts $fileId "*"
	puts $fileId "* @return	A pointer to the configuration table entry corresponding to the"
	puts $fileId "*		given device ID, or NULL if no match is found"
	puts $fileId "*"
	puts $fileId "* @note		None."
	puts $fileId "*"
	puts $fileId "******************************************************************************\/"
	puts $fileId "#ifndef SDT"
	puts $fileId "${driver_name}_Config* ${driver_name}_LookupConfig(u32 DeviceId)"
	puts $fileId "{"
	puts $fileId "	${driver_name}_Config *CfgPtr = NULL;"
	puts $fileId "	u32 Index;"
	puts $fileId ""
	puts $fileId "	for (Index = 0; Index < (u32)XPAR_[string toupper $driver_name]_NUM_INSTANCES; Index++) {"
	puts $fileId "		if (${driver_name}_ConfigTable\[Index\].DeviceId == DeviceId) {"
	puts $fileId "			CfgPtr = &${driver_name}_ConfigTable\[Index\];"
	puts $fileId "			break;"
	puts $fileId "		}"
	puts $fileId "	}"
	puts $fileId ""
	puts $fileId "	return CfgPtr;"
	puts $fileId "}	"	
	puts $fileId "#else"
	puts $fileId "${driver_name}_Config* ${driver_name}_LookupConfig(UINTPTR BaseAddress)"
	puts $fileId "{"
	puts $fileId "	${driver_name}_Config *CfgPtr = NULL;"
	puts $fileId "	u32 Index;"
	puts $fileId ""
	puts $fileId "	for (Index = 0U; ${driver_name}_ConfigTable\[Index\].Name != NULL; Index++) {"
	puts $fileId "		if ((${driver_name}_ConfigTable\[Index\].BaseAddress == BaseAddress) || !BaseAddress) {"
	puts $fileId "			CfgPtr = &${driver_name}_ConfigTable\[Index\];"
	puts $fileId "			break;"
	puts $fileId "		}"
	puts $fileId "	}"
	puts $fileId ""
	puts $fileId "	return CfgPtr;"
	puts $fileId "}	"
	puts $fileId "#endif"
	puts $fileId ""		
	puts $fileId "#ifndef SDT"
	puts $fileId "int ${driver_name}_Initialize($driver_name * InstancePtr, u16 DeviceId)"
	puts $fileId "#else"
	puts $fileId "int ${driver_name}_Initialize($driver_name * InstancePtr, UINTPTR BaseAddress)"
	puts $fileId "#endif"
	puts $fileId "{"
	puts $fileId "	${driver_name}_Config *ConfigPtr;"
	puts $fileId ""
	puts $fileId "	/*"
	puts $fileId "	 * Assert arguments"
	puts $fileId "	 */"
	puts $fileId "	Xil_AssertNonvoid(InstancePtr != NULL);"
	puts $fileId ""
	puts $fileId "	/*"
	puts $fileId "	 * Lookup configuration data in the device configuration table."
	puts $fileId "	 * Use this configuration info down below when initializing this"
	puts $fileId "	 * driver."
	puts $fileId "	 */"
	puts $fileId "#ifndef SDT"
	puts $fileId "	ConfigPtr = ${driver_name}_LookupConfig(DeviceId);"
	puts $fileId "#else"
	puts $fileId "	ConfigPtr = ${driver_name}_LookupConfig(BaseAddress);"
	puts $fileId "#endif"
	puts $fileId "	if (ConfigPtr == (${driver_name}_Config *) NULL) {"
	puts $fileId "		InstancePtr->IsReady = 0;"
	puts $fileId "		return (XST_DEVICE_NOT_FOUND);"
	puts $fileId "	}"
	puts $fileId ""
	puts $fileId "	return ${driver_name}_CfgInitialize(InstancePtr, ConfigPtr,"
	puts $fileId "				   ConfigPtr->BaseAddress);"
	puts $fileId "}"

	close $fileId
	puts "Info: [string tolower $sinit_file] is generated"
}

proc generate_cmake {args} {
	set driver ""
	set overwrite_cmake 0
	set ip_name ""
	set driver_src ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-driver"} {
            set driver [lindex $args [expr {$i + 1}]]
        }
        if {[lindex $args $i] == "-overwrite_cmake"} {
            set overwrite_cmake 1
        }
        if {[lindex $args $i] == "-ip_name"} {
            set ip_name [lindex $args [expr {$i + 1}]]
        }
		if {[lindex $args $i] == "-driver_src"} {
			set driver_src [lindex $args [expr {$i + 1}]]
		}		
    }
	
	if {$driver == ""} {
		puts "Error: No driver passed. Use -driver to pass a valid driver"
	}
	
	if {$ip_name == ""} {
		set mdd [glob -nocomplain -directory ${driver}/data -type f *.mdd]
		if {$mdd == ""} {
			puts "Error: No MDD file found at ${driver}/data"
			return ""
		} else {
			set driver_name [file rootname [file tail $mdd]]
		}
	} else {
		set driver_name $ip_name
	}

	
	set cmake_exists [glob -nocomplain -directory ${driver}/src -type f CMakeLists.txt]
	if {$cmake_exists != "" && $overwrite_cmake == 0} {
		puts "Info: CMakeLists.txt already exists. Use -overwrite_cmake to overwrite"
		return ""
	}
	
	if {$driver_src != ""} {
		set driver_files [glob -nocomplain -directory $driver_src -type f *.c *.h]
		if {$driver_files != ""} {
			puts "Info: Importing source files from $driver_src to ${driver}/src"
			foreach driver_file $driver_files {
				if {![regexp {selftest} $driver_file]} {
					file copy $driver_file ${driver}/src
				} else {
					puts "Info: Ignoring $driver_file as this is a selftest source file"
				}
				
			}
		} else {
			puts "Info: No Valid .c or .h found at $driver_src"
		}
	}
	
	set systemTime [clock seconds]
	set date [clock format $systemTime -format %D]
	set year [clock format $systemTime -format %Y]

	set fileId [open ${driver}/src/CMakeLists.txt "w"]
	puts $fileId "# Copyright (C) $year Advanced Micro Devices, Inc.  All rights reserved."
	puts $fileId "# Copyright (c) 2021 Xilinx, Inc.  All rights reserved."
	puts $fileId "# SPDX-License-Identifier: MIT"
	puts $fileId ""
	puts $fileId "cmake_minimum_required(VERSION 3.15)"
	puts $fileId "project(${driver_name})"
	puts $fileId ""
	puts $fileId "find_package(common)"
	puts $fileId "collector_create (PROJECT_LIB_HEADERS \"\${CMAKE_CURRENT_SOURCE_DIR}\")"
	puts $fileId "collector_create (PROJECT_LIB_SOURCES \"\${CMAKE_CURRENT_SOURCE_DIR}\")"
	puts $fileId "include_directories(\${CMAKE_BINARY_DIR}/include)"
	foreach source_files [glob -nocomplain -directory ${driver}/src -type f *.c] {
		puts $fileId "collect (PROJECT_LIB_SOURCES [file tail $source_files])"
	}
	foreach header_files [glob -nocomplain -directory ${driver}/src -type f *.h] {
		puts $fileId "collect (PROJECT_LIB_HEADERS [file tail $header_files])"
	}
	puts $fileId "collector_list (_sources PROJECT_LIB_SOURCES)"
	puts $fileId "collector_list (_headers PROJECT_LIB_HEADERS)"
	puts $fileId "file(COPY \${_headers} DESTINATION \${CMAKE_BINARY_DIR}/include)"
	puts $fileId "add_library(${driver_name} STATIC \${_sources})"
	puts $fileId "set_target_properties(${driver_name} PROPERTIES LINKER_LANGUAGE C)"
	close $fileId
	puts "Info: ${driver}/src/CMakeLists.txt generated"
}

proc help {args} {
	set create_driver 0
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] == "-create_driver"} {
            set create_driver 1
        }		
    }
	if {$create_driver == 1} {
		puts "This is a utility to create a Unified SDT driver. The output driver should be treated as a reference and it is upto the developer to fully test"
		puts "create_driver <options>"
		puts "Required:	-xsa. This is needed to get the HW metadata"
		puts "Required:	-ip_name. This is ip_name of the Vivado cell for the driver to be created for."
		puts "          Users can use the -get_ip_names to get all the IP in the XSA file"
		puts "Example:	create_driver -ip_name name -xsa path/to/xsa"
		puts "Optional:	-overwrite_yaml this overwrites any existing yaml"
		puts "Optional:	-driver_src this will add the driver source files to the driver/src folder"
		puts "Optional:	-repo path/to/output_driver. If this is not set a default path will be set in current dir"
		puts "Optional:	-force_driver. If this is set then any existing driver matches -ip_name will be overwritten."
		puts "Optional:	-type. This is the type of driver to be created. Options are basic (default) or advanced."
		puts "          basic will create a basic driver with just the yaml and cmake file. This is needed if the user just wants the xparameters.h to be populated"
		puts "          advanced will generate the yaml/cmake and the init files for the driver."
		return ""
	}
	puts "Please choose an option:"
	puts "help -create_driver"
	return ""
}