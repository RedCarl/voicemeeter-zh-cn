<#
    安装 / 还原汉化后的 VoiceMeeter 上下文帮助（帮助 XML）。

    这个操作只替换两个纯文本 XML 文件，不涉及 exe，
    因此不受 VoiceMeeter 完整性校验影响（已实测：原版 exe + 汉化 XML 正常启动）。

    需要管理员权限（要写入 C:\Program Files (x86)\...），脚本会自动请求提升。

    用法:
        powershell -ExecutionPolicy Bypass -File .\install_help.ps1
        powershell -ExecutionPolicy Bypass -File .\install_help.ps1 -Restore
#>
[CmdletBinding()]
param(
    [switch]$Restore,
    [string]$InstallDir = "C:\Program Files (x86)\VB\Voicemeeter"
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path $ScriptDir -Parent
$HelpDir = Join-Path $RepoRoot 'translations\help'
$BackupDir = Join-Path $InstallDir '_VoiceMeeter_ZH_Backup'

$Files = @('VoicemeeterBanana_Help.xml', 'VoicemeeterPotato_Help.xml')

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "需要管理员权限，正在请求提升..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                 '-InstallDir', "`"$InstallDir`"")
    if ($Restore) { $argList += '-Restore' }
    Start-Process -FilePath 'powershell' -ArgumentList $argList -Verb RunAs
    exit
}

if (-not (Test-Path $InstallDir)) {
    Write-Host "找不到安装目录: $InstallDir" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

Write-Host ""
if ($Restore) {
    Write-Host "=== 还原上下文帮助为英文原版 ===" -ForegroundColor White
    foreach ($f in $Files) {
        $bak = Join-Path $BackupDir "$f.orig"
        $dst = Join-Path $InstallDir $f
        if (Test-Path $bak) {
            Copy-Item $bak $dst -Force
            Write-Host "  已还原 $f" -ForegroundColor Green
        } elseif (Test-Path $dst) {
            Write-Host "  跳过 $f (没有备份，可能本来就是原版)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "=== 安装汉化的上下文帮助 ===" -ForegroundColor White
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    foreach ($f in $Files) {
        $src = Join-Path $HelpDir $f
        $dst = Join-Path $InstallDir $f
        if (-not (Test-Path $src)) {
            Write-Host "  跳过 $f (仓库里没有这个文件)" -ForegroundColor DarkGray
            continue
        }
        if (Test-Path $dst) {
            $bak = Join-Path $BackupDir "$f.orig"
            if (-not (Test-Path $bak)) {
                Copy-Item $dst $bak -Force
                Write-Host "  已备份原文件 -> $bak" -ForegroundColor DarkGray
            }
        }
        Copy-Item $src $dst -Force
        Write-Host "  已安装 $f" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "注意: 上下文帮助是菜单里的开关, 默认关闭。" -ForegroundColor Yellow
    Write-Host "      请在 VoiceMeeter 的 Menu 里打开「在标题栏显示上下文帮助」后才能看到。" -ForegroundColor Yellow
}
Write-Host ""
Read-Host "按回车退出"
