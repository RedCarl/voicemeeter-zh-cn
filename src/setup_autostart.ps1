<#
    让 VoiceMeeter 的开机自启 / 桌面图标也走汉化启动器。

    为什么需要这一步:
      VoiceMeeter 的安装程序会在「启动」文件夹里放一个快捷方式，直接指向
      voicemeeterxxx.exe。开机时那条快捷方式启动的是原版，绕过了汉化启动器，
      所以界面会是英文。这个脚本把那条快捷方式改成经由 launch-cn.ps1 启动。

    用法:
        powershell -ExecutionPolicy Bypass -File .\src\setup_autostart.ps1
        powershell -ExecutionPolicy Bypass -File .\src\setup_autostart.ps1 -Remove
        powershell -ExecutionPolicy Bypass -File .\src\setup_autostart.ps1 -Product potato-x86

    注意: 只动你自己用户的「启动」文件夹和桌面，不需要管理员权限。
          原快捷方式会备份成 *.lnk.bak，-Remove 可还原。
#>
[CmdletBinding()]
param(
    [ValidateSet('potato', 'potato-x86', 'banana', 'banana-x86')]
    [string]$Product = 'potato',
    [switch]$Remove,
    [string]$InstallDir = "C:\Program Files (x86)\VB\Voicemeeter"
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path $ScriptDir -Parent
$Launcher = Join-Path $RepoRoot 'launch-cn.ps1'
$StartupDir = [Environment]::GetFolderPath('Startup')
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$sh = New-Object -ComObject WScript.Shell

$NameMap = @{
    potato = 'VoiceMeeter Potato (64 位)'
    'potato-x86' = 'VoiceMeeter Potato (32 位)'
    banana = 'VoiceMeeter Banana (64 位)'
    'banana-x86' = 'VoiceMeeter Banana (32 位)'
}
$ExeMap = @{
    potato = 'voicemeeter8x64.exe'; 'potato-x86' = 'voicemeeter8.exe'
    banana = 'voicemeeterpro_x64.exe'; 'banana-x86' = 'voicemeeterpro.exe'
}

if (-not (Test-Path $Launcher)) {
    Write-Host "找不到 $Launcher" -ForegroundColor Red
    exit 1
}

# 找出安装程序留下的、直接指向 VoiceMeeter 主程序的自启快捷方式
$existing = @()
if (Test-Path $StartupDir) {
    $existing = Get-ChildItem $StartupDir -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $sc = $sh.CreateShortcut($_.FullName)
                # 已经被本脚本改过的（指向 powershell + launch-cn.ps1）也要认出来，
                # 否则重复运行会多建一个自启项，导致开机启动两次。
                if ($sc.Arguments -match 'launch-cn\.ps1') { return $true }
                $t = $sc.TargetPath
                return [bool]($t -and (Split-Path $t -Leaf) -match '^voicemeeter.*\.exe$')
            } catch { return $false }
        }
}

if ($Remove) {
    Write-Host "=== 还原开机自启 ===" -ForegroundColor White
    $done = $false
    foreach ($f in $existing) {
        # 已是经由启动器的，跳过
        if ($sh.CreateShortcut($f.FullName).TargetPath -match 'powershell') { continue }
        if (Test-Path "$($f.FullName).bak") {
            Copy-Item "$($f.FullName).bak" $f.FullName -Force
            Write-Host "  已从备份还原: $($f.Name)" -ForegroundColor Green
            $done = $true
        }
    }
    if (-not $done) { Write-Host "  没有找到可还原的备份" -ForegroundColor DarkGray }
    Get-ChildItem $DesktopDir -Filter '*中文*.lnk' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force; Write-Host "  已删除桌面快捷方式: $($_.Name)" -ForegroundColor Green }
    Read-Host "按回车退出"
    exit
}

Write-Host "=== 配置开机自启与桌面快捷方式 ===" -ForegroundColor White
Write-Host "  目标版本: $($NameMap[$Product])" -ForegroundColor DarkGray

# 1) 改写自启快捷方式
if ($existing.Count -eq 0) {
    $lnk = Join-Path $StartupDir 'Voicemeeter (中文).lnk'
    Write-Host "  启动文件夹里没有 VoiceMeeter 快捷方式，新建一个" -ForegroundColor DarkGray
} else {
    $lnk = $existing[0].FullName
    if (-not (Test-Path "$lnk.bak")) {
        Copy-Item $lnk "$lnk.bak" -Force
        Write-Host "  已备份原快捷方式 -> $lnk.bak" -ForegroundColor DarkGray
    }
}
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
               $Launcher + '" -Product ' + $Product
$s.WorkingDirectory = $RepoRoot
$s.Description = "$($NameMap[$Product]) 简体中文（开机自启，经汉化启动器）"
$s.Save()
Write-Host "  已改写自启: $([IO.Path]::GetFileName($lnk))" -ForegroundColor Green

# 2) 桌面快捷方式（名字跟着所选的构建走）
$shortName = $NameMap[$Product] -replace ' \(', ' 中文 ('
$dlnk = Join-Path $DesktopDir "$shortName.lnk"
$s2 = $sh.CreateShortcut($dlnk)
$s2.TargetPath = Join-Path $RepoRoot '启动汉化版VoiceMeeter.cmd'
$s2.WorkingDirectory = $RepoRoot
$s2.Description = "以简体中文界面启动 $($NameMap[$Product])"
$iconExe = Join-Path $InstallDir $ExeMap[$Product]
if (Test-Path $iconExe) { $s2.IconLocation = "$iconExe,0" }
$s2.Save()
Write-Host "  已创建桌面快捷方式: $dlnk" -ForegroundColor Green

Write-Host ""
Write-Host "完成。下次开机时 VoiceMeeter 会以中文界面启动。" -ForegroundColor Green
Write-Host "还原: powershell -ExecutionPolicy Bypass -File .\src\setup_autostart.ps1 -Remove" -ForegroundColor DarkGray
Read-Host "按回车退出"
