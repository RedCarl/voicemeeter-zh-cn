# 更新日志

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
