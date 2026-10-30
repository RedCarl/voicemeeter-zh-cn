<#
    编译 version.dll 代理（含汉化）。

    需要 zig（便携，无需安装 VS）。若你没装，可以先：
        python -m pip install ziglang
    然后本脚本会自动在常见位置找到 zig.exe，或用 -Zig 指定。

    产物: build\version.dll  (x86)

    用法:
        powershell -ExecutionPolicy Bypass -File .\src\build_dll.ps1
        powershell -ExecutionPolicy Bypass -File .\src\build_dll.ps1 -Zig "C:\zig\zig.exe"
#>
[CmdletBinding()]
param(
    [string]$Zig = "",
    [ValidateSet('x86', 'x64')]
    [string]$Arch = 'x86'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path $ScriptDir -Parent
$Build = Join-Path $RepoRoot 'build'
New-Item -ItemType Directory -Force -Path $Build | Out-Null

if (-not $Zig) {
    $cands = @(
        (Join-Path $env:TEMP 'vmtoolchain\pkg\ziglang\zig.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\zig\zig.exe')
    )
    $Zig = ($cands | Where-Object { Test-Path $_ } | Select-Object -First 1)
    if (-not $Zig) {
        $c = Get-Command zig -ErrorAction SilentlyContinue
        if ($c) { $Zig = $c.Source }
    }
}
if (-not $Zig -or -not (Test-Path $Zig)) {
    Write-Host "找不到 zig.exe。" -ForegroundColor Red
    Write-Host "  python -m pip install ziglang" -ForegroundColor Yellow
    Write-Host "  （装完通常位于 %TEMP%\vmtoolchain\pkg\ziglang\zig.exe）" -ForegroundColor DarkGray
    exit 1
}

$target = if ($Arch -eq 'x86') { 'x86-windows-gnu' } else { 'x86_64-windows-gnu' }
$outName = if ($Arch -eq 'x86') { 'version.dll' } else { 'version_x64.dll' }

Write-Host "zig      : $Zig" -ForegroundColor DarkGray
Write-Host "目标     : $target" -ForegroundColor DarkGray
& $Zig version

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $env:TEMP 'zigcache'
$env:ZIG_LOCAL_CACHE_DIR  = Join-Path $env:TEMP 'zigcache'

Push-Location $ScriptDir
try {
    & $Zig cc -target $target -shared -O2 -fno-sanitize=all `
        -Wno-dll-attribute-on-redeclaration `
        -o (Join-Path $Build $outName) `
        vmzh_proxy.c vmzh_patch.c version.def
    if ($LASTEXITCODE -ne 0) { throw "编译失败 ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

$f = Get-Item (Join-Path $Build $outName)
$b = [System.IO.File]::ReadAllBytes($f.FullName)
$o = [BitConverter]::ToInt32($b, 0x3C)
$m = [BitConverter]::ToUInt16($b, $o + 4)
Write-Host ""
Write-Host "✔ 已生成 $($f.FullName)" -ForegroundColor Green
Write-Host "  大小   : $([Math]::Round($f.Length/1KB,1)) KB"
Write-Host "  架构   : $(switch ($m) { 0x8664 {'x64'} 0x014c {'x86'} default { "0x{0:x}" -f $m } })"
Write-Host "  SHA256 : $((Get-FileHash $f.FullName -Algorithm SHA256).Hash)"
