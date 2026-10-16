<#
    VoiceMeeter 简体中文汉化启动器  (PowerShell 5.1 原生实现, 无需安装任何运行库)

    原理
    ----
    VoiceMeeter 会校验自身可执行文件的完整性(并用自身字节派生皮肤解密密钥),
    所以磁盘上的 exe 只要改动一个字节, 启动就会失败 —— 静态汉化补丁走不通。
    但实测证明: 这个校验读的是【磁盘文件】, 不是已加载的内存镜像。

    因此本启动器:
      1. 用 CREATE_SUSPENDED 挂起方式启动 VoiceMeeter
      2. 在它还没开始运行时, 就把中文写进内存里的 .rdata 字符串区
      3. 放行主线程
    这样程序启动时构建菜单、绘制界面拿到的就已经是中文, 连弹出的菜单也是中文
    (菜单项文字在菜单创建时会被复制进菜单结构, 事后改就来不及了)。
    磁盘上的 exe 一个字节都不改。

    用法
    ----
        powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1
        powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1 -Product banana
        powershell -ExecutionPolicy Bypass -File .\launch-cn.ps1 -Attach
            # 汉化已经运行的实例: 只能改界面标签(并强制重绘), 菜单改不到

    还原
    ----
    不需要还原: 磁盘文件从未被修改。关闭 VoiceMeeter 后正常启动它就是英文原版。
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'banana', 'potato')]
    [string]$Product = 'auto',
    [switch]$Attach,
    [string]$InstallDir = "C:\Program Files (x86)\VB\Voicemeeter",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

$Products = @{
    banana = @{ Exe = 'voicemeeterpro_x64.exe'; Plan = 'mempatch_banana.json'; Name = 'VoiceMeeter Banana' }
    potato = @{ Exe = 'voicemeeter8x64.exe';    Plan = 'mempatch_potato.json'; Name = 'VoiceMeeter Potato' }
}

function Say($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host "  $msg" -ForegroundColor $color }
}

# ---------------------------------------------------------------- P/Invoke
if (-not ('VMCN.Native' -as [type])) {
    Add-Type -Namespace VMCN -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta,
    bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern uint ResumeThread(IntPtr hThread);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
[DllImport("ntdll.dll")]
public static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, IntPtr ret);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr written);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool VirtualProtectEx(IntPtr h, IntPtr addr, IntPtr size, uint prot, out uint old);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool TerminateProcess(IntPtr h, uint code);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)]
public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder sb, int max);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr h, IntPtr r, bool erase);
[DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr rgn, uint flags);

public delegate bool EnumProc(IntPtr h, IntPtr lp);

[StructLayout(LayoutKind.Sequential)]
public struct STARTUPINFO {
  public int cb; public IntPtr r1, r2, r3; public int x, y, xs, ys, xc, yc, fill, flags;
  public short show; public short r4; public IntPtr r5, hIn, hOut, hErr; }
[StructLayout(LayoutKind.Sequential)]
public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int pid, tid; }
[StructLayout(LayoutKind.Sequential)]
public struct PBI { public IntPtr r1, peb, r2, r3, pid, r4; }

// 把补丁写进目标进程; 返回 [成功, 已汉化, 原文不符, 失败]
public static int[] Apply(IntPtr hp, long b, long[] rvas, byte[][] news, byte[][] origs,
                          out int already, out int mismatch, out int failed) {
  int ok = 0; already = 0; mismatch = 0; failed = 0;
  IntPtr read;
  for (int k = 0; k < rvas.Length; k++) {
    IntPtr addr = (IntPtr)(b + rvas[k]);
    byte[] o = origs[k]; byte[] n = news[k];
    int probe = Math.Max(o.Length, n.Length);
    byte[] cur = new byte[probe];
    if (!ReadProcessMemory(hp, addr, cur, probe, out read)) { failed++; continue; }
    bool isNew = true;
    for (int i = 0; i < n.Length; i++) { if (cur[i] != n[i]) { isNew = false; break; } }
    if (isNew) { already++; continue; }
    bool isOrig = true;
    for (int i = 0; i < o.Length; i++) { if (cur[i] != o[i]) { isOrig = false; break; } }
    if (!isOrig) { mismatch++; continue; }
    long reg = b + rvas[k]; long rgn = reg & ~0xFFFL;
    uint old;
    VirtualProtectEx(hp, (IntPtr)rgn, (IntPtr)(reg + n.Length - rgn), 0x40, out old);
    IntPtr wrote;
    bool w = WriteProcessMemory(hp, addr, n, n.Length, out wrote);
    uint o2;
    VirtualProtectEx(hp, (IntPtr)rgn, (IntPtr)(reg + n.Length - rgn), old, out o2);
    if (!w) { failed++; continue; }
    byte[] back = new byte[n.Length];
    ReadProcessMemory(hp, addr, back, n.Length, out read);
    bool eq = true;
    for (int i = 0; i < n.Length; i++) { if (back[i] != n[i]) { eq = false; break; } }
    if (!eq) { failed++; continue; }
    ok++;
  }
  return new int[] { ok, already, mismatch, failed };
}

public static long PebImageBase(IntPtr hp) {
  PBI pbi = new PBI();
  if (NtQueryInformationProcess(hp, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), IntPtr.Zero) != 0) return 0;
  if (pbi.peb == IntPtr.Zero) return 0;
  byte[] buf = new byte[8];
  IntPtr read;
  if (!ReadProcessMemory(hp, (IntPtr)(pbi.peb.ToInt64() + 0x10), buf, 8, out read)) return 0;
  return BitConverter.ToInt64(buf, 0);
}

public static IntPtr FindMainWindow(int pid) {
  IntPtr found = IntPtr.Zero;
  EnumWindows(delegate(IntPtr h, IntPtr lp) {
    uint p; GetWindowThreadProcessId(h, out p);
    if (p == (uint)pid) {
      var sb = new System.Text.StringBuilder(256);
      GetClassNameW(h, sb, 256);
      if (sb.ToString().Contains("VBCABLE")) { found = h; return false; }
    }
    return true;
  }, IntPtr.Zero);
  return found;
}
'@
}
$CREATE_SUSPENDED = 0x00000004
$STARTF_USESHOWWINDOW = 0x00000001
$SW_SHOWNORMAL = 1
$SW_SHOW = 5
$RDW = 0x0001 -bor 0x0004 -bor 0x0080 -bor 0x0100

function Resolve-Product {
    if ($Product -ne 'auto') { return $Product }
    foreach ($p in @('potato', 'banana')) {
        $pn = [IO.Path]::GetFileNameWithoutExtension($Products[$p].Exe)
        if (Get-Process -Name $pn -ErrorAction SilentlyContinue) { return $p }
    }
    foreach ($p in @('potato', 'banana')) {
        if (Test-Path (Join-Path $InstallDir $Products[$p].Exe)) { return $p }
    }
    throw "在 $InstallDir 下找不到 VoiceMeeter 主程序。"
}

function Load-Plan($key) {
    $info = $Products[$key]
    $path = Join-Path $ScriptDir $info.Plan
    if (-not (Test-Path $path)) { throw "找不到汉化计划文件: $path" }
    $plan = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $n = [int]$plan.count
    $rvas = New-Object 'long[]' $n
    $news = New-Object 'byte[][]' $n
    $origs = New-Object 'byte[][]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $it = $plan.items[$i]
        $rvas[$i] = [int64]$it.rva
        $nb = New-Object 'byte[]' ([int]($it.bytes.Length / 2))
        for ($j = 0; $j -lt $nb.Length; $j++) { $nb[$j] = [Convert]::ToByte($it.bytes.Substring($j*2,2),16) }
        $ob = New-Object 'byte[]' ([int]($it.orig.Length / 2))
        for ($j = 0; $j -lt $ob.Length; $j++) { $ob[$j] = [Convert]::ToByte($it.orig.Substring($j*2,2),16) }
        $news[$i] = $nb; $origs[$i] = $ob
    }
    return @{ Info = $info; Rvas = $rvas; News = $news; Origs = $origs; Count = $n }
}

function Invoke-Attach($key) {
    $p = Load-Plan $key
    $pn = [IO.Path]::GetFileNameWithoutExtension($p.Info.Exe)
    $proc = Get-Process -Name $pn -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { Say "$($p.Info.Name) 没有在运行" 'Yellow'; return $false }
    Say "附着到已运行的 $($p.Info.Name) (PID $($proc.Id))"
    $base = [VMCN.Native]::PebImageBase($proc.Handle)
    if ($base -eq 0) { Say "无法取得模块基址" 'Red'; return $false }
    $already = 0; $mismatch = 0; $failed = 0
    $r = [VMCN.Native]::Apply($proc.Handle, $base, $p.Rvas, $p.News, $p.Origs,
                              [ref]$already, [ref]$mismatch, [ref]$failed)
    Say "写入 $($r[0]) 项, 已汉化 $already 项, 原文不符 $mismatch 项, 失败 $failed 项" `
        $(if ($mismatch -eq 0 -and $failed -eq 0) { 'Green' } else { 'Yellow' })
    $hwnd = [VMCN.Native]::FindMainWindow($proc.Id)
    if ($hwnd -ne [IntPtr]::Zero) {
        [void][VMCN.Native]::RedrawWindow($hwnd, [IntPtr]::Zero, [IntPtr]::Zero, $RDW)
        [void][VMCN.Native]::InvalidateRect($hwnd, [IntPtr]::Zero, $true)
        [void][VMCN.Native]::UpdateWindow($hwnd)
        Say "已强制重绘界面" 'Green'
        Say "注意: 菜单文字在启动时已复制进菜单结构, 事后无法更改;" 'Yellow'
        Say "      想要菜单也是中文, 请用本启动器重新启动 VoiceMeeter。" 'Yellow'
    }
    return ($mismatch -eq 0 -and $failed -eq 0)
}

function Invoke-EarlyPatch($key) {
    $p = Load-Plan $key
    $exe = Join-Path $InstallDir $p.Info.Exe
    if (-not (Test-Path $exe)) { throw "找不到 $exe" }

    foreach ($n in @('voicemeeterpro_x64.exe', 'voicemeeter8x64.exe')) {
        Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($n)) -ErrorAction SilentlyContinue |
            ForEach-Object { Say "先关闭正在运行的 $($_.ProcessName)"; Stop-Process -Id $_.Id -Force }
    }
    Start-Sleep -Milliseconds 1500

    $si = New-Object VMCN.Native+STARTUPINFO
    $si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
    $si.flags = $STARTF_USESHOWWINDOW
    $si.show = $SW_SHOWNORMAL
    $pi = New-Object VMCN.Native+PROCESS_INFORMATION
    $ok = [VMCN.Native]::CreateProcessW($exe, $null, [IntPtr]::Zero, [IntPtr]::Zero,
            $false, $CREATE_SUSPENDED, [IntPtr]::Zero, (Split-Path $exe -Parent),
            [ref]$si, [ref]$pi)
    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "CreateProcess 失败 (Win32 错误 $err)"
    }
    Say "已挂起启动 $($p.Info.Name) (PID $($pi.pid))"

    try {
        $base = 0
        for ($i = 0; $i -lt 25 -and $base -eq 0; $i++) {
            Start-Sleep -Milliseconds 200
            $base = [VMCN.Native]::PebImageBase($pi.hProcess)
        }
        if ($base -eq 0) { throw "无法取得模块基址" }
        Say "模块基址 0x$($base.ToString('x')), 计划 $($p.Count) 项"

        $already = 0; $mismatch = 0; $failed = 0
        $r = [VMCN.Native]::Apply($pi.hProcess, $base, $p.Rvas, $p.News, $p.Origs,
                                  [ref]$already, [ref]$mismatch, [ref]$failed)
        if ($mismatch -gt 0) {
            Say "原文不符 $mismatch 项 —— exe 版本与计划不匹配, 已放弃以免损坏程序" 'Red'
            [void][VMCN.Native]::TerminateProcess($pi.hProcess, 1)
            [void][VMCN.Native]::CloseHandle($pi.hThread)
            [void][VMCN.Native]::CloseHandle($pi.hProcess)
            return $false
        }
        Say "挂起期间写入 $($r[0]) 项 (已汉化 $already, 失败 $failed)" 'Green'
    } catch {
        [void][VMCN.Native]::TerminateProcess($pi.hProcess, 1)
        [void][VMCN.Native]::CloseHandle($pi.hThread)
        [void][VMCN.Native]::CloseHandle($pi.hProcess)
        throw
    }

    [void][VMCN.Native]::ResumeThread($pi.hThread)
    Say "已放行, 程序正在启动..."
    Start-Sleep -Seconds 5
    $hwnd = [VMCN.Native]::FindMainWindow($pi.pid)
    if ($hwnd -ne [IntPtr]::Zero -and -not [VMCN.Native]::IsWindowVisible($hwnd)) {
        [void][VMCN.Native]::ShowWindow($hwnd, $SW_SHOW)
        Say "已显示主窗口"
    }
    [void][VMCN.Native]::CloseHandle($pi.hThread)
    [void][VMCN.Native]::CloseHandle($pi.hProcess)
    return $true
}

# ---------------------------------------------------------------- 主流程
Write-Host ""
Write-Host "VoiceMeeter 简体中文汉化启动器" -ForegroundColor White
Write-Host "磁盘上的 exe 不会被修改; 只改运行中进程的内存。" -ForegroundColor DarkGray

$key = Resolve-Product
Say "目标: $($Products[$key].Name)"

if ($Attach) { $ok = Invoke-Attach $key } else { $ok = Invoke-EarlyPatch $key }

Write-Host ""
if ($ok) {
    Write-Host "完成。界面与菜单应显示中文。" -ForegroundColor Green
} else {
    Write-Host "未能全部应用, 请查看上面的提示。" -ForegroundColor Yellow
}
Write-Host "还原方法: 关闭 VoiceMeeter 后正常启动它即可 (磁盘文件从未修改)。" -ForegroundColor DarkGray
