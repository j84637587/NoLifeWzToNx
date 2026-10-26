# NoLifeWzToNx

**English** | [繁體中文](README.zh-TW.md)

NoLifeWzToNx is a C++ command-line tool for converting MapleStory WZ files to NX files.

## Upstream and improvements

This project is an improved and updated version based on [ryantpayton/NoLifeWzToNx](https://github.com/ryantpayton/NoLifeWzToNx).

This version includes:

- A modern CMake-based Windows x64 build.
- Source-built dependencies pinned with Git submodules.
- Extended compatibility with newer WZ bitmap formats.
- A repeatable Debug build helper script.

## Requirements

- [CMake](https://cmake.org/) 3.23 or newer.

## Clone

Clone this repository together with its pinned dependencies:

```bat
git clone --recurse-submodules https://github.com/j84637587/NoLifeWzToNx
cd NoLifeWzToNx
```

If the repository was cloned without `--recurse-submodules`, initialize the dependencies separately:

```bat
git submodule update --init --recursive
```

## Build

Configure the project:

```bat
cmake --preset windows-x64
```

Build Debug:

```bat
cmake --build --preset windows-x64-debug
```

Build Release:

```bat
cmake --build --preset windows-x64-release
```

The executables are written to:

```text
x64\Debug\NoLifeWzToNx.exe
x64\Release\NoLifeWzToNx.exe
```

You can also configure and build the Debug executable with the helper script:

```bat
build-debug.bat
```

## Run

Run the converter directly and provide a WZ file, IMG file, or directory as an input argument.

Client WZ example:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" --client
```

Client directory example:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\wz_folder" -c
```

Server WZ example:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\Data.wz" --server
```

Use high-compression LZ4 output by adding `--lz4hc` or `-h`:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" -c -h
```

Bitmap conversion uses up to 8 worker threads by default. Use `--threads N` or `-t N` to choose between 1 and 64 workers:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" -c -h --threads 8
```

Command-line options:

| Option | Short form | Description |
| --- | --- | --- |
| `--client` | `-c` | Convert client WZ/IMG data, including bitmaps and audio. |
| `--server` | `-s` | Convert server data without client bitmap and audio output. |
| `--lz4hc` | `-h` | Use LZ4 high-compression mode for bitmap output. |
| `--threads N` | `-t N` | Use N bitmap worker threads (1-64, default: up to 8). |

At least one input file or directory must be provided. The converter writes each NX file next to its source WZ or IMG file. If the destination NX file already exists, that file is skipped.

Client bitmap compression results are cached in a shared `.NoLifeWzToNx.cache` directory. For a directory input, one cache is created at the specified root and shared by all recursively converted WZ/IMG files; for a single-file input, the cache is created next to that file. Unchanged bitmaps are reused even when the input filename changes. The bitmap progress line shows the completed count, percentage, cache hits, and images compressed during the current run. A changed bitmap, compression mode, or bitmap format automatically uses a separate cache entry.

## NX raw binary extension

WZ `RawData` and `Canvas#Video` payloads are copied byte-for-byte into the NX file, including payloads with child properties or zero length. They are available in both client and server output.

The extension keeps the `PKG4` header and the existing 20-byte node layout. Header offset 52 stores the raw entry count as a `uint32`, and offset 56 stores the raw offset-table position as a `uint64`. Node type 8 is raw binary; its 8-byte data field contains the raw entry ID and payload length as two `uint32` values. Each raw offset-table entry is a `uint64` absolute file offset. Files without raw entries retain zeroes in header bytes 52 through 63.

## Dependencies

Dependencies are built from source and pinned to exact Git commits:

| Dependency | Version | Commit |
| --- | --- | --- |
| [zlib](https://github.com/madler/zlib) | 1.2.11 | `cacf7f1d4e3d44d871b605da3b647f07d718623f` |
| [LZ4](https://github.com/lz4/lz4) | 1.8.2 | `b3692db46d2b23a7c0af2d5e69988c94f126e10a` |
| [libsquish](https://github.com/oblivioncth/libsquish) | 1.15.1.4 | `4f48f6752814e3e62e75087fc09b816ac0e1f0f0` |
| [bcdec](https://github.com/iOrange/bcdec) | 0.97 | `93628fe5627102fe5187b7eeb99122dec6612c36` |

zlib, LZ4, and libsquish are linked statically. No dependency DLLs need to be copied next to the executable.

## License

This project is distributed under the GNU Affero General Public License, version 3 or later, consistent with the upstream project and the license headers in the source files.
