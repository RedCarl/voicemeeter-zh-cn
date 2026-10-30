<#
    安装 / 还原「version.dll 代理 + 汉化」（64 位版本）。

    机制
      1. 把现有的 version.dll（如果你之前放过别的）备份为 version_orig.dll
      2. 把本项目的 version.dll 放到原位
      3. 64 位 VoiceMeeter 启动时加载它 -> DllMain 阶段写入中文 ->
         早于 exe 入口点，所以菜单也是中文
      4. 我们的 DLL 实现 version.dll 全部 15 个导出：
         先尝试 vmzh_host.dll、再尝试 version_orig.dll，都没有就用系统 version.dll

    架构说明
      这个文件名只能放一种架构。放 64 位的进去：
        * 64 位 VoiceMeeter -> 使用我们的 DLL，界面中文
        * 32 位 VoiceMeeter -> 加载器跳过不匹配的同目录 DLL，回落到系统 DLL，
          照常运行（界面英文，不受影响）—— 已实测确认

    用法（需要管理员权限，会自动请求提升）：
        powershell -ExecutionPolicy Bypass -File .\src\install_version_dll.ps1
        powershell -ExecutionPolicy Bypass -File .\src\install_version_dll.ps1 -Restore
#>
[CmdletBinding()]
param(
    [switch]$Restore,
    [string]$InstallDir = "C:\Program Files (x86)\VB\Voicemeeter",
    [string]$SourceDll = ""
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path $ScriptDir -Parent
if (-not $SourceDll) { $SourceDll = Join-Path $RepoRoot 'build\version_x64.dll' }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "需要管理员权限，正在请求提升..." -ForegroundColor Yellow
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
              '-InstallDir', "`"$InstallDir`"")
    if ($SourceDll) { $argv += @('-SourceDll', "`"$SourceDll`"") }
    if ($Restore) { $argv += '-Restore' }
    Start-Process powershell -ArgumentList $argv -Verb RunAs
    exit
}

function Get-PeArch([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $o = [BitConverter]::ToInt32($b, 0x3C)
    $m = [BitConverter]::ToUInt16($b, $o + 4)
    switch ($m) { 0x8664 { 'x64' } 0x014c { 'x86' } default { "0x{0:x}" -f $m } }
}

$target  = Join-Path $InstallDir 'version.dll'
$origDll = Join-Path $InstallDir 'version_orig.dll'
$bakDir  = Join-Path $InstallDir '_VoiceMeeter_ZH_Backup'
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null

Write-Host ""
if ($Restore) {
    Write-Host "=== 还原 version.dll ===" -ForegroundColor White
    if (Test-Path $origDll) {
        if (Test-Path $target) { Remove-Item $target -Force }
        Rename-Item $origDll $target -Force
        Write-Host "  已把 version_orig.dll 改回 version.dll" -ForegroundColor Green
    } elseif (Test-Path $target) {
        Write-Host "  没有备份；直接删除我们放的 DLL" -ForegroundColor DarkGray
        Remove-Item $target -Force
        Write-Host "  已删除 version.dll（系统 DLL 会自动接管）" -ForegroundColor Green
    } else {
        Write-Host "  什么都没找到，可能本来就未安装" -ForegroundColor DarkGray
    }
    Read-Host "按回车退出"
    exit
}

Write-Host "=== 安装 version.dll 代理 + 汉化 ===" -ForegroundColor White

if (-not (Test-Path $SourceDll)) {
    Write-Host "  找不到编译产物: $SourceDll" -ForegroundColor Red
    Write-Host "  先运行: powershell -ExecutionPolicy Bypass -File .\src\build_dll.ps1 -Arch x64" -ForegroundColor Yellow
    Read-Host "按回车退出"
    exit 1
}

$srcArch = Get-PeArch $SourceDll
Write-Host "  待安装 DLL : $SourceDll  ($srcArch)" -ForegroundColor DarkGray
if ($srcArch -ne 'x64') {
    Write-Host "  警告: 这不是 64 位 DLL，64 位 VoiceMeeter 不会加载它" -ForegroundColor Yellow
}

if (Test-Path $target) {
    $curArch = Get-PeArch $target
    $curHash = (Get-FileHash $target -Algorithm SHA256).Hash
    $srcHash = (Get-FileHash $SourceDll -Algorithm SHA256).Hash
    if ($curHash -eq $srcHash) {
        Write-Host "  已经安装过了（哈希一致）" -ForegroundColor DarkGray
    } else {
        if (Test-Path $origDll) {
            Copy-Item $origDll (Join-Path $bakDir 'version_orig.dll.old') -Force
            Write-Host "  旧备份已转到 _VoiceMeeter_ZH_Backup\version_orig.dll.old" -ForegroundColor DarkGray
        }
        Copy-Item $target $origDll -Force
        Write-Host "  已备份原 DLL -> version_orig.dll  ($curArch)" -ForegroundColor Green
    }
} else {
    Write-Host "  目录里原本没有 version.dll，直接放我们的" -ForegroundColor DarkGray
}

Copy-Item $SourceDll $target -Force
$h = (Get-FileHash $target -Algorithm SHA256).Hash
Write-Host "  已安装 version.dll ($srcArch, SHA256 $($h.Substring(0,16))...)" -ForegroundColor Green

Write-Host ""
Write-Host "完成。启动 64 位 VoiceMeeter，界面与菜单即为中文。" -ForegroundColor Green
Write-Host "  64 位: 使用本 DLL     32 位: 自动回落系统 DLL，不受影响（界面英文）" -ForegroundColor DarkGray
Write-Host "还原: powershell -ExecutionPolicy Bypass -File .\src\install_version_dll.ps1 -Restore" -ForegroundColor DarkGray
Read-Host "按回车退出"
