#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>
#include <lz4.h>

namespace nx_texture {
inline constexpr char kNodeName[] = "__nx_texture";
inline constexpr uint32_t kMagic = 0x58544350;  // PCTX, little endian.
inline constexpr uint32_t kFormat = 2562;     // R10G10B10A2_UNORM.
inline constexpr uint32_t kHeaderSize = 32;
inline constexpr uint32_t kMaxPages = 65536;

inline uint32_t read32(const uint8_t* p) {
  return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 |
         uint32_t(p[3]) << 24;
}
inline void write32(uint8_t* p, uint32_t v) {
  for (unsigned i = 0; i < 4; ++i) p[i] = static_cast<uint8_t>(v >> (8 * i));
}

// An additive raw child of an NX bitmap. Legacy bitmap pixels remain BGRA8;
// this payload holds independent lossless LZ4 pages of the original packed data.
// Header: eight LE uint32 values (magic, version, header size, width, height,
// format, page count, codec). Codec 1 has page-count pairs of offset/size followed
// by LZ4 blocks. Offsets are relative to this payload, not to the NX file.
class Payload {
 public:
  Payload(const uint8_t* data, size_t size) : data_(data) {
    if (!data || size < kHeaderSize || read32(data) != kMagic ||
        read32(data + 4) != 1 || read32(data + 8) != kHeaderSize ||
        read32(data + 20) != kFormat || read32(data + 28) != 1)
      throw std::runtime_error("Invalid packed canvas header");
    width_ = read32(data + 12);
    height_ = read32(data + 16);
    pages_ = read32(data + 24);
    const uint64_t bytes = uint64_t(width_) * height_ * 4;
    if (!width_ || !height_ || width_ > 65535 || height_ > 65535 ||
        !pages_ || pages_ > kMaxPages ||
        bytes > static_cast<uint64_t>((std::numeric_limits<int>::max)()) ||
        uint64_t(kHeaderSize) + uint64_t(pages_) * 8 > size)
      throw std::runtime_error("Invalid packed canvas dimensions");
    page_bytes_ = static_cast<uint32_t>(bytes);
    for (uint32_t page = 0; page < pages_; ++page) {
      const auto entry = data + kHeaderSize + size_t(page) * 8;
      const auto offset = read32(entry);
      const auto length = read32(entry + 4);
      if (offset < uint64_t(kHeaderSize) + uint64_t(pages_) * 8 ||
          offset > size || !length || length > size - offset ||
          length > static_cast<uint32_t>((std::numeric_limits<int>::max)()))
        throw std::runtime_error("Invalid packed canvas page range");
    }
  }

  uint32_t width() const { return width_; }
  uint32_t height() const { return height_; }
  uint32_t pageCount() const { return pages_; }
  uint32_t format() const { return kFormat; }
  uint32_t pageBytes() const { return page_bytes_; }
  std::vector<uint8_t> decodePage(uint32_t page,
                                size_t budget = size_t(256) * 1024 * 1024) const {
    if (page >= pages_ || page_bytes_ > budget)
      throw std::runtime_error("Packed canvas page exceeds decode budget or index");
    const auto entry = data_ + kHeaderSize + size_t(page) * 8;
    const auto offset = read32(entry);
    const auto length = read32(entry + 4);
    std::vector<uint8_t> decoded(page_bytes_);
    if (LZ4_decompress_safe(reinterpret_cast<const char*>(data_ + offset),
            reinterpret_cast<char*>(decoded.data()), static_cast<int>(length),
            static_cast<int>(page_bytes_)) != static_cast<int>(page_bytes_))
      throw std::runtime_error("Invalid packed canvas compressed page");
    return decoded;
  }

 private:
  const uint8_t* data_;
  uint32_t width_ = 0, height_ = 0, pages_ = 0, page_bytes_ = 0;
};
}  // namespace nx_texture
