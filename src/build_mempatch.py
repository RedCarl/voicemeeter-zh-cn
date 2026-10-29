#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a "memory patch plan" for VoiceMeeter from the translation table.

It reads YOUR OWN installed VoiceMeeter executable (it is never modified),
locates each English string from translations/zh_cn.py inside the string pool,
and writes mempatch_<product>.json next to launch-cn.ps1.  The launcher then
applies that plan to the process memory at startup.

Usage
-----
    python src/build_mempatch.py                     # auto-detect product
    python src/build_mempatch.py --product potato
    python src/build_mempatch.py --product banana --install-dir "D:\\VB"
    python src/build_mempatch.py --check             # report only, write nothing

Only the Python standard library is used.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from peutil import PE, Spans, find_literal, display_width  # noqa: E402

DEFAULT_INSTALL_DIR = r"C:\Program Files (x86)\VB\Voicemeeter"

PRODUCTS = {
    # key           可执行文件                 说明
    "banana":       {"exe": "voicemeeterpro_x64.exe", "name": "VoiceMeeter Banana (64 位)",
                     "known": ["D9AC177129911A58A1388211ACE5F82F653AA8A8311D07274740262857883FA2"]},
    "banana-x86":   {"exe": "voicemeeterpro.exe",     "name": "VoiceMeeter Banana (32 位)",
                     "known": ["70F83E4381654C056A317EA59B44483ADAB453612473408E8FBF92CC9D0E1867"]},
    "potato":       {"exe": "voicemeeter8x64.exe",    "name": "VoiceMeeter Potato (64 位)",
                     "known": ["7F783F03599F704124BEDB1E13E8D8A6E91AB58FD74DC37D675F3A718ACB81EB"]},
    "potato-x86":   {"exe": "voicemeeter8.exe",       "name": "VoiceMeeter Potato (32 位)",
                     "known": ["35B040158CE4AB9F53169ABB6B7970D33F5EE138D3DD896B1D7BE55CD4C11AEB"]},
}

# 产品族：同一个界面的 64 位 / 32 位两个构建
FAMILY = {
    "banana": "banana", "banana-x86": "banana",
    "potato": "potato", "potato-x86": "potato",
}


def load_translations():
    path = os.path.join(ROOT, "translations", "zh_cn.py")
    spec = importlib.util.spec_from_file_location("zh_cn", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TRANSLATIONS, mod.MULTILINE


def detect_product(install_dir):
    # 优先 64 位构建；两者都装时由调用方用 --product 明确指定
    for key in ("potato", "potato-x86", "banana", "banana-x86"):
        if os.path.exists(os.path.join(install_dir, PRODUCTS[key]["exe"])):
            return key
    return None


def build(pe, translations, multiline, verbose=True):
    d = pe.data
    spans = Spans(d)
    items = []
    stats = {"single_ok": 0, "wide_ok": 0, "not_found": [], "too_long": [],
             "outside_rdata": 0, "width_warn": [], "already": 0}

    for en, cn in translations:
        hits = []
        for kind in ("A", "W"):
            for off in find_literal(d, en, kind):
                if not pe.in_rdata(off):
                    stats["outside_rdata"] += 1
                    continue
                hits.append((kind, off))
        if not hits:
            stats["not_found"].append(en)
            continue
        for kind, off in hits:
            blob = cn.encode("gbk" if kind == "A" else "utf-16le")
            olit = len(en.encode("latin1")) if kind == "A" else len(en) * 2
            space = spans.safe_avail(d, off, olit)
            need = len(blob) + (1 if kind == "A" else 2)
            if need > space:
                stats["too_long"].append((en, cn, need, space))
                continue
            if display_width(cn) > display_width(en):
                stats["width_warn"].append((en, cn))
            rva = pe.off2rva(off)
            if rva is None:
                continue
            items.append({
                "rva": rva,
                "bytes": (blob + (b"\x00" if kind == "A" else b"\x00\x00")).hex(),
                "orig": ((en.encode("latin1") + b"\x00") if kind == "A"
                         else (en.encode("utf-16le") + b"\x00\x00")).hex(),
                "text": cn,
                "kind": kind,
                "src": en,
            })
            stats["single_ok" if kind == "A" else "wide_ok"] += 1

    for en, lines_cn in multiline:
        src_lines = en.split("\n")
        if len(src_lines) != len(lines_cn):
            stats["not_found"].append(en[:40] + "… (行数不符)")
            continue
        raw = en.encode("latin1")
        found = []
        st = 0
        while True:
            k = d.find(raw + b"\x00", st)
            if k < 0:
                break
            if (k == 0 or d[k - 1] == 0) and pe.in_rdata(k):
                found.append(k)
            st = k + 1
        if not found:
            stats["not_found"].append(en[:40] + "…")
            continue
        for base in found:
            out = bytearray()
            bad = False
            for i, (sl, cl) in enumerate(zip(src_lines, lines_cn)):
                budget = len(sl.encode("latin1"))
                blob = cl.encode("gbk")
                if len(blob) > budget:
                    stats["too_long"].append((sl, cl, len(blob), budget))
                    bad = True
                    break
                out += blob + b" " * (budget - len(blob))
                if i < len(src_lines) - 1:
                    out += b"\n"
            if bad:
                continue
            rva = pe.off2rva(base)
            if rva is None:
                continue
            items.append({
                "rva": rva,
                "bytes": bytes(out).hex(),
                "orig": raw.hex(),
                "text": " / ".join(lines_cn),
                "kind": "ML",
                "src": en,
            })

    # 去重（同一偏移可能被多条命中）
    seen = set()
    uniq = []
    for it in items:
        key = (it["rva"], it["kind"])
        if key in seen:
            continue
        seen.add(key)
        uniq.append(it)
    uniq.sort(key=lambda x: x["rva"])
    return uniq, stats


def main():
    ap = argparse.ArgumentParser(description="为 VoiceMeeter 生成内存汉化计划")
    ap.add_argument("--product", default="auto",
                    choices=["auto"] + list(PRODUCTS.keys()))
    ap.add_argument("--install-dir", default=DEFAULT_INSTALL_DIR)
    ap.add_argument("--out", default=None)
    ap.add_argument("--check", action="store_true", help="只报告，不写文件")
    args = ap.parse_args()

    product = args.product
    if product == "auto":
        product = detect_product(args.install_dir)
        if not product:
            print(f"[X] 在 {args.install_dir} 下找不到 VoiceMeeter 主程序。")
            print("    请用 --install-dir 指定安装目录。")
            return 1
    info = PRODUCTS[product]
    exe = os.path.join(args.install_dir, info["exe"])
    if not os.path.exists(exe):
        print(f"[X] 找不到 {exe}")
        return 1

    pe = PE(exe)
    sha = hashlib.sha256(pe.data).hexdigest().upper()
    print(f"目标      : {info['name']}  ({info['exe']})")
    print(f"文件大小  : {pe.size:,} 字节")
    print(f"SHA256    : {sha}")
    if sha in info["known"]:
        print("版本      : 与已知的原版完全一致 ✔")
    else:
        print("版本      : 未在已知列表中 —— 这不一定有问题，构建时会逐条核对原文；")
        print("            若报告大量『原文不符』，说明该版本的字符串位置已变化。")

    translations, multiline = load_translations()
    print(f"翻译表    : {len(translations)} 条单行 + {len(multiline)} 组多行")

    items, stats = build(pe, translations, multiline)

    written = sum(len(i["bytes"]) // 2 for i in items)
    print()
    print(f"已定位并生成 {len(items)} 个补丁项，共 {written:,} 字节")
    print(f"  单行(ANSI) {stats['single_ok']}   单行(UTF-16) {stats['wide_ok']}   "
          f"多行消息框 {sum(1 for i in items if i['kind'] == 'ML')}")
    if stats["outside_rdata"]:
        print(f"  ⚠ 跳过 {stats['outside_rdata']} 处在 .data 段的重复字面量"
              f"（那些是被程序解析的表项，翻译会导致崩溃）")
    if stats["not_found"]:
        print(f"  ⚠ 本版本中找不到 {len(stats['not_found'])} 条原文"
              f"（可能是该版本没有这些文字，或措辞略有不同）:")
        for s in stats["not_found"][:12]:
            print(f"      {s!r}")
        if len(stats["not_found"]) > 12:
            print(f"      … 其余 {len(stats['not_found']) - 12} 条略")
    if stats["too_long"]:
        print(f"  ⚠ 放不下 {len(stats['too_long'])} 条（译文比原文可用空间长）:")
        for en, cn, need, space in stats["too_long"][:10]:
            print(f"      {en!r} -> {cn!r}  需要 {need} 字节, 可用 {space}")
    if stats["width_warn"]:
        print(f"  ⚠ 显示宽度可能超出控件 {len(stats['width_warn'])} 条"
              f"（汉字比拉丁字母宽，菜单/提示类不影响，固定宽度标签可能被裁剪）:")
        for en, cn in stats["width_warn"][:10]:
            print(f"      {en!r} -> {cn!r}")

    if args.check:
        print("\n(--check 模式，未写文件)")
        return 0

    out = args.out or os.path.join(ROOT, f"mempatch_{product}.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({
            "generated_by": "voicemeeter-zh-cn/src/build_mempatch.py",
            "product": product,
            "target_exe": info["exe"],
            "sha256_original": sha,
            "count": len(items),
            "items": items,
        }, f, ensure_ascii=False, indent=1)
    print(f"\n已写出 {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
