#pragma once
#include "PackedCanvasPayload.h"
#include <algorithm>
#include <zlib.h>

namespace nx_texture {
inline bool hasLegacyZlibTail(const uint8_t* data, size_t length) {
  static constexpr uint8_t sync_flush[] = {0x00, 0x00, 0xff, 0xff};
  if (length >= sizeof(sync_flush) &&
      std::memcmp(data + length - sizeof(sync_flush), sync_flush,
                  sizeof(sync_flush)) == 0)
    return true;
  // Some existing WZ samples append an invalid deflate block after Z_SYNC_FLUSH.
  return length >= sizeof(sync_flush) + 1 && data[length - 1] == 0x07 &&
      std::memcmp(data + length - sizeof(sync_flush) - 1, sync_flush,
                  sizeof(sync_flush)) == 0;
}

inline uint32_t inferPageCount(const uint8_t* data, size_t length,
    uint64_t page_bytes) {
  z_stream stream{};
  if (inflateInit(&stream) != Z_OK)
    throw std::runtime_error("Cannot initialize packed canvas inflater");
  struct Cleanup { z_stream* stream; ~Cleanup() { inflateEnd(stream); } } cleanup{&stream};
  stream.next_in = const_cast<Bytef*>(data);
  stream.avail_in = static_cast<uInt>(length);
  uint8_t output[64 * 1024];
  const auto max_bytes = page_bytes * kMaxPages;
  uint64_t total = 0;
  while (true) {
    stream.next_out = output;
    stream.avail_out = sizeof(output);
    const auto before_in = stream.avail_in;
    const auto status = inflate(&stream, Z_NO_FLUSH);
    const auto produced = sizeof(output) - stream.avail_out;
    if (produced > max_bytes - total)
      throw std::runtime_error("Packed canvas page count exceeds limit");
    total += produced;
    if (status == Z_STREAM_END) {
      if (stream.avail_in != 0)
        throw std::runtime_error("Packed canvas has trailing compressed data");
      break;
    }
    const bool legacy_end = stream.avail_in == 0 && hasLegacyZlibTail(data, length) &&
        (status == Z_BUF_ERROR || (status == Z_DATA_ERROR && stream.msg &&
         std::strcmp(stream.msg, "invalid block type") == 0));
    if (legacy_end) break;
    if (status != Z_OK ||
        (before_in == stream.avail_in && produced == 0))
      throw std::runtime_error("Invalid packed canvas zlib stream");
  }
  if (!total || total % page_bytes != 0)
    throw std::runtime_error("Packed canvas size is not a whole page count");
  const auto pages = total / page_bytes;
  if (!pages || pages > kMaxPages)
    throw std::runtime_error("Packed canvas page count exceeds limit");
  return static_cast<uint32_t>(pages);
}

inline std::vector<uint8_t> encodePages(const uint8_t* data, size_t length,
    uint32_t width, uint32_t height, uint32_t pages) {
  const uint64_t bytes = uint64_t(width) * height * 4;
  if (!data || !width || !height || width > 65535 || height > 65535 ||
      pages > kMaxPages || bytes > static_cast<uint64_t>(LZ4_MAX_INPUT_SIZE) ||
      !length || length > (std::numeric_limits<uInt>::max)())
    throw std::runtime_error("Invalid packed canvas source dimensions");
  if (!pages) pages = inferPageCount(data, length, bytes);
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
  bool legacy_complete = false;
  for (uint32_t index = 0; index < pages; ++index) {
    stream.next_out = page.data();
    stream.avail_out = static_cast<uInt>(page_bytes);
    int status = Z_OK;
    while (stream.avail_out) {
      const auto before_in = stream.avail_in;
      const auto before_out = stream.avail_out;
      status = inflate(&stream, Z_NO_FLUSH);
      if (status == Z_DATA_ERROR && index + 1 == pages &&
          stream.avail_out == 0 && stream.avail_in == 0 && stream.msg &&
          std::strcmp(stream.msg, "invalid block type") == 0 &&
          hasLegacyZlibTail(data, length)) {
        legacy_complete = true;
        break;
      }
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
  if (legacy_complete) return result;
  uint8_t extra;
  stream.next_out = &extra;
  stream.avail_out = 1;
  const auto status = inflate(&stream, Z_FINISH);
  const bool legacy_tail = hasLegacyZlibTail(data, length) &&
      (status == Z_BUF_ERROR || (status == Z_DATA_ERROR && stream.msg &&
       std::strcmp(stream.msg, "invalid block type") == 0));
  if (stream.avail_out != 1 || stream.avail_in != 0 ||
      (status != Z_STREAM_END && !legacy_tail))
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
        throw;
      const auto size = read32(data + offset);
      offset += 4;
      if (!size || size > 65536 || size > length - offset)
        throw;
      for (uint32_t i = 0; i < size; ++i) decrypted.push_back(data[offset + i] ^ key[i]);
      offset += size;
    }
    return encodePages(decrypted.data(), decrypted.size(), width, height, pages);
  }
}
}  // namespace nx_texture
