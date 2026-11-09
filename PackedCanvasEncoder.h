#pragma once
#include "PackedCanvasPayload.h"
#include <algorithm>
#include <zlib.h>

namespace nx_texture {
inline std::vector<uint8_t> encodePages(const uint8_t* data, size_t length,
    uint32_t width, uint32_t height, uint32_t pages) {
  const uint64_t bytes = uint64_t(width) * height * 4;
  if (!data || !width || !height || width > 65535 || height > 65535 || !pages ||
      pages > kMaxPages || bytes > static_cast<uint64_t>(LZ4_MAX_INPUT_SIZE) ||
      !length || length > (std::numeric_limits<uInt>::max)())
    throw std::runtime_error("Invalid packed canvas source dimensions");
  z_stream stream{};
  if (inflateInit(&stream) != Z_OK)
    throw std::runtime_error("Cannot initialize packed canvas inflater");
  struct Cleanup { z_stream* stream; ~Cleanup() { inflateEnd(stream); } } cleanup{&stream};
  stream.next_in = const_cast<Bytef*>(data);
  stream.avail_in = static_cast<uInt>(length);
  const auto page_bytes = static_cast<int>(bytes);
  std::vector<uint8_t> page(page_bytes);
  std::vector<uint8_t> compressed(LZ4_compressBound(page_bytes));
  std::vector<uint8_t> result(kHeaderSize + size_t(pages) * 8);
  write32(result.data(), kMagic);
  write32(result.data() + 4, 1);
  write32(result.data() + 8, kHeaderSize);
  write32(result.data() + 12, width);
  write32(result.data() + 16, height);
  write32(result.data() + 20, kFormat);
  write32(result.data() + 24, pages);
  write32(result.data() + 28, 1);  // Independent LZ4 block per page.
  for (uint32_t index = 0; index < pages; ++index) {
    stream.next_out = page.data();
    stream.avail_out = static_cast<uInt>(page_bytes);
    int status = Z_OK;
    while (stream.avail_out) {
      const auto before_in = stream.avail_in;
      const auto before_out = stream.avail_out;
      status = inflate(&stream, Z_NO_FLUSH);
      if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR)
        throw std::runtime_error("Invalid packed canvas zlib stream");
      if (stream.avail_out && (status == Z_STREAM_END ||
          (before_in == stream.avail_in && before_out == stream.avail_out)))
        throw std::runtime_error("Truncated packed canvas pixels");
    }
    const auto size = LZ4_compress_default(reinterpret_cast<const char*>(page.data()),
        reinterpret_cast<char*>(compressed.data()), page_bytes,
        static_cast<int>(compressed.size()));
    if (size <= 0 || result.size() > UINT32_MAX - static_cast<uint32_t>(size))
      throw std::runtime_error("Packed canvas payload is too large");
    write32(result.data() + kHeaderSize + size_t(index) * 8,
            static_cast<uint32_t>(result.size()));
    write32(result.data() + kHeaderSize + size_t(index) * 8 + 4, size);
    result.insert(result.end(), compressed.begin(), compressed.begin() + size);
  }
  // WZ streams may omit the zlib end marker. Accept that only after all
  // declared pixels and all source bytes have been consumed, without extra pixels.
  uint8_t extra;
  stream.next_out = &extra;
  stream.avail_out = 1;
  const auto status = inflate(&stream, Z_FINISH);
  if (stream.avail_out != 1 || stream.avail_in != 0 ||
      (status != Z_STREAM_END && status != Z_BUF_ERROR))
    throw std::runtime_error("Packed canvas size does not match page count");
  return result;
}

inline std::vector<uint8_t> encode(const uint8_t* data, size_t length,
    const uint8_t* key, uint32_t width, uint32_t height, uint32_t pages) {
  try { return encodePages(data, length, width, height, pages); }
  catch (const std::runtime_error&) {
    // List.wz uses length-prefixed XOR blocks, with the key restarting per block.
    std::vector<uint8_t> decrypted;
    size_t offset = 0;
    while (offset < length) {
      if (!key || length - offset < 4)
        throw std::runtime_error("Invalid packed canvas encrypted block");
      const auto size = read32(data + offset);
      offset += 4;
      if (!size || size > 65536 || size > length - offset)
        throw std::runtime_error("Invalid packed canvas encrypted block size");
      for (uint32_t i = 0; i < size; ++i) decrypted.push_back(data[offset + i] ^ key[i]);
      offset += size;
    }
    return encodePages(decrypted.data(), decrypted.size(), width, height, pages);
  }
}
}  // namespace nx_texture
