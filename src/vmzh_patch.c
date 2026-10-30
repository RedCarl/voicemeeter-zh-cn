/* VoiceMeeter 简体中文汉化 —— 可编入 DLL 的补丁实现
 *
 * 编译（zig cc，无需安装 VS）：
 *     x64: zig cc -target x86_64-windows-gnu -shared -O2 -o version.dll \
 *              vmzh_proxy.c vmzh_patch.c version.def
 *     x86: zig cc -target x86-windows-gnu -shared -O2 -o version.dll \
 *              vmzh_proxy.c vmzh_patch.c version.def
 *
 * 架构决定用哪套数据表：
 *   x64 -> voicemeeter8x64.exe (552) / voicemeeterpro_x64.exe (528)
 *   x86 -> voicemeeter8.exe    (548) / voicemeeterpro.exe     (524)
 * 两套表的字符串布局不同，不能混用。
 *
 * 设计要点
 *   1. 运行在本进程内，直接对已映射的镜像读写（VirtualProtect 临时放开 .rdata）。
 *   2. 时机：静态导入的 DLL 在 DllMain 阶段执行，早于 exe 入口点，
 *      所以菜单创建时读到的已经是中文（菜单文案创建时即被复制）。
 *   3. 先整体校验再统一写入：任何一条原文不符就整体放弃，绝不留半中半英。
 *   4. 只认白名单宿主：本 DLL 会被同目录的其它工具加载
 *      （VoicemeeterMacroButtons.exe 等），那些进程一个字节都不碰。
 *   5. DllMain 里只调 VirtualProtect / memcmp / memcpy，不碰 loader lock。
 */

#include <windows.h>
#include <string.h>
#include <wchar.h>

#include "vmzh_patch.h"

#ifdef _WIN64
#  include "vmzh_table_potato_x64.h"
#  include "vmzh_table_banana_x64.h"
#  define HOST_POTATO   VMZH_HOST_POTATO_X64
#  define HOST_BANANA   VMZH_HOST_BANANA_X64
#  define COUNT_POTATO  VMZH_COUNT_POTATO_X64
#  define COUNT_BANANA  VMZH_COUNT_BANANA_X64
#  define BLOB_POTATO   vmzh_potato_x64_blob
#  define BLOB_BANANA   vmzh_banana_x64_blob
#  define IDX_POTATO    vmzh_potato_x64_index
#  define IDX_BANANA    vmzh_banana_x64_index
#else
#  include "vmzh_table_potato_x86.h"
#  include "vmzh_table_banana_x86.h"
#  define HOST_POTATO   VMZH_HOST_POTATO_X86
#  define HOST_BANANA   VMZH_HOST_BANANA_X86
#  define COUNT_POTATO  VMZH_COUNT_POTATO_X86
#  define COUNT_BANANA  VMZH_COUNT_BANANA_X86
#  define BLOB_POTATO   vmzh_potato_x86_blob
#  define BLOB_BANANA   vmzh_banana_x86_blob
#  define IDX_POTATO    vmzh_potato_x86_index
#  define IDX_BANANA    vmzh_banana_x86_index
#endif

/* ------------------------------------------------------------------ 工具 */

static BYTE *VmzhImageBase(void)
{
    return (BYTE *)GetModuleHandleW(NULL);
}

static int VmzhHostName(wchar_t *out, int cch)
{
    wchar_t full[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, full, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;
    const wchar_t *slash = wcsrchr(full, L'\\');
    const wchar_t *name = slash ? slash + 1 : full;
    int len = (int)wcslen(name);
    if (len + 1 > cch) return 0;
    wmemcpy(out, name, len + 1);
    return 1;
}

static int VmzhNameEq(const wchar_t *a, const wchar_t *b)
{
    return _wcsicmp(a, b) == 0;
}

/* ------------------------------------------------------------------ 核心 */

VMZH_RESULT VmzhApply(void)
{
    VMZH_RESULT r;
    memset(&r, 0, sizeof(r));

    wchar_t host[MAX_PATH];
    if (!VmzhHostName(host, MAX_PATH)) return r;

    const unsigned char *blob  = NULL;
    const VMZH_ENTRY    *index = NULL;
    int count = 0;

    if (VmzhNameEq(host, HOST_POTATO)) {
        blob = BLOB_POTATO; index = IDX_POTATO;
        count = COUNT_POTATO; r.hostMatched = 1;
    } else if (VmzhNameEq(host, HOST_BANANA)) {
        blob = BLOB_BANANA; index = IDX_BANANA;
        count = COUNT_BANANA; r.hostMatched = 1;
    }

    if (!r.hostMatched) return r;      /* 白名单外：静默放行 */

    BYTE *base = VmzhImageBase();
    if (!base) { r.applied = -2; return r; }

    /* 先整体校验 */
    int i;
    for (i = 0; i < count; i++) {
        const VMZH_ENTRY *e = &index[i];
        BYTE *p = base + e->rva;
        const unsigned char *o = blob + e->origOff;
        const unsigned char *n = blob + e->newOff;

        if (memcmp(p, n, e->newLen) == 0) { r.already++; continue; }
        if (memcmp(p, o, e->origLen) != 0) { r.mismatch++; }
    }
    if (r.mismatch > 0) { r.applied = -1; return r; }

    /* 统一写入 */
    for (i = 0; i < count; i++) {
        const VMZH_ENTRY *e = &index[i];
        BYTE *p = base + e->rva;
        const unsigned char *n = blob + e->newOff;
        DWORD oldProt = 0;

        if (memcmp(p, n, e->newLen) == 0) { r.applied++; continue; }
        if (!VirtualProtect(p, e->newLen, PAGE_EXECUTE_READWRITE, &oldProt))
            continue;
        memcpy(p, n, e->newLen);
        VirtualProtect(p, e->newLen, oldProt, &oldProt);
        r.applied++;
    }
    return r;
}

int VmzhApplyForCurrentProcess(void)
{
    VMZH_RESULT r = VmzhApply();
    if (!r.hostMatched) return 0;
    return r.applied;
}
