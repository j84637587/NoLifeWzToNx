# NoLifeWzToNx

[English](README.md) | **繁體中文**

NoLifeWzToNx 是一個使用 C++ 開發的命令列工具，用於將 MapleStory WZ 檔案轉換成 NX 檔案。

## 上游專案與改良內容

本專案是基於 [ryantpayton/NoLifeWzToNx](https://github.com/ryantpayton/NoLifeWzToNx) 改良及更新的版本。

此版本包含以下改進：

- 使用現代化 CMake 建置 Windows x64 版本。
- 透過 Git submodule 鎖定並從原始碼建置相依套件。
- 支援較新版本 WZ 使用的 bitmap 格式。
- 提供可重複執行的 Debug 編譯輔助腳本。

## 系統需求

- [CMake](https://cmake.org/) 3.23 或更新版本。

## 複製專案

複製專案時一併取得鎖定版本的相依套件：

```bat
git clone --recurse-submodules https://github.com/j84637587/NoLifeWzToNx
cd NoLifeWzToNx
```

如果複製專案時沒有使用 `--recurse-submodules`，請另外初始化相依套件：

```bat
git submodule update --init --recursive
```

## 編譯

設定 CMake 專案：

```bat
cmake --preset windows-x64
```

編譯 Debug 版本：

```bat
cmake --build --preset windows-x64-debug
```

編譯 Release 版本：

```bat
cmake --build --preset windows-x64-release
```

執行檔會輸出至：

```text
x64\Debug\NoLifeWzToNx.exe
x64\Release\NoLifeWzToNx.exe
```

你也可以使用輔助腳本設定專案並編譯 Debug 版本：

```bat
build-debug.bat
```

## 執行

請直接執行轉換器，並提供 WZ 檔案、IMG 檔案或資料夾作為輸入參數。

轉換 Client WZ 檔案：

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" --client
```

轉換 Client 資料夾：

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\wz_folder" -c
```

轉換 Server WZ 檔案：

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\Data.wz" --server
```

加入 `--lz4hc` 或 `-h` 可以使用 LZ4 高壓縮模式：

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" -c -h
```

bitmap 轉換預設最多使用 8 個 worker threads。可用 `--threads N` 或 `-t N` 指定 1 到 64：

```bat
x64\Debug\NoLifeWzToNx.exe "F:\path\to\file.wz" -c -h --threads 8
```

命令列選項：

| 選項 | 簡寫 | 說明 |
| --- | --- | --- |
| `--client` | `-c` | 轉換 Client WZ/IMG 資料，包含 bitmap 與 audio。 |
| `--server` | `-s` | 轉換 Server 資料，不輸出 Client bitmap 與 audio。 |
| `--lz4hc` | `-h` | bitmap 輸出使用 LZ4 高壓縮模式。 |
| `--threads N` | `-t N` | 使用 N 個 bitmap worker threads（1-64，預設最多 8）。 |

至少必須提供一個輸入檔案或資料夾。轉換器會將 NX 檔案寫入來源 WZ 或 IMG 檔案所在的資料夾。如果目的 NX 檔案已存在，該檔案會被跳過。

Client bitmap 的壓縮結果會快取在輸入旁共用的 `.NoLifeWzToNx.cache` 目錄。同一資料夾內的 WZ/IMG 即使檔名不同，也能重用未變更 bitmap 的 LZ4 資料。bitmap 進度列會顯示完成數、百分比、快取命中數與本次實際壓縮數；bitmap 內容、壓縮模式或格式變更時會自動使用不同的快取項目。

## NX raw binary 擴充

WZ 的 `RawData` 與 `Canvas#Video` payload 會逐位元組複製到 NX，包含具有子屬性或長度為零的 payload；client 與 server 輸出都會保留 raw binary。

此擴充維持 `PKG4` header 與既有 20-byte node layout。Header offset 52 是 raw entry 數量（`uint32`），offset 56 是 raw offset table 位置（`uint64`）。Node type 8 代表 raw binary，其 8-byte data field 依序存放 raw entry ID 與 payload length（兩者皆為 `uint32`）；raw offset table 的每筆資料是 payload 的絕對檔案位置（`uint64`）。不含 raw entry 的檔案，其 header byte 52 到 63 維持全零。

## 相依套件

所有相依套件都會從原始碼建置，並鎖定至指定的 Git commit：

| 相依套件 | 版本 | Commit |
| --- | --- | --- |
| [zlib](https://github.com/madler/zlib) | 1.2.11 | `cacf7f1d4e3d44d871b605da3b647f07d718623f` |
| [LZ4](https://github.com/lz4/lz4) | 1.8.2 | `b3692db46d2b23a7c0af2d5e69988c94f126e10a` |
| [libsquish](https://github.com/oblivioncth/libsquish) | 1.15.1.4 | `4f48f6752814e3e62e75087fc09b816ac0e1f0f0` |
| [bcdec](https://github.com/iOrange/bcdec) | 0.97 | `93628fe5627102fe5187b7eeb99122dec6612c36` |

zlib、LZ4 與 libsquish 會以靜態方式連結，因此不需要將相依套件的 DLL 複製到執行檔旁邊。

## 授權條款

本專案依照 GNU Affero General Public License 3 或更新版本授權，與上游專案及原始碼中的授權聲明一致。
