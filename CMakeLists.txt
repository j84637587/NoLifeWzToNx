cmake_minimum_required(VERSION 3.23)

project(NoLifeWzToNx LANGUAGES C CXX)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Only 64-bit Windows builds are currently supported.")
endif()

include(cmake/Dependencies.cmake)

add_executable(NoLifeWzToNx Keys.cpp NoLifeWzToNx.cpp)

target_compile_features(NoLifeWzToNx PRIVATE cxx_std_17)
target_compile_definitions(NoLifeWzToNx PRIVATE
    LZ4_DISABLE_DEPRECATE_WARNINGS
    _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
)
target_compile_options(NoLifeWzToNx PRIVATE
    "$<$<CXX_COMPILER_ID:MSVC>:/W4;/sdl>"
)

target_link_libraries(NoLifeWzToNx PRIVATE
    ThirdParty::bcdec
    ThirdParty::lz4
    ThirdParty::libsquish
    ThirdParty::zlib
)

set_target_properties(NoLifeWzToNx PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/x64"
)
