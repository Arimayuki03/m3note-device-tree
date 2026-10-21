#!/usr/bin/env python3
"""检查 secro / lk 中是否存放了 boot 镜像（或其内核/ramdisk）的哈希值。

判断逻辑：
  - 若 secro 或 lk 里能找到 boot 镜像（整包 / 内核段 / ramdisk）的哈希字节，
    说明引导阶段可能拿它做完整性校验 —— 改了 boot 就会校验失败。
  - 若找不到任何相关哈希，则修改 boot 后大概率仍能启动（LK 未校验该镜像）。

安全约束：只读取脚本目录下白名单内的文件，纯只读，不写入任何文件。
"""
import hashlib
import os
import struct

ALLOWED = {
    "boot": "m3note-backup/boot-orig.img",
    "lk": "m3note-backup/lk-orig.img",
    "secro": "m3note-backup/secro-orig.img",
    "frp": "m3note-backup/frp.img",
    "proinfo": "m3note-backup/proinfo.img",
    "devinfo": "m3note-backup/devinfo.img",
    # 本机没有独立的 persist 分区（fstab 中 frp 即 /persistent）。
    # 保留该键是为了让读取走 FileNotFoundError 分支后被安全跳过。
    "persist": "m3note-backup/persist.img",
}
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def safe_read(key):
    rel = ALLOWED[key]
    base_real = os.path.realpath(BASE_DIR)
    path_real = os.path.realpath(os.path.join(BASE_DIR, rel))
    if not path_real.startswith(base_real + os.sep):
        raise ValueError("路径越界")
    with open(path_real, "rb") as fh:
        return fh.read()


def find_all(hay, needle, limit=6):
    hits, start = [], 0
    while len(hits) < limit:
        i = hay.find(needle, start)
        if i < 0:
            break
        hits.append(i)
        start = i + 1
    return hits


boot = safe_read("boot")
lk = safe_read("lk")
secro = safe_read("secro")

# 拆出内核段与 ramdisk 段（与 bootimg_inspect.py 一致）
kernel_size, = struct.unpack_from("<I", boot, 0x08)
ramdisk_size, = struct.unpack_from("<I", boot, 0x10)
page = struct.unpack_from("<I", boot, 0x24)[0]
kernel = boot[page:page + kernel_size]
ram_off = page + (kernel_size + page - 1) // page * page
ramdisk = boot[ram_off:ram_off + ramdisk_size]
image_used = ram_off + ramdisk_size  # 镜像实际占用的字节数（其余为分区尾部空余）

parts = {
    "boot 分区全量(16MB)": boot,
    f"boot 镜像实占({image_used}B)": boot[:image_used],
    "kernel 段": kernel,
    "ramdisk 段": ramdisk,
}

print("=== 计算各部分的摘要 ===")
digests = {}
for label, data in parts.items():
    # 说明：这里刻意同时使用 MD5 / SHA1 / SHA256，用途是「搜索」固件中可能遗留的摘要值，
    # 以判断厂商是否把 boot 哈希固化在 secro/lk 里；并非用它们做完整性保护。
    d = {
        "sha256": hashlib.sha256(data).digest(),
        "sha1": hashlib.sha1(data).digest(),
        "md5": hashlib.md5(data).digest(),
    }
    digests[label] = d
    print(f"  {label}: sha256={d['sha256'].hex()[:32]}...")

print("\n=== 在各元数据分区中搜索这些摘要 ===")
blobs = {"lk": lk, "secro": secro}
for extra_key in ("frp", "proinfo", "devinfo", "persist"):
    try:
        blobs[extra_key] = safe_read(extra_key)
    except (ValueError, FileNotFoundError, OSError):
        continue  # 未 dump 的分区直接跳过
print(f"  参与搜索的分区: {', '.join(blobs)}")

found_any = False
for label, d in digests.items():
    for algo, val in d.items():
        for target_name, target in blobs.items():
            hits = find_all(target, val)
            if hits:
                found_any = True
                offsets = ", ".join(hex(h) for h in hits)
                print(f"  [命中] {algo}({label}) 出现在 {target_name} 的偏移: {offsets}")
if not found_any:
    print("  未找到任何 boot 相关摘要 —— 未见将 boot 哈希固化用于校验的迹象")

print("\n=== secro 结构概览 ===")
for magic in (b"AND_AC_REGION", b"SECURE_RO", b"SBC", b"AND_SECRO"):
    hits = find_all(secro, magic, limit=5)
    if hits:
        print(f"  {magic.decode(errors='replace'):<14} 出现 {len(hits)} 次，偏移: "
              + ", ".join(hex(h) for h in hits))

print("\n=== secro 前 128 字节 ===")
for i in range(0, 128, 16):
    print(f"  {i:04x}: " + " ".join(f"{b:02x}" for b in secro[i:i + 16]))
