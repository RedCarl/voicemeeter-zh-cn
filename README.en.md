# VoiceMeeter Simplified Chinese Localization

A Chinese (Simplified) UI patch for [VoiceMeeter](https://vb-audio.com/Voicemeeter/).

**No VoiceMeeter file is modified** — the Chinese text is written into the
process memory at the moment the program starts.

![Chinese main menu](docs/images/menu-zh.png)

> [中文说明见 README.md](README.md)

---

## ⚠️ Read this first

* This is an **unofficial** fan project. It is **not affiliated with, endorsed by,
  or authorized by** VB-Audio / Vincent Burel.
* **VoiceMeeter® and VB-Audio® are trademarks of VB-Audio.** They are used here
  only descriptively.
* This repository contains **no VoiceMeeter binaries** (no exe, dll, driver or skin
  images) — only my own scripts, plain-text translation tables, and translated
  help XML. Please install VoiceMeeter yourself from the official site.
* VoiceMeeter is donationware. **If you use it, please support the author.**
* This project only translates UI text. It does **not** touch, bypass or weaken any
  licensing / activation logic.
* See [NOTICE.md](NOTICE.md) for details.

---

## Features

| | |
|---|---|
| Entries | **528** (Banana) / **552** (Potato), including 59 multi-line message boxes |
| Covers | main menu, tray menu, context menus, all dialogs, error/warning boxes, channel & bus labels, device hints, fader labels |
| Disk changes | **none** — no file is modified, replaced or added |
| Restore | close VoiceMeeter and start it normally — back to English |
| Requirements | Windows PowerShell 5.1 (built in). No Python, nothing to install |
| Uninstall | nothing to uninstall |

## Quick start

1. Install VoiceMeeter (Banana or Potato, 64-bit)
2. Download this repository (`Code` → `Download ZIP`, or `git clone`)
3. Double-click **`启动汉化版VoiceMeeter.cmd`**

> ⚠️ **You must launch it with this launcher.** If you start VoiceMeeter yourself
> first, the menus cannot be translated — their text is copied into the menu
> structure when the menu is created. The launcher detects this case and tells you.

```powershell
# auto-detect the installed product
powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1

# pick a product / attach to a running instance / custom install dir
powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1 -Product banana
powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1 -Attach
powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1 -InstallDir "D:\VB\Voicemeeter"
```

## How it works

VoiceMeeter validates the integrity of its own executable (and derives its skin
decryption key from its own bytes), so **changing a single byte on disk prevents
it from starting** — a static patch is impossible.

But experiments showed that **this check reads the file on disk, not the loaded
image**. So the launcher:

```
starts VoiceMeeter suspended
   ↓
writes Chinese into the .rdata string pool while it has not run a single instruction
   ↓
resumes the main thread — menus and widgets are built with Chinese from the start
```

Full write-up and experimental evidence: **[docs/how-it-works.md](docs/how-it-works.md)**
(Chinese). Hard-won engineering constraints: **[docs/engineering-notes.md](docs/engineering-notes.md)**.

## Limitations

* **Text baked into the skin images cannot be translated.** Labels such as
  `INTELLIPAN`, `AUDIBILITY`, `VIRTUAL INPUTS`, `HARDWARE OUT`, `MASTER SECTION`,
  `Normal mode`, `mono`, `EQ`, `Mute`, `solo`, `0dB`, `Menu`, `A1`–`B3` live inside
  five strongly encrypted `RCDATA` resources (entropy 7.999, undecryptable).
* The `Ok` button keeps its English text: only 4 bytes are available after the
  literal, and `确定` needs 5.
* The launcher uses `WriteProcessMemory` / `VirtualProtectEx` on a process in your
  own user session. A few antivirus products may flag this. The source is fully
  open (`Apply` in `launch-cn.ps1`) — review it before use.

## Regenerating for a new VoiceMeeter version

The bundled `mempatch_*.json` target `voicemeeterpro_x64.exe` 2.1.3.0 and
`voicemeeter8x64.exe` 3.1.3.0. After a VoiceMeeter update, regenerate them from
your own installed copy (Python 3, standard library only):

```bash
python src/build_mempatch.py --product potato
python src/build_mempatch.py --product banana
```

An outdated plan cannot damage anything: the launcher verifies the original bytes
of every entry and reports a mismatch instead of writing blindly.

## Contributing translations

Edit **[translations/zh_cn.py](translations/zh_cn.py)** — a plain text mapping:

```python
TRANSLATIONS = [
    ("Stereo Input", "立体声输入"),          # (english, chinese)
    ...
]
```

Do not change the English side: the builder uses it to locate strings in the exe.
`MULTILINE` entries must stay **line-for-line equal in byte length**, because the
compiler suffix-merged those literals. Run `python src/build_mempatch.py --check`
to get warnings about entries that do not fit or whose CJK width may be clipped by
a fixed-width control.

## License

My own code and translations are released under the [MIT License](LICENSE).
VoiceMeeter itself, its UI strings and its help documentation remain the property
of VB-Audio. See [NOTICE.md](NOTICE.md).
