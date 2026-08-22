cmake_minimum_required(VERSION 3.22)
project(rnfv_fast_core VERSION 0.0.1 LANGUAGES CXX)

option(RNFV_BUILD_TESTS "Build FastCore tests" OFF)

add_library(rnfv_fast_core STATIC
  src/buffer_policy.cpp
  src/preload_policy.cpp
  src/adaptive_policy.cpp
  src/predictive_policy.cpp
  src/session.cpp
  src/c_api.cpp
)

target_include_directories(rnfv_fast_core PUBLIC include)
target_compile_features(rnfv_fast_core PUBLIC cxx_std_20)
set_target_properties(rnfv_fast_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(MSVC)
  target_compile_options(rnfv_fast_core PRIVATE /W4 /permissive-)
else()
  target_compile_options(rnfv_fast_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(RNFV_BUILD_TESTS)
  enable_testing()
  add_executable(rnfv_fast_core_tests tests/session_test.cpp)
  target_link_libraries(rnfv_fast_core_tests PRIVATE rnfv_fast_core)
  add_test(NAME rnfv_fast_core_tests COMMAND rnfv_fast_core_tests)
endif()
