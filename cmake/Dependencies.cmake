set(THIRD_PARTY_DIR "${PROJECT_SOURCE_DIR}/third_party")

set(REQUIRED_SUBMODULE_FILES
    "${THIRD_PARTY_DIR}/bcdec/bcdec.h"
    "${THIRD_PARTY_DIR}/libsquish/lib/include/squish/squish.h"
    "${THIRD_PARTY_DIR}/lz4/lib/lz4.h"
    "${THIRD_PARTY_DIR}/zlib/zlib.h"
)

foreach(required_file IN LISTS REQUIRED_SUBMODULE_FILES)
    if(NOT EXISTS "${required_file}")
        message(FATAL_ERROR
            "Missing third-party source: ${required_file}\n"
            "Run: git submodule update --init --recursive"
        )
    endif()
endforeach()

add_library(third_party_zlib STATIC
    "${THIRD_PARTY_DIR}/zlib/adler32.c"
    "${THIRD_PARTY_DIR}/zlib/compress.c"
    "${THIRD_PARTY_DIR}/zlib/crc32.c"
    "${THIRD_PARTY_DIR}/zlib/deflate.c"
    "${THIRD_PARTY_DIR}/zlib/gzclose.c"
    "${THIRD_PARTY_DIR}/zlib/gzlib.c"
    "${THIRD_PARTY_DIR}/zlib/gzread.c"
    "${THIRD_PARTY_DIR}/zlib/gzwrite.c"
    "${THIRD_PARTY_DIR}/zlib/infback.c"
    "${THIRD_PARTY_DIR}/zlib/inffast.c"
    "${THIRD_PARTY_DIR}/zlib/inflate.c"
    "${THIRD_PARTY_DIR}/zlib/inftrees.c"
    "${THIRD_PARTY_DIR}/zlib/trees.c"
    "${THIRD_PARTY_DIR}/zlib/uncompr.c"
    "${THIRD_PARTY_DIR}/zlib/zutil.c"
)
target_include_directories(third_party_zlib SYSTEM PUBLIC "${THIRD_PARTY_DIR}/zlib")
add_library(ThirdParty::zlib ALIAS third_party_zlib)

add_library(third_party_lz4 STATIC
    "${THIRD_PARTY_DIR}/lz4/lib/lz4.c"
    "${THIRD_PARTY_DIR}/lz4/lib/lz4frame.c"
    "${THIRD_PARTY_DIR}/lz4/lib/lz4hc.c"
    "${THIRD_PARTY_DIR}/lz4/lib/xxhash.c"
)
target_include_directories(third_party_lz4 SYSTEM PUBLIC "${THIRD_PARTY_DIR}/lz4/lib")
add_library(ThirdParty::lz4 ALIAS third_party_lz4)

add_library(third_party_libsquish STATIC
    "${THIRD_PARTY_DIR}/libsquish/lib/src/alpha.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/clusterfit.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/colourblock.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/colourfit.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/colourset.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/maths.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/rangefit.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/singlecolourfit.cpp"
    "${THIRD_PARTY_DIR}/libsquish/lib/src/squish.cpp"
)

include(GenerateExportHeader)
generate_export_header(third_party_libsquish
    BASE_NAME squish
    EXPORT_FILE_NAME "${CMAKE_CURRENT_BINARY_DIR}/generated/squish/squish_export.h"
)

target_compile_definitions(third_party_libsquish PUBLIC SQUISH_STATIC_DEFINE)
target_include_directories(third_party_libsquish
    PUBLIC "${CMAKE_CURRENT_BINARY_DIR}/generated"
    PRIVATE "${THIRD_PARTY_DIR}/libsquish/lib/src"
)
target_include_directories(third_party_libsquish SYSTEM PUBLIC
    "${THIRD_PARTY_DIR}/libsquish/lib/include"
)
add_library(ThirdParty::libsquish ALIAS third_party_libsquish)

add_library(third_party_bcdec INTERFACE)
target_include_directories(third_party_bcdec SYSTEM INTERFACE "${THIRD_PARTY_DIR}/bcdec")
add_library(ThirdParty::bcdec ALIAS third_party_bcdec)

set_target_properties(
    third_party_zlib
    third_party_lz4
    third_party_libsquish
    PROPERTIES FOLDER "Third Party"
)
