# Copyright (c) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Number of parallel jobs by default is 1
if(NOT DEFINED HIP_CLANG_NUM_PARALLEL_JOBS)
  set(HIP_CLANG_NUM_PARALLEL_JOBS 1)
endif()

if(NOT HIP_CXX_COMPILER)
  set(HIP_CXX_COMPILER ${CMAKE_CXX_COMPILER})
endif()

if(NOT WIN32)
  find_dependency(AMDDeviceLibs)
endif()
set(AMDGPU_TARGETS "" CACHE STRING "AMD GPU targets to compile for")
set(GPU_TARGETS "${AMDGPU_TARGETS}" CACHE STRING "GPU targets to compile for")

if(NOT WIN32)
  find_dependency(amd_comgr)
endif()

include( "${CMAKE_CURRENT_LIST_DIR}/hip-targets.cmake" )

#Using find_dependency to locate the dependency for the packages
#This makes the cmake generated file xxxx-targets to supply the linker libraries
# without worrying other transitive dependencies
if(NOT WIN32)
  find_dependency(hsa-runtime64)
  find_dependency(Threads)
endif()

set(_IMPORT_PREFIX ${HIP_PACKAGE_PREFIX_DIR})
# Right now this is only supported for amd platforms
set_target_properties(hip::host PROPERTIES
  INTERFACE_COMPILE_DEFINITIONS "__HIP_PLATFORM_HCC__=1;__HIP_PLATFORM_AMD__=1"
)

set_target_properties(hip::amdhip64 PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
  INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
)

get_target_property(amdhip64_type hip::amdhip64 TYPE)
message(STATUS "hip::amdhip64 is ${amdhip64_type}")

if(NOT WIN32)
  set_target_properties(hip::device PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
    INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
  )
endif()

get_property(compilePropIsSet TARGET hip::device PROPERTY INTERFACE_COMPILE_OPTIONS SET)

if (NOT compilePropIsSet AND HIP_CXX_COMPILER MATCHES ".*clang\\+\\+")
  hip_add_interface_compile_flags(hip::device -mllvm -amdgpu-early-inline-all=true -mllvm -amdgpu-function-calls=false)
endif()

if (NOT compilePropIsSet)
  hip_add_interface_compile_flags(hip::device -x hip)
endif()

hip_add_interface_link_flags(hip::device --hip-link)

foreach(GPU_TARGET ${GPU_TARGETS})
    if (NOT compilePropIsSet)
      hip_add_interface_compile_flags(hip::device --offload-arch=${GPU_TARGET})
    endif()
    hip_add_interface_link_flags(hip::device --offload-arch=${GPU_TARGET})
endforeach()
#Add support for parallel build and link
if(${CMAKE_CXX_COMPILER_ID} STREQUAL "Clang")
  check_cxx_compiler_flag("-parallel-jobs=1" HIP_CLANG_SUPPORTS_PARALLEL_JOBS)
endif()
if(HIP_CLANG_NUM_PARALLEL_JOBS GREATER 1)
  if(${HIP_CLANG_SUPPORTS_PARALLEL_JOBS} )
    if (NOT compilePropIsSet)
      hip_add_interface_compile_flags(hip::device -parallel-jobs=${HIP_CLANG_NUM_PARALLEL_JOBS} -Wno-format-nonliteral)
    endif()
    hip_add_interface_link_flags(hip::device -parallel-jobs=${HIP_CLANG_NUM_PARALLEL_JOBS})
  else()
    message("clang compiler doesn't support parallel jobs")
  endif()
endif()

# Use HIP_CXX option -print-libgcc-file-name --rtlib=compiler-rt
# To fetch the compiler rt library file name.
execute_process(
  COMMAND ${HIP_CXX_COMPILER} -print-libgcc-file-name --rtlib=compiler-rt
  OUTPUT_VARIABLE CLANGRT_BUILTINS
  ERROR_VARIABLE  CLANGRT_Error
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE CLANGRT_BUILTINS_FETCH_EXIT_CODE)

if( CLANGRT_Error )
  if (HIP_CXX_COMPILER MATCHES ".*clang\\+\\+")
    message( STATUS "${HIP_CXX_COMPILER}: CLANGRT compiler options not supported.")
  endif()
else()
  # Add support for __fp16 and _Float16, explicitly link with compiler-rt
  if( "${CLANGRT_BUILTINS_FETCH_EXIT_CODE}" STREQUAL "0" )
    # CLANG_RT Builtins found Successfully Set interface link libraries property
    set_property(TARGET hip::host APPEND PROPERTY INTERFACE_LINK_LIBRARIES "${CLANGRT_BUILTINS}")
    set_property(TARGET hip::device APPEND PROPERTY INTERFACE_LINK_LIBRARIES "${CLANGRT_BUILTINS}")
  else()
    message(STATUS "clangrt builtins lib not found: ${CLANGRT_BUILTINS_FETCH_EXIT_CODE}")
  endif() # CLANGRT_BUILTINS_FETCH_EXIT_CODE Check
endif() # CLANGRT_Error Check
