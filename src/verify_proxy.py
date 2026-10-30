# -*- coding: utf-8 -*-
"""在没有 VoiceMeeter 参与的独立进程里验证编译出来的 version.dll：

  * 能否被 LoadLibrary 加载（= DllMain 没崩）
  * 15 个导出是否齐全
  * 转发链是否真的工作（此处目录里没有 vmzh_host.dll，
    应当自动回落到系统 version.dll）

这样不需要碰 VoiceMeeter 就能验证代理层。
"""
import ctypes as C
import ctypes.wintypes as W
import os
import sys

EXPORTS = [
    "GetFileVersionInfoA", "GetFileVersionInfoByHandle", "GetFileVersionInfoExA",
    "GetFileVersionInfoExW", "GetFileVersionInfoSizeA", "GetFileVersionInfoSizeExA",
    "GetFileVersionInfoSizeExW", "GetFileVersionInfoSizeW", "GetFileVersionInfoW",
    "VerFindFileA", "VerFindFileW", "VerInstallFileA", "VerInstallFileW",
    "VerQueryValueA", "VerQueryValueW",
]


def main():
    dll = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "build", "version.dll")
    if not os.path.exists(dll):
        print("找不到", dll)
        return 1
    print(f"目标: {dll}\n大小: {os.path.getsize(dll):,} 字节")

    # 用一个不被劫持的名字加载，避免影响本进程真正的 version.dll 解析
    tmp = os.path.join(os.environ["TEMP"], "vmzh_verify_copy.dll")
    with open(dll, "rb") as f:
        data = f.read()
    with open(tmp, "wb") as f:
        f.write(data)

    k = C.WinDLL("kernel32", use_last_error=True)
    k.LoadLibraryW.restype = C.c_void_p
    k.LoadLibraryW.argtypes = [C.c_wchar_p]
    k.GetProcAddress.restype = C.c_void_p
    k.GetProcAddress.argtypes = [C.c_void_p, C.c_char_p]
    h = k.LoadLibraryW(tmp)
    if not h:
        print("✘ LoadLibrary 失败，错误码", C.get_last_error())
        return 1
    print("✔ DllMain 执行成功，DLL 已加载")

    missing = []
    for name in EXPORTS:
        if not k.GetProcAddress(h, name.encode()):
            missing.append(name)
    print(f"导出检查: {len(EXPORTS) - len(missing)}/{len(EXPORTS)} 齐全"
          + ("" if not missing else "  缺失: " + ", ".join(missing)))

    # 转发验证：调用 GetFileVersionInfoSizeW 读一个真实文件的版本资源
    target = os.path.join(os.environ["SystemRoot"], "System32", "notepad.exe")
    fn = C.WinDLL(tmp)
    fn.GetFileVersionInfoSizeW.restype = W.DWORD
    fn.GetFileVersionInfoSizeW.argtypes = [W.LPCWSTR, C.POINTER(W.DWORD)]
    handle = W.DWORD(0)
    size = fn.GetFileVersionInfoSizeW(target, C.byref(handle))
    print(f"转发验证: GetFileVersionInfoSizeW(notepad.exe) = {size}"
          + ("  ✔ 转发链正常" if size > 0 else "  ✘ 转发失败"))

    # 再验一次 VerQueryValueW 的整条链路
    ok = False
    if size > 0:
        buf = C.create_string_buffer(size)
        fn.GetFileVersionInfoW.restype = W.BOOL
        fn.GetFileVersionInfoW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, C.c_void_p]
        fn.VerQueryValueW.restype = W.BOOL
        fn.VerQueryValueW.argtypes = [C.c_void_p, W.LPCWSTR,
                                      C.POINTER(C.c_void_p), C.POINTER(W.UINT)]
        if fn.GetFileVersionInfoW(target, 0, size, buf):
            ptr = C.c_void_p()
            ln = W.UINT()
            if fn.VerQueryValueW(buf, "\\", C.byref(ptr), C.byref(ln)):
                ok = True
                vs = C.cast(ptr, C.POINTER(W.DWORD))
                print(f"          VerQueryValueW(\"\\\") 成功, 结构长度 {ln.value}, "
                      f"签名 0x{vs[0]:08x}")
    print("整条转发链: " + ("正常 ✔" if ok else "失败 ✘"))

    k.FreeLibrary.argtypes = [C.c_void_p]
    k.FreeLibrary(h)
    try:
        os.remove(tmp)
    except OSError:
        pass
    return 0 if (not missing and size > 0 and ok) else 1


if __name__ == "__main__":
    sys.exit(main())
