cmake_minimum_required(VERSION 3.10)

project(ladybird_plugin LANGUAGES CXX)

set(PLUGIN_NAME "ladybird_plugin")

# The flutter tooling requires at least one cpp file in the plugin
# We can just put a dummy here, or since FFI, we can avoid standard Flutter plugin registration.
# But gradle expects to build a target with PLUGIN_NAME.
add_library(${PLUGIN_NAME} SHARED
    ../cpp/engine.cpp
)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

# Build the engine from the cpp folder, exactly as macOS / Linux do
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../cpp" engine_build)

target_link_libraries(${PLUGIN_NAME} PRIVATE engine log android jnigraphics)

# Standard C++2b is required by Ladybird
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)

