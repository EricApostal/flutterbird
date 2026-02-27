cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(engine SHARED engine.cpp)

set_target_properties(engine PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
)