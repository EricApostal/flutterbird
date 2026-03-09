cmake_minimum_required(VERSION 3.10)

project(ladybird_plugin LANGUAGES CXX)

set(PLUGIN_NAME "ladybird_plugin")

add_library(${PLUGIN_NAME} SHARED
    # No C++ plugin code needed since we bind through dart ffi. Just building the engine.
    ../cpp/engine.cpp
)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

# Link the same libraries as Ladybird Android UI
target_link_libraries(${PLUGIN_NAME} PRIVATE jnigraphics android)

# Define standard compiler properties (C++23 is needed by ladybird)
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

target_include_directories(${PLUGIN_NAME} PRIVATE
    ${LADYBIRD_DIR}
    ${LADYBIRD_DIR}/Libraries
    ${LADYBIRD_DIR}/Userland/Libraries
    ${LADYBIRD_DIR}/Services
    ${LADYBIRD_DIR}/Build/release
)

include(${LADYBIRD_DIR}/UI/cmake/AndroidExtras.cmake)
create_ladybird_bundle(${PLUGIN_NAME})
