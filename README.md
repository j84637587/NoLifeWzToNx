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

Inspect WZ format and legacy version candidates without converting:

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" --info
```

Command-line options:

| Option | Short form | Description |
| --- | --- | --- |
| `--client` | `-c` | Convert client WZ/IMG data, including bitmaps and audio. |
| `--server` | `-s` | Convert server data without client bitmap and audio output. |
| `--lz4hc` | `-h` | Use LZ4 high-compression mode for bitmap output. |
| `--threads N` | `-t N` | Use N bitmap worker threads (1-64, default: up to 8). |
| `--info` | `-i` | Show WZ format and legacy version candidates without converting. |

At least one input file or directory must be provided. The converter writes each NX file next to its source WZ or IMG file. If the destination NX file already exists, that file is skipped.

For a client directory conversion, the converter scans every WZ and builds a global bitmap registry before writing any NX files. A `source` can therefore obtain its bitmap directly from another WZ or numbered split without depending on NX output order. When only one WZ is provided, the registry contains only the WZ files listed on the command line; provide the directory or list the required WZ files together when cross-file resolution is needed.

Client bitmap compression results are cached in a shared `.NoLifeWzToNx.cache` directory. For a directory input, one cache is created at the specified root and shared by all recursively converted WZ/IMG files; for a single-file input, the cache is created next to that file. Unchanged bitmaps are reused even when the input filename changes. The bitmap progress line shows the completed count, percentage, cache hits, and images compressed during the current run. A changed bitmap, compression mode, or bitmap format automatically uses a separate cache entry.

## Daily conversion: keep only two NX generations

After building the updated converter, put only your active WZ/IMG set in `wz/current/` and double-click `convert-local.bat` (Windows PowerShell 5.1+).

```text
wz/current/          active WZ/IMG files, with stable filenames
wz/backup/           manually managed source backup, excluded from conversion
nx-local/current/    latest successful NX set
nx-local/previous/   previous distinct successful NX set
```

- 轉換會先寫入暫存 NX. 成功結束, 預期檔案齊全, PKG4/PKG5 header 正確, 且來源與轉換器雜湊未變更後才換版; 這不代表遊戲內相容性驗證.
- A failed conversion leaves both successful generations intact. The next successful distinct generation rotates out the oldest NX set; identical output does not consume history.
- Source WZ/IMG files are never deleted or automatically backed up. Save a pre-edit copy in `wz/backup/` yourself.
- Existing numbered history is not migrated or cleaned. Do not use a folder containing multiple historical WZ versions as the active source.
- Interrupted rotation is recovered on the next run. Locked or unexpected files stop cleanup rather than being forcibly removed. Keep `nx-local/` exclusively for the tool's managed NX output.
- Use `nx-local/current/` for client testing, or retrieve `previous/` to roll back. The script does not switch a client or publish assets.
- The shared source-side `.NoLifeWzToNx.cache` is unchanged and is not pruned by this workflow.

For an existing active source folder:

```powershell
.\convert-local.ps1 -Source 'F:\NovaAssets\wz-current'
```

Optional parameters: `-Output`, `-ConverterPath`, `-Mode server`, `-Threads 8`, `-Lz4HC`. The output must be empty on first use; source and output must not contain each other.

The converter also supports `--output DIR` for exactly one input file or directory, preserving relative paths. Omitting it retains the existing source-adjacent output and skip-existing behavior. Use `convert-local` for retention and failure protection.

## NX raw binary extension

WZ `RawData` and `Canvas#Video` payloads are copied byte-for-byte into the NX file, including payloads with child properties or zero length. They are available in both client and server output.

此擴充維持 `PKG4`/`PKG5` header 與既有 20-byte node 佈局. Header offset 52 存放 raw entry 數量 (`uint32`), offset 56 存放 raw offset table 位置 (`uint64`). Node type 8 代表 raw binary, 其 8-byte data field 依序存放 raw entry ID 與 payload length (皆為 `uint32`); raw offset table 每筆資料為 payload 的絕對位置 (`uint64`). 沒有 raw entry 時, header byte 52 至 63 維持全零.

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
