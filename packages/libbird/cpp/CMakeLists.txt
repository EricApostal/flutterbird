cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

# Ladybird requires C++23
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(engine SHARED engine.cpp)

# Define the path to Ladybird relative to your cpp folder
set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/ladybird")

# Add the header inclusion paths
target_include_directories(engine PRIVATE
    ${LADYBIRD_DIR}
    ${LADYBIRD_DIR}/Userland/Libraries
)

# Point to where your compiled Ladybird libraries are sitting
target_link_directories(engine PRIVATE 
    ${LADYBIRD_DIR}/Build/release/lib # Update this if your build path differs
)

# Link against the specific Ladybird libraries used in engine.cpp
target_link_libraries(engine PRIVATE
    lagom-core
    lagom-gfx
    lagom-webview
)

set_target_properties(engine PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
)