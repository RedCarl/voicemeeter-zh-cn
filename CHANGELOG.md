# 更新日志

## v1.1.0 — 支持 32 位构建 + 开机自启

**新增：32 位构建支持**

VoiceMeeter 有 32 位和 64 位两套主程序，字符串布局不同，之前只覆盖了 64 位。
开始菜单里不带 `(x64)` 字样的条目指向的就是 32 位版，所以按那种方式打开会一直是英文。

| 构建 | 可执行文件 | 条目 | 计划文件 |
|---|---|---|---|
| Potato 64 位 | `voicemeeter8x64.exe` | 552 | `mempatch_potato.json` |
| Potato 32 位 | `voicemeeter8.exe` | 548 | `mempatch_potato-x86.json` |
| Banana 64 位 | `voicemeeterpro_x64.exe` | 528 | `mempatch_banana.json` |
| Banana 32 位 | `voicemeeterpro.exe` | 524 | `mempatch_banana-x86.json` |

**新增：`src/setup_autostart.ps1`**

安装程序会在「启动」文件夹里放一个直接指向 exe 的快捷方式，开机时绕过汉化启动器，
于是每次开机都是英文。这个脚本把它改成经由 `launch-cn.ps1` 启动（原快捷方式备份为
`*.lnk.bak`，`-Remove` 可还原），并顺带在桌面建一个中文版快捷方式。

**修复**

* `peutil.PE` 之前按 64 位解析 ImageBase（PE32 的 `ImageBase` 在 `opt+28`，是 DWORD；
  PE32+ 在 `opt+24`，是 QWORD），现在两种都能正确解析。
* 启动器读取模块基址时区分架构：64 位读 `PEB+0x10`，32 位（WOW64）先经
  `ProcessWow64Information` 拿到 32 位 PEB，再读其 `+0x08`（4 字节）。
* `Mute BUS A1~B2` 的译文改为更紧凑的写法（`总线A1静音`）—— 32 位构建里这些字面量
  后面只剩 12 字节，原译文需要 13 字节。现在一份译文同时适配 32/64 位。
* `setup_autostart.ps1` 能识别「已被自己改过」的快捷方式，重复运行不会多建自启项
  （否则会开机启动两次）。

**文档**

* README 增加「打开还是英文？先看这几条」排查表。

## v1.0.0 — 首个公开版本

**汉化覆盖**

* 单行字符串 **528** 条（Banana）/ **552** 条（Potato），含 ANSI 与 UTF-16LE 两种编码
* 多行消息框 **59** 组（逐行等长对齐）
* 上下文帮助 XML：Banana 82 条、Potato 133 条

**已验证的目标版本**

| 产品 | 可执行文件 | 版本 | SHA256（原版） |
|---|---|---|---|
| VoiceMeeter Banana | `voicemeeterpro_x64.exe` | 2.1.3.0 | `d9ac1771…883fa2` |
| VoiceMeeter Potato | `voicemeeter8x64.exe` | 3.1.3.0 | `7f783f03…cb81eb` |

**实现**

* `launch-cn.ps1`：以 `CREATE_SUSPENDED` 挂起启动，在程序执行任何指令前把中文写入
  内存 `.rdata`，再放行。磁盘文件零改动。只依赖 Windows 自带的 PowerShell 5.1。
* `src/build_mempatch.py`：按**英文原文**在本机已安装的 exe 中定位字符串，
  生成补丁计划。仅需 Python 3 标准库。
* `src/peutil.py`：PE 解析、字符串字面量定位、安全写入范围计算、显示宽度估算。

**已确认的关键结论**

* VoiceMeeter 会校验自身文件完整性，且用自身字节派生皮肤密钥 ——
  改动 exe 任何一个字节都会导致启动崩溃（崩溃偏移固定 `0x1445f0`，位于 `memcpy` 循环内）。
* 该完整性校验读的是**磁盘文件**而非内存镜像 —— 这是本项目得以实现的前提。
* 弹出菜单的文字在菜单创建时即被复制，因此必须在**启动前**写入内存。
* `.data` 段的重复字面量是被程序解析的表项，翻译会导致崩溃，必须排除。
* 皮肤图内嵌文字无法汉化（5 个 RCDATA，熵 7.999，强加密）。
* 汉字显示宽度约为拉丁字母 2 倍，固定宽度的标签区（如 `Gate`）译文过宽会被裁剪。

**已知限制**

* 皮肤内嵌标签（`INTELLIPAN`、`AUDIBILITY`、`VIRTUAL INPUTS`、`MASTER SECTION`、
  `mono`、`EQ`、`Mute`、`solo`、`0dB`、`Menu`、`A1`–`B3` 等）保持英文。
* `Ok` 按钮因可用空间不足（4 字节）保留英文。
* VoiceMeeter 升级后需重新生成补丁计划。
