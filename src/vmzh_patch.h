/* VoiceMeeter 简体中文汉化 —— 可编入 DLL 的补丁模块
 *
 * 设计要点
 *   1. 运行在本进程内，所以不需要 ReadProcessMemory/WriteProcessMemory ——
 *      直接对已映射的镜像地址读写即可（VirtualProtect 临时放开 .rdata 写权限）。
 *   2. 时机完美：静态导入的 DLL 在 DllMain 阶段就执行，早于 exe 入口点，
 *      因此菜单创建时读到的已经是中文（菜单文案在创建时就复制进菜单结构，
 *      事后改 .rdata 是无效的）。
 *   3. 失败即放弃：逐条比对原文，任何一条不认识就整体放弃，界面保持英文。
 *      绝不因为汉化失败而影响宿主程序。
 *   4. 只认白名单宿主：本 DLL 也会被同目录的其它工具加载
 *      （VoicemeeterMacroButtons.exe / VoicemeeterBUSGEQ15.exe /
 *        VoicemeeterBUSMatrix8.exe），它们的布局不同，必须原样放行。
 *
 * 集成方法（在你自己的 DllMain 里，DLL_PROCESS_ATTACH 分支）
 *      #include "vmzh_patch.h"
 *      if (reason == DLL_PROCESS_ATTACH) {
 *          DisableThreadLibraryCalls(hInst);
 *          VmzhApplyForCurrentProcess();
 *      }
 *      return TRUE;                 // 无论如何都返回 TRUE
 *
 * 注意
 *   * 不要在 DllMain 里写日志文件或 LoadLibrary —— 会撞 loader lock。
 *     本模块只调用 VirtualProtect / memcmp / memcpy，全部安全。
 *   * 把 vmzh_table_*.h 当作纯十六进制数据即可，不涉及源码字符编码问题。
 */

#ifndef VMZH_PATCH_H
#define VMZH_PATCH_H

#ifdef __cplusplus
extern "C" {
#endif

/* 一条补丁记录（由 gen_c_table.py 生成的数据表使用） */
typedef struct {
    unsigned int   rva;      /* 目标字符串在镜像内的 RVA */
    unsigned int   origOff;  /* 原文在字节池中的偏移 */
    unsigned short origLen;  /* 原文长度 */
    unsigned int   newOff;   /* 中文串在字节池中的偏移 */
    unsigned short newLen;   /* 中文串长度（含终止符） */
} VMZH_ENTRY;

/* 统计信息 */
typedef struct {
    int applied;       /* 实际写入的条目数 */
    int already;       /* 已经是中文（重复调用） */
    int mismatch;      /* 原文不符的条目数 */
    int hostMatched;   /* 1 = 宿主在白名单内 */
} VMZH_RESULT;

/* 返回值：
 *   >= 0  成功应用的条目数（0 = 宿主不是白名单程序，未做任何事）
 *   -1    宿主匹配但版本不符，已整体放弃
 *   -2    取不到模块基址
 */
int VmzhApplyForCurrentProcess(void);

/* 需要详细结果时用这个 */
VMZH_RESULT VmzhApply(void);

#ifdef __cplusplus
}
#endif

#endif /* VMZH_PATCH_H */
