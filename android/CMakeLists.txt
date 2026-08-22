cmake_minimum_required(VERSION 3.22.1)
project(react_native_fast_video LANGUAGES CXX)

set(RNFV_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(../cpp ${CMAKE_CURRENT_BINARY_DIR}/fast-core)

add_library(react-native-fast-video SHARED
  src/main/cpp/FastCoreJni.cpp
)

target_compile_features(react-native-fast-video PRIVATE cxx_std_20)
target_include_directories(react-native-fast-video PRIVATE ../cpp/include)
target_link_libraries(react-native-fast-video
  rnfv_fast_core
  android
  log
)
