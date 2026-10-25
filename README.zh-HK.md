<div align="center">

<h1>kakikomi</h1>

<strong>將磁碟映像寫入軟碟、Zip 碟、USB 手指和硬碟，逐塊校驗，而且唔畀系統掛載。</strong>

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | 繁體中文 (香港)

[![ci](https://github.com/gufranco/kakikomi/actions/workflows/ci.yml/badge.svg)](https://github.com/gufranco/kakikomi/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/gufranco/kakikomi)](https://github.com/gufranco/kakikomi/releases)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![shell](https://img.shields.io/badge/shell-POSIX%20sh-lightgrey)](#portability)

<p align="center">
  <a href="#quick-start"><strong>快速開始</strong></a> |
  <a href="#never-mounted">絕不掛載</a> |
  <a href="#kiyome">kiyome</a> |
  <a href="#development">開發</a>
</p>

</div>

兩個指令，40 個測試，13 個 shell 模組，除咗 POSIX 系統之外冇任何執行時依賴。`kakikomi` 係日文「書き込み」，即係將資料寫入磁碟；`kiyome` 係「清め」，即係淨化，用嚟將磁碟抹乾淨。

---

```console
$ kakikomi debian.img.xz /dev/disk4
Image:  debian.img.xz
        xz, 1.4 GiB (1501560832 bytes)
Target: /dev/disk4, 14.9 GiB, SANDISK ULTRA
Type disk4 to write, or anything else to stop: disk4
Blanking the first 1.0 MiB so nothing on /dev/disk4 is mountable until the very end.
Told macOS not to mount the 2 volume(s) in this image.
Writing the first 1.0 MiB last.
Wrote and verified every chunk of the image.
Validated: /dev/disk4 matches the image, SHA-256 9f86d081884c7d65...
Ejected. /dev/disk4 is safe to remove.
```

<a id="quick-start"></a>

## 快速開始

### 前置條件

| 工具 | 用途 | 安裝 |
|:-----|:----|:--------|
| POSIX `sh`、`dd`、`cmp`、`od` | 工具本身 | macOS 同 Linux 已預裝，唔需要 `bash` |
| `openssl` | kiyome 嘅逐塊隨機圖案 | 已預裝 |
| `gzip`、`xz`、`zstd`、`bzip2` | 壓縮映像 | 只喺寫入對應格式時需要 |
| `bsdtar` 或 `7z` | `.zip` 映像同 Windows ISO | Linux 上係 `libarchive-tools` 或 `p7zip-full` |
| `qemu-img` | `.vhd`、`.vhdx`、`.vmdk`、`.qcow2` | `brew install qemu` 或 `apt install qemu-utils` |
| `mtools`、`wimlib` | Windows ISO 同 `kakikomi format` | 隨 Homebrew formula 安裝；Linux 上係 `apt install mtools wimtools` |

### 安裝

```bash
brew install gufranco/tap/kakikomi
```

亦可以由原始碼安裝：

```bash
git clone https://github.com/gufranco/kakikomi.git
cd kakikomi
make install
```

`make install` 會將工具複製到 `~/.local` 之下，再將 `kakikomi` 同 `kiyome` 放入 `~/.local/bin`；設定 `PREFIX` 可以改位置。

### 驗證

```console
$ kakikomi --version
kakikomi 1.0.0
```

## 用法

| 指令 | 用途 |
|:--------|:--------|
| `kakikomi <image\|url\|device> [target...]` | 將映像寫入一個或多個磁碟。唔指定目標時，會列出可揀嘅抽取式磁碟 |
| `kakikomi <windows.iso> <target>` | 將 Windows 安裝 ISO 佈置成可以 UEFI 開機嘅 FAT32 USB 手指 |
| `kakikomi format <target> [fat32\|exfat\|fat\|floppy] [LABEL]` | 快速格式化：只寫入新檔案系統嘅結構 |
| `kakikomi --release` | 移除某次執行遺留低嘅掛載防護 |
| `kiyome <target>` | 用五種經過校驗嘅圖案覆寫磁碟 |

| 來源 | 讀取方式 |
|:-------|:---------------|
| `.img`、`.iso`、`.bin`、`.raw`、`.dsk`、`.ima` | 直接讀取 |
| `.gz`、`.xz`、`.zst`、`.bz2` | 串流讀取，從不解壓到磁碟 |
| 只得一個映像嘅 `.zip` | 用 `bsdtar` 串流讀取 |
| `.dmg`、`.vhd`、`.vhdx`、`.vmdk`、`.qcow2` | 檢查可用空間後先轉換成 raw |
| `http://` 或 `https://` URL | 可續傳下載之後當檔案讀取 |
| `/dev/...` | 由該磁碟機複製，嗰部磁碟機同樣唔會被掛載 |

| 變數 | 效果 |
|:---------|:-------|
| `VERIFY=n` | 跳過最後嘅全碟 SHA-256 比對。未設定時會問你 |
| `DELETE=y` | 所有磁碟校驗通過後將映像移去垃圾桶。冇回讀時忽略 |
| `AGAIN=y` | 將同一個映像寫入你插入嘅下一隻磁碟 |
| `REINSERT=y` | 退出之後等磁碟重新插入再比對一次 |
| `ZERO_TAIL=y` | 喺較大嘅磁碟上清空映像之後嘅空間 |
| `SHA256=<hash>` | 映像唔吻合就停止。同目錄嘅 `.sha256` 或 `SHA256SUMS` 檔案會自動讀取 |
| `ALLOW_INTERNAL=y` | 允許內置磁碟。正在運行嘅系統所在嘅磁碟一定會被拒絕 |
| `KEEP_GUARD=y` | 執行後保留 fstab 防護，等呢部 Mac 永遠唔掛載嗰隻磁碟 |
| `MODE=raw` | 逐個 byte 照寫 Windows ISO，而唔係佈置成 FAT32 |

```bash
kakikomi debian.img.xz /dev/disk4 /dev/disk5     # two sticks at once
kakikomi https://example.org/os.img.gz            # pick the target from a list
kakikomi /dev/disk4 /dev/disk5                    # clone disk4 onto disk5
AGAIN=y kakikomi game.ima /dev/disk6              # a batch of floppies
kakikomi format /dev/disk4 exfat MEDIA
```

<a id="never-mounted"></a>

## 絕不掛載

macOS 只要掛載 FAT 卷，就算得一剎那，都會寫入 `.fseventsd`、`.Spotlight-V100` 同 `._` 檔案，於是為懷舊機器寫好嘅磁碟攞返嚟時已經變咗。kakikomi 令系統無從入手：

```mermaid
graph LR
    A["確認目標"] --> B["清空第一個 MiB"]
    B --> C["寫入並校驗其餘每塊"]
    C --> D["將每個卷宣告為 noauto"]
    D --> E["寫入並校驗第一個 MiB"]
    E --> F["退出"]
    F --> G["移除防護"]
```

| 步驟 | 細節 |
|:-----|:-------|
| 直到最後都冇嘢可以掛載 | 第一個 MiB 係空白，就冇分割表同開機扇區，DiskArbitration 同 udisks 都搵唔到卷 |
| 出現之前先宣告 | macOS：由用 `-nomount` 掛接、只有標頭嘅副本讀取每個卷嘅 UUID，以 `noauto` 寫入 `/etc/fstab`。Linux：為該裝置加入 `UDISKS_IGNORE` udev 規則 |
| 監察 | 執行期間發現掛載即當失敗，並列出系統建立嘅檔案 |
| 證明 | `REINSERT=y` 喺你拔插之後回讀成隻磁碟 |

中途停止嘅執行會令第一個 MiB 保持空白，所以寫咗一半嘅磁碟一樣掛載唔到。

## 一遇到問題就停

每一塊都會寫入、回讀、比對，之後先處理下一塊。kakikomi 會先測量磁碟本身嘅速度，再根據結果為每次傳輸設定期限。唔吻合、停頓或者裝置消失，都會停止嗰隻磁碟、退出佢，並印出出錯嘅位線。

| 磁碟機 | 處理方式 |
|:------|:----------|
| Zip、Jaz、PocketZip | 期限更嚴而且唔重試；停頓會當成磁頭偏離，偏離咗嘅磁頭會整壞佢遇到嘅下一隻碟 |
| 軟碟、SuperDisk | 唔重試，並等你取出磁碟，因為呢啲磁碟機冇得用軟件退出 |
| 其他 | 每塊試三次，然後停止 |

有多個目標時，每隻磁碟由獨立嘅 worker 寫入，一隻出錯唔會影響其他。

## Windows 安裝碟

逐個 byte 照寫嘅 Windows ISO 冇辦法由 USB 開機。kakikomi 會認出佢，建立一個 MBR 磁碟，入面只有一個載住所有檔案嘅 FAT32 分割區，並用 `wimlib` 拆開超過 4 GiB 嘅 `install.wim`。檔案用 `mtools` 複製，目標從不被掛載，寫入卷之前每個檔案都會回讀比對。結果可以喺 UEFI 機器上開機。

<a id="kiyome"></a>

## kiyome

```console
$ kiyome /dev/disk4
This will ERASE all data on /dev/disk4. Continue? (y/N): y
Pass 1 of 1
Writing per-chunk unique data over 4 chunks, timing every chunk
Verify per-chunk unique data completed
Verify 0xAA completed
Verify 0x55 completed
Verify 0xFF completed
Verify 0x00 completed
Device ejected successfully
```

每一輪寫入並回讀五種圖案：每塊都唔同嘅 AES-CTR 資料，然後係 `0xAA`、`0x55`、`0xFF` 同 `0x00`。錯誤嘅 byte 會連同相關位線一齊報告，從而分辨線材或轉接器入面卡住嘅資料線同老化嘅媒體。`PASSES=N` 會重複執行，`CREATE=y` 會喺最後留低一個全新嘅 FAT 或 exFAT 檔案系統。

<a id="portability"></a>

## 可攜性

所有程式碼都係 POSIX `sh`，ShellCheck `-o all` 零發現，冇停用任何檢查。測試喺 macOS 嘅 `/bin/sh`、`dash`、`bash`、`bash --posix` 同 `zsh` 之下運行，亦喺特權容器入面嘅 Ubuntu 用相同嘅 shell 運行。

<a id="development"></a>

## 開發

| 指令 | 說明 |
|:--------|:------------|
| `make lint` | 對每個腳本執行 ShellCheck |
| `make test` | 喺系統 `sh` 之下執行 40 個 `bats` 測試 |
| `make test-all` | 喺每個已安裝嘅 shell 之下執行相同測試 |
| `make test-linux` | 由 Mac 喺特權 Ubuntu 容器入面執行相同測試 |

測試用 `hdiutil` 或 `losetup` 掛接以檔案為後端嘅磁碟，真實寫入，並喺 Linux 上用 `dmsetup` 注入 I/O 錯誤。CI 喺 Ubuntu 同 macOS 上運行。推送同 [`lib/core.sh`](lib/core.sh) 入面 `KAKIKOMI_VERSION` 一致嘅 `vX.Y.Z` 標籤，就會發佈 release 並更新 Homebrew formula。

## 授權

[MIT](LICENSE)
