@echo off
rem ============================================================
rem  VoiceMeeter Simplified-Chinese launcher  (just double-click)
rem
rem  Starts VoiceMeeter suspended, writes the Chinese strings into
rem  the process memory, then resumes it.  The exe on disk is NEVER
rem  modified, so VoiceMeeter's own integrity check and skin
rem  decryption key stay valid.
rem
rem  To restore the English UI: close VoiceMeeter and start it
rem  normally - no files were ever changed.
rem
rem  Extra arguments are passed through, e.g.
rem      -Product banana   -Attach   -InstallDir "D:\VB\Voicemeeter"
rem ============================================================
setlocal
set "PS1=%~dp0launch-cn.ps1"
if not exist "%PS1%" (
    echo [X] launch-cn.ps1 not found next to this file.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
    echo.
    echo Launcher exit code: %RC%
    pause
)
endlocal