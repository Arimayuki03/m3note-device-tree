#!/usr/bin/env python3
"""解析魅蓝 note3 的原厂 boot 镜像（纯只读，不写入任何文件）。

目的：
  1. 打印 Android boot image header 的全部字段（重打包时必须一字不差复用）
  2. 判断内核压缩格式、是否含追加 DTB（FDT）
  3. 从解压后的内核里提取 "Linux version / gcc version"（决定用哪代交叉编译器）
  4. 打印各段的 SHA-256（供重打包后做字节级比对）

安全约束：只读取脚本所在目录下白名单内的文件，不接受任何外部路径参数。
"""
import hashlib
import os
import struct
import zlib

ALLOWED_INPUTS = ("m3note-backup/boot-orig.img",)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def safe_read(rel_name):
    """只读白名单文件；规范化后必须仍位于脚本所在目录内。"""
    if rel_name not in ALLOWED_INPUTS:
        raise ValueError(f"不在白名单内: {rel_name}")
    base_real = os.path.realpath(BASE_DIR)
    path_real = os.path.realpath(os.path.join(BASE_DIR, rel_name))
    if not path_real.startswith(base_real + os.sep):
        raise ValueError("路径越界")
    with open(path_real, "rb") as fh:
        return fh.read()


def padded(size, page):
    return (size + page - 1) // page * page


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def find_all(hay, needle, limit=8):
    hits, start = [], 0
    while len(hits) < limit:
        i = hay.find(needle, start)
        if i < 0:
            break
        hits.append(i)
        start = i + 1
    return hits


img = safe_read("m3note-backup/boot-orig.img")
print(f"镜像总长: {len(img)} 字节 ({len(img) / 1024 / 1024:.2f} MB)")
if img[:8] != b"ANDROID!":
    raise SystemExit(f"不是标准 Android boot 镜像，前 8 字节: {img[:8]!r}")
print("魔数: ANDROID! （标准格式，非 MTK 私有封装）\n")

kernel_size, kernel_addr = struct.unpack_from("<II", img, 0x08)
ramdisk_size, ramdisk_addr = struct.unpack_from("<II", img, 0x10)
second_size, second_addr = struct.unpack_from("<II", img, 0x18)
tags_addr, = struct.unpack_from("<I", img, 0x20)
page_size, = struct.unpack_from("<I", img, 0x24)
board_name = img[0x30:0x40].split(b"\0")[0].decode("utf-8", "replace")
cmdline = img[0x40:0x40 + 512].split(b"\0")[0].decode("utf-8", "replace")
img_id = img[0x240:0x248]
extra_cmdline = img[0x248:0x248 + 1024].split(b"\0")[0].decode("utf-8", "replace")

print("=== header 字段（重打包必须完全一致）===")
print(f"  kernel_addr  = {kernel_addr:#010x}   kernel_size  = {kernel_size} bytes")
print(f"  ramdisk_addr = {ramdisk_addr:#010x}   ramdisk_size = {ramdisk_size} bytes")
print(f"  second_addr  = {second_addr:#010x}   second_size  = {second_size} bytes")
print(f"  tags_addr    = {tags_addr:#010x}")
print(f"  page_size    = {page_size}")
print(f"  board/name   = {board_name!r}")
print(f"  cmdline      = {cmdline!r}")
print(f"  extra_cmdline= {extra_cmdline!r}")
print(f"  id(sha1)     = {img_id.hex()}")

base = kernel_addr & 0xFFFF0000
print("\n=== 推导出的 mkbootimg 参数 ===")
print(f"  --base {base:#x} --kernel_offset {kernel_addr - base:#x} "
      f"--ramdisk_offset {ramdisk_addr - base:#x} "
      f"--tags_offset {tags_addr - base:#x} --pagesize {page_size}")

off = page_size
kernel = img[off:off + kernel_size]
off += padded(kernel_size, page_size)
ramdisk = img[off:off + ramdisk_size]
off += padded(ramdisk_size, page_size)
second = img[off:off + second_size] if second_size else b""

print("\n=== 各段位置与校验值 ===")
print(f"  kernel  偏移 {page_size}  大小 {len(kernel)}  sha256={sha256(kernel)}")
print(f"  ramdisk 偏移 {padded(kernel_size, page_size) + page_size}  大小 {len(ramdisk)}  sha256={sha256(ramdisk)}")
print(f"  second  {'sha256=' + sha256(second) if second else '（无）'}")

MAGICS = {
    b"\x1f\x8b": "gzip",
    b"\x02\x21\x4c\x18": "lz4",
    b"\xfd7zXZ\x00": "xz",
    b"\x28\xb5\x2f\xfd": "zstd",
    b"BZh": "bzip2",
}
fmt = next((v for k, v in MAGICS.items() if kernel.startswith(k)), None)
if fmt is None and kernel[56:60] == b"ARM\x64":
    fmt = "未压缩的 ARM64 Image"
print(f"\n内核压缩格式: {fmt or '未知'}（内核段前 16 字节: {kernel[:16].hex()}）")

fdt_in_kernel = find_all(kernel, b"\xd0\x0d\xfe\xed")
fdt_in_image = find_all(img, b"\xd0\x0d\xfe\xed")
print(f"内核段内 FDT 魔数位置: {fdt_in_kernel or '未找到'}")
print(f"整镜像内 FDT 魔数位置: {fdt_in_image or '未找到'}")

tail_start = off
tail = img[tail_start:]

print("\n=== ramdisk 之后的尾部（原厂可能附有签名/校验块）===")
print(f"  尾部起始偏移: {tail_start}，长度: {len(tail)} 字节")
nz = [i for i, b in enumerate(tail) if b]
if nz:
    print(f"  非零字节: {len(nz)} 个；首个 {tail_start + nz[0]}，末个 {tail_start + nz[-1]}")
    print(f"  连续非零区域长度: {nz[-1] - nz[0] + 1} 字节")
    print(f"  该区域开头 48 字节: {tail[nz[0]:nz[0] + 48].hex()}")
    print(f"  该区域是否页对齐起始: {'是' if (tail_start + nz[0]) % page_size == 0 else '否'}")
else:
    print("  尾部全为零")

if fmt == "gzip":
    try:
        dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
        unpacked = dec.decompress(kernel) + dec.flush()
        dtb_tail = dec.unused_data
        print(f"\ngzip 解压成功: {len(kernel)} -> {len(unpacked)} 字节")
        print(f"  gzip 流止于第 {len(kernel) - len(dtb_tail)} 字节，其后 {len(dtb_tail)} 字节为追加的 DTB")
        for needle in (b"Linux version", b"gcc version", b"clang version"):
            for pos in find_all(unpacked, needle, limit=2):
                text = unpacked[pos:pos + 200].split(b"\0")[0].decode("utf-8", "replace")
                print(f"  [{needle.decode()}] {text}")
    except Exception as exc:  # noqa: BLE001
        print(f"\ngzip 解压失败: {exc}")
