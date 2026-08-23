cmake_minimum_required(VERSION 3.22)
project(rnfv_fast_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

file(GLOB RNFV_CORE_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")

add_library(rnfv_core STATIC ${RNFV_CORE_SOURCES})
set_target_properties(rnfv_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(
  rnfv_core
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(MSVC)
  target_compile_options(rnfv_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(rnfv_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

option(RNFV_BUILD_TESTS "Build deterministic FastCore tests" OFF)
if(RNFV_BUILD_TESTS)
  enable_testing()
  file(GLOB RNFV_TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tests/*.cpp")
  foreach(test_source IN LISTS RNFV_TEST_SOURCES)
    get_filename_component(test_name "${test_source}" NAME_WE)
    set(target_name "rnfv_${test_name}")
    add_executable("${target_name}" "${test_source}")
    target_link_libraries("${target_name}" PRIVATE rnfv_core)
    if(MSVC)
      target_compile_options("${target_name}" PRIVATE /W4 /permissive-)
    else()
      target_compile_options("${target_name}" PRIVATE -Wall -Wextra -Wpedantic)
    endif()
    add_test(NAME "${target_name}" COMMAND "${target_name}")
  endforeach()
endif()
