/* 32 位程序，**静态导入** version.dll。
 *
 * 用途：验证"目录里放一个 x64 的 version.dll"时，32 位程序还能不能启动。
 * 这是静态导入场景（语音软件真正的场景），与显式 LoadLibrary 的行为不同。
 *
 * 判定：
 *   能启动且返回非 0   -> 加载器跳过了不匹配架构的同目录 DLL，回落到系统 DLL
 *   无法启动/报错 193  -> 同目录的错架构 DLL 会让 32 位程序起不来
 */
#include <windows.h>
#include <winver.h>
#include <stdio.h>

int main(void)
{
    DWORD handle = 0;
    DWORD size = GetFileVersionInfoSizeW(L"C:\\Windows\\System32\\notepad.exe", &handle);
    printf("已启动 (GetFileVersionInfoSizeW = %lu)\n", size);
    return size > 0 ? 0 : 2;
}
