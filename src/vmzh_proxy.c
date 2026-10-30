/* VoiceMeeter 简体中文汉化 —— version.dll 代理 + 汉化
 *
 * 这个 DLL 占用 VoiceMeeter 目录下的 version.dll 位置（VoiceMeeter 静态导入它，
 * 且 version 不在 KnownDLLs 里，所以同目录的这份会被优先加载）。
 *
 * 它做两件事：
 *   1. DllMain(PROCESS_ATTACH) 时把中文写进自己的 .rdata（只对白名单宿主生效）。
 *      DLL 在 exe 入口点之前加载，所以菜单创建时拿到的已经是中文。
 *   2. 完整实现 version.dll 的导出：优先转发给同目录的 vmzh_host.dll
 *      （= 你原来的补丁 DLL 改名而来），没有就转发给系统的 version.dll。
 *      转发是**惰性**的（首次调用时用 LoadLibrary 解析），避免在 DllMain 里
 *      撞 loader lock。
 *
 * 编译（zig cc，无需安装 VS）：
 *     zig cc -target x86-windows-gnu -shared -O2 -fno-sanitize=all \
 *            -o version.dll vmzh_proxy.c vmzh_patch.c
 */

#include <windows.h>
#include <winver.h>
#include <string.h>
#include <wchar.h>

#include "vmzh_patch.h"

/* ------------------------------------------------------------------ 转发目标 */

static HMODULE g_fwd = NULL;          /* 真正的 version.dll 实现 */
static INIT_ONCE g_once = INIT_ONCE_STATIC_INIT;

/* 追加字符串（不依赖 swprintf_s，MinGW 下更省事） */
static int AppendW(wchar_t *buf, size_t cch, const wchar_t *s)
{
    size_t a = wcslen(buf), b = wcslen(s);
    if (a + b + 1 > cch) return 0;
    wcscpy(buf + a, s);
    return 1;
}

static BOOL CALLBACK FwdInitOnce(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    (void)once; (void)param;
    wchar_t dir[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, dir, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        wchar_t *slash = wcsrchr(dir, L'\\');
        if (slash) *(slash + 1) = L'\0';        /* 保留结尾反斜杠 */
        else dir[0] = L'\0';

        wchar_t host[MAX_PATH];
        /* 1) 优先：同目录的 vmzh_host.dll（保留用户原有补丁） */
        wcscpy(host, dir);
        if (AppendW(host, MAX_PATH, L"vmzh_host.dll"))
            g_fwd = LoadLibraryExW(host, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
        /* 2) 其次：同目录里可能还有一份原始 version.dll 备份 */
        if (!g_fwd) {
            wcscpy(host, dir);
            if (AppendW(host, MAX_PATH, L"version_orig.dll"))
                g_fwd = LoadLibraryExW(host, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
        }
    }
    /* 3) 兜底：系统 version.dll（绝对路径，避免再次命中自己） */
    if (!g_fwd) {
        wchar_t sys[MAX_PATH];
        UINT k = GetSystemDirectoryW(sys, MAX_PATH);
        if (k > 0 && k < MAX_PATH && AppendW(sys, MAX_PATH, L"\\version.dll"))
            g_fwd = LoadLibraryExW(sys, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    }
    if (ctx) *(HMODULE *)ctx = g_fwd;
    return TRUE;
}

static HMODULE Fwd(void)
{
    PVOID ctx = NULL;
    InitOnceExecuteOnce(&g_once, FwdInitOnce, NULL, &ctx);
    return g_fwd;
}

#define RESOLVE(name)                                   \
    static FARPROC p_##name = NULL;                     \
    if (!p_##name) {                                    \
        HMODULE m = Fwd();                              \
        if (m) p_##name = GetProcAddress(m, #name);     \
        if (!p_##name) return 0;                        \
    }

/* --------------------------------------------------- version.dll 的 15 个导出 */

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeA(LPCSTR f, LPDWORD h)
{ RESOLVE(GetFileVersionInfoSizeA);
  return ((DWORD (WINAPI *)(LPCSTR, LPDWORD))p_GetFileVersionInfoSizeA)(f, h); }

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeW(LPCWSTR f, LPDWORD h)
{ RESOLVE(GetFileVersionInfoSizeW);
  return ((DWORD (WINAPI *)(LPCWSTR, LPDWORD))p_GetFileVersionInfoSizeW)(f, h); }

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeExA(DWORD fl, LPCSTR f, LPDWORD h)
{ RESOLVE(GetFileVersionInfoSizeExA);
  return ((DWORD (WINAPI *)(DWORD, LPCSTR, LPDWORD))p_GetFileVersionInfoSizeExA)(fl, f, h); }

__declspec(dllexport) DWORD WINAPI GetFileVersionInfoSizeExW(DWORD fl, LPCWSTR f, LPDWORD h)
{ RESOLVE(GetFileVersionInfoSizeExW);
  return ((DWORD (WINAPI *)(DWORD, LPCWSTR, LPDWORD))p_GetFileVersionInfoSizeExW)(fl, f, h); }

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoA(LPCSTR f, DWORD h, DWORD len, LPVOID d)
{ RESOLVE(GetFileVersionInfoA);
  return ((BOOL (WINAPI *)(LPCSTR, DWORD, DWORD, LPVOID))p_GetFileVersionInfoA)(f, h, len, d); }

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoW(LPCWSTR f, DWORD h, DWORD len, LPVOID d)
{ RESOLVE(GetFileVersionInfoW);
  return ((BOOL (WINAPI *)(LPCWSTR, DWORD, DWORD, LPVOID))p_GetFileVersionInfoW)(f, h, len, d); }

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoExA(DWORD fl, LPCSTR f, DWORD h, DWORD len, LPVOID d)
{ RESOLVE(GetFileVersionInfoExA);
  return ((BOOL (WINAPI *)(DWORD, LPCSTR, DWORD, DWORD, LPVOID))p_GetFileVersionInfoExA)(fl, f, h, len, d); }

__declspec(dllexport) BOOL WINAPI GetFileVersionInfoExW(DWORD fl, LPCWSTR f, DWORD h, DWORD len, LPVOID d)
{ RESOLVE(GetFileVersionInfoExW);
  return ((BOOL (WINAPI *)(DWORD, LPCWSTR, DWORD, DWORD, LPVOID))p_GetFileVersionInfoExW)(fl, f, h, len, d); }

/* 非公开导出：签名不确定，用通用转发，仅保证不阻断 */
__declspec(dllexport) DWORD WINAPI GetFileVersionInfoByHandle(DWORD a, DWORD b, DWORD c, DWORD d)
{ RESOLVE(GetFileVersionInfoByHandle);
  return ((DWORD (WINAPI *)(DWORD, DWORD, DWORD, DWORD))p_GetFileVersionInfoByHandle)(a, b, c, d); }

__declspec(dllexport) BOOL WINAPI VerQueryValueA(LPCVOID blk, LPCSTR sub, LPVOID *out, PUINT len)
{ RESOLVE(VerQueryValueA);
  return ((BOOL (WINAPI *)(LPCVOID, LPCSTR, LPVOID *, PUINT))p_VerQueryValueA)(blk, sub, out, len); }

__declspec(dllexport) BOOL WINAPI VerQueryValueW(LPCVOID blk, LPCWSTR sub, LPVOID *out, PUINT len)
{ RESOLVE(VerQueryValueW);
  return ((BOOL (WINAPI *)(LPCVOID, LPCWSTR, LPVOID *, PUINT))p_VerQueryValueW)(blk, sub, out, len); }

__declspec(dllexport) DWORD WINAPI VerFindFileA(DWORD fl, LPSTR fn, LPSTR wd, LPSTR ad,
                                               LPSTR cd, PUINT cdl, LPSTR dd, PUINT ddl)
{ RESOLVE(VerFindFileA);
  return ((DWORD (WINAPI *)(DWORD, LPSTR, LPSTR, LPSTR, LPSTR, PUINT, LPSTR, PUINT))
         p_VerFindFileA)(fl, fn, wd, ad, cd, cdl, dd, ddl); }

__declspec(dllexport) DWORD WINAPI VerFindFileW(DWORD fl, LPWSTR fn, LPWSTR wd, LPWSTR ad,
                                               LPWSTR cd, PUINT cdl, LPWSTR dd, PUINT ddl)
{ RESOLVE(VerFindFileW);
  return ((DWORD (WINAPI *)(DWORD, LPWSTR, LPWSTR, LPWSTR, LPWSTR, PUINT, LPWSTR, PUINT))
         p_VerFindFileW)(fl, fn, wd, ad, cd, cdl, dd, ddl); }

__declspec(dllexport) DWORD WINAPI VerInstallFileA(DWORD fl, LPSTR sf, LPSTR df, LPSTR sd,
                                                   LPSTR dd, LPSTR cd, LPSTR td, PUINT tdl)
{ RESOLVE(VerInstallFileA);
  return ((DWORD (WINAPI *)(DWORD, LPSTR, LPSTR, LPSTR, LPSTR, LPSTR, LPSTR, PUINT))
         p_VerInstallFileA)(fl, sf, df, sd, dd, cd, td, tdl); }

__declspec(dllexport) DWORD WINAPI VerInstallFileW(DWORD fl, LPWSTR sf, LPWSTR df, LPWSTR sd,
                                                   LPWSTR dd, LPWSTR cd, LPWSTR td, PUINT tdl)
{ RESOLVE(VerInstallFileW);
  return ((DWORD (WINAPI *)(DWORD, LPWSTR, LPWSTR, LPWSTR, LPWSTR, LPWSTR, LPWSTR, PUINT))
         p_VerInstallFileW)(fl, sf, df, sd, dd, cd, td, tdl); }

/* ------------------------------------------------------------------ 入口 */

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hInst);
        /* 只做内存写入，不调用任何 loader 相关 API，DllMain 里安全 */
        VmzhApplyForCurrentProcess();
    }
    return TRUE;
}
