#pragma once
#include <cstddef>
#include <cstdint>

namespace nl {
// Sound_DX8 is also used for fonts. Their WZ payload is the final declared
// number of bytes in the extended property, independently of sound header size.
inline bool is_sfnt_payload(const std::uint8_t* p, std::size_t size) {
    auto read16 = [](const std::uint8_t* q) { return (q[0] << 8) | q[1]; };
    auto read32 = [](const std::uint8_t* q) { return (std::uint32_t(q[0]) << 24) |
        (std::uint32_t(q[1]) << 16) | (std::uint32_t(q[2]) << 8) | q[3]; };
    auto face = [&](std::size_t start) {
        if (start > size || size - start < 12) return false;
        auto magic = read32(p + start);
        if (magic != 0x00010000 && magic != 0x4f54544f && magic != 0x74727565) return false;
        auto count = read16(p + start + 4);
        if (!count || std::size_t(count) > (size - start - 12) / 16) return false;
        for (int i = 0; i < count; ++i) {
            auto entry = p + start + 12 + 16 * i;
            auto offset = read32(entry + 8), length = read32(entry + 12);
            if (offset > size || length > size - offset) return false;
        }
        return true;
    };
    if (face(0)) return true;
    if (size < 12 || read32(p) != 0x74746366) return false;
    auto version = read32(p + 4), count = read32(p + 8);
    if ((version != 0x10000 && version != 0x20000) || !count || count > (size - 12) / 4) return false;
    for (std::uint32_t i = 0; i < count; ++i)
        if (!face(read32(p + 12 + 4 * i))) return false;
    return true;
}
}
