# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

# Project name
project(thebinary)

# cmake requirement
cmake_minimum_required(VERSION 2.8)

set(CMAKE_CXX_FLAGS "-Wall")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Common settings
include_directories(".")

file(GLOB thebinary_SOURCES
    "*.cqq"
)

# Main
set(thebinary ${thebinary_SOURCES})
add_executable(thebinary ${thebinary})
target_link_libraries(thebinary rt)
