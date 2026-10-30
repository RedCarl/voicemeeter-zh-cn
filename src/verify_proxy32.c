/* 32 位测试宿主：验证我们编译出来的 version.dll
 *   * 能否被 32 位进程 LoadLibrary（DllMain 不崩）
 *   * 15 个导出是否齐全
 *   * 转发链是否工作（此目录没有 vmzh_host.dll，应回落到系统 version.dll）
 */
#include <windows.h>
#include <stdio.h>

static const char *kExports[] = {
    "GetFileVersionInfoA", "GetFileVersionInfoByHandle", "GetFileVersionInfoExA",
    "GetFileVersionInfoExW", "GetFileVersionInfoSizeA", "GetFileVersionInfoSizeExA",
    "GetFileVersionInfoSizeExW", "GetFileVersionInfoSizeW", "GetFileVersionInfoW",
    "VerFindFileA", "VerFindFileW", "VerInstallFileA", "VerInstallFileW",
    "VerQueryValueA", "VerQueryValueW",
};

int main(int argc, char **argv)
{
    const wchar_t *dll = (argc > 1) ? L"version.dll" : L"version.dll";
    (void)argv;
    SetLastError(0);
    HMODULE h = LoadLibraryW(dll);
    if (!h) {
        printf("[X] LoadLibraryW 失败, 错误 %lu\n", GetLastError());
        return 1;
    }
    printf("[OK] DllMain 执行成功, DLL 已加载\n");

    int miss = 0;
    for (size_t i = 0; i < sizeof(kExports) / sizeof(kExports[0]); i++) {
        if (!GetProcAddress(h, kExports[i])) {
            printf("[X] 缺少导出 %s\n", kExports[i]);
            miss++;
        }
    }
    printf("[%s] 导出 %zu 个, 缺失 %d\n",
           miss ? "XX" : "OK", sizeof(kExports) / sizeof(kExports[0]), miss);

    typedef DWORD (WINAPI *SIZE_W)(LPCWSTR, LPDWORD);
    SIZE_W f = (SIZE_W)GetProcAddress(h, "GetFileVersionInfoSizeW");
    DWORD handle = 0;
    DWORD size = f ? f(L"C:\\Windows\\System32\\notepad.exe", &handle) : 0;
    printf("[%s] 转发 GetFileVersionInfoSizeW = %lu\n",
           size ? "OK" : "XX", size);

    FreeLibrary(h);
    return (miss == 0 && size > 0) ? 0 : 1;
}
