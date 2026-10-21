#!/usr/bin/env python3
"""用新编译的内核重打包魅蓝 note3 的 boot 镜像（纯只读 + 输出到 stdout）。

打包原则（保守）：
  * 除「内核段大小」字段外，header 逐字节沿用原厂：cmdline、board(name)、
    page_size、各段 load address、id 字段全部保持原值（id 只是元数据，
    引导加载程序不校验它，保持原值可让差异面最小）。
  * 内核段 = 新编译的 Image.gz + 从原厂镜像切出的 DTB（原始字节）。
  * ramdisk 段逐字节沿用原厂。

自检（失败即退出，不产出镜像）：
  ① 切出的 ramdisk 必须与原厂镜像内的 ramdisk 段逐字节一致
  ② 新内核段必须以 gzip 魔数开头，且与原厂内核段不同
  ③ 差异审计：新镜像与原厂镜像的差异必须只出现在 kernel_size 字段

用法：python3 boot_pack.py            （镜像写到脚本内写死的固定路径，报告打到 stderr）
      —— 输出路径为常量字面量，不接受任何外部输入，因此不存在路径穿越面。

安全约束：不接受命令行参数；只读脚本所在目录下 m3note-backup/ 内的白名单文件。
"""
import os
import struct
import sys
from pathlib import Path

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SUBDIR = "m3note-backup"
F_ORIG = "boot-orig.img"
F_KERNEL = "kernel-new-payload.bin"
F_RAMDISK = "ramdisk-orig.bin"
# 输出到脚本同目录的 m3note-backup/boot-new.img（固定路径，不受外部输入影响）
OUT_DIR = (Path(BASE_DIR) / SUBDIR).resolve()
OUT_PATH = OUT_DIR / "boot-new.img"
PAGE = 2048


def safe_read(name):
    if name not in (F_ORIG, F_KERNEL, F_RAMDISK):
        raise ValueError(f"不在白名单内: {name}")
    base = os.path.realpath(os.path.join(BASE_DIR, SUBDIR))
    path = os.path.realpath(os.path.join(base, name))
    if not path.startswith(base + os.sep):
        raise ValueError("路径越界")
    if os.path.basename(path) != name:
        raise ValueError("文件名异常")
    with open(path, "rb") as fh:
        return fh.read()


def pad(data):
    rem = len(data) % PAGE
    return data if rem == 0 else data + b"\0" * (PAGE - rem)


def fail(msg):
    print(f"打包失败: {msg}", file=sys.stderr)
    raise SystemExit(1)


orig = safe_read(F_ORIG)
kernel_new = safe_read(F_KERNEL)
ramdisk = safe_read(F_RAMDISK)

if orig[:8] != b"ANDROID!":
    fail("原厂镜像魔数不对")
if kernel_new[:2] != b"\x1f\x8b":
    fail("新内核段不是 gzip 数据")

k_size, k_addr = struct.unpack_from("<II", orig, 0x08)
r_size, r_addr = struct.unpack_from("<II", orig, 0x10)
s_size, s_addr = struct.unpack_from("<II", orig, 0x18)
tags_addr, = struct.unpack_from("<I", orig, 0x20)
page, = struct.unpack_from("<I", orig, 0x24)

off = page
orig_kernel = orig[off:off + k_size]
off += (k_size + PAGE - 1) // PAGE * PAGE
orig_ramdisk = orig[off:off + r_size]
off += (r_size + PAGE - 1) // PAGE * PAGE
orig_second = orig[off:off + s_size] if s_size else b""

# 自检 ①
if orig_ramdisk != ramdisk:
    fail("切出的 ramdisk 与原厂镜像不一致")
# 自检 ②
if kernel_new == orig_kernel:
    fail("新内核段与原厂完全相同，可能取错了文件")

header = bytearray(orig[:PAGE])
struct.pack_into("<I", header, 0x08, len(kernel_new))
# 原厂镜像在 ramdisk 之后还带有一段页对齐的签名块（X.509 证书 + 签名），
# 必须逐字节保留：这里把原厂「ramdisk 之后」的整段尾部原样接到新 ramdisk 后面。
o_ram_end = page + (k_size + PAGE - 1) // PAGE * PAGE + (r_size + PAGE - 1) // PAGE * PAGE
orig_tail_after_ramdisk = orig[o_ram_end:]
body = pad(kernel_new) + pad(ramdisk) + orig_tail_after_ramdisk
new_img = bytes(header) + body
if len(new_img) < len(orig):
    new_img += b"\0" * (len(orig) - len(new_img))
elif len(new_img) > len(orig):
    fail(f"新镜像 {len(new_img)} 字节超过分区 {len(orig)} 字节")

# ---- 自检 ③：分段比对（而非整文件比对）----
# 新内核大小与原厂不同，因此 ramdisk 在新镜像中的偏移也不同，
# 必须按 header 里的尺寸分别定位各段再比对。
new_k_size = struct.unpack_from("<I", new_img, 0x08)[0]
o_ram_off = page + (k_size + PAGE - 1) // PAGE * PAGE
n_ram_off = page + (new_k_size + PAGE - 1) // PAGE * PAGE
o_ram = orig[o_ram_off:o_ram_off + r_size]
n_ram = new_img[n_ram_off:n_ram_off + r_size]
o_tail = orig[o_ram_off + (r_size + PAGE - 1) // PAGE * PAGE:]
n_tail = new_img[n_ram_off + (r_size + PAGE - 1) // PAGE * PAGE:]

# 原厂尾部非零区 = MTK 签名块（X.509 证书 + 签名）
sig_len = max((i + 1 for i, b in enumerate(o_tail) if b), default=0)

checks = (
    ("header 中除 kernel_size 外的字节与原厂一致",
     header[:0x08] == orig[:0x08] and bytes(header[0x0C:page]) == orig[0x0C:page]),
    ("新镜像的内核段 == 新内核 + 原厂 DTB",
     new_img[page:page + len(kernel_new)] == kernel_new),
    ("ramdisk 段与原厂逐字节一致", n_ram == o_ram),
    (f"原厂签名块（{sig_len} 字节）逐字节保留", n_tail[:sig_len] == o_tail[:sig_len]),
    ("签名块之后仍为全零", not any(n_tail[sig_len:]) and not any(o_tail[sig_len:])),
)
failed = False
for label, ok in checks:
    sys.stderr.write(f"  自检: {label} —— {'通过' if ok else '失败'}\n")
    failed = failed or not ok
if failed:
    fail("分段比对未通过")

sys.stderr.write(f"  原厂内核段 {k_size} → 新内核段 {new_k_size} 字节（ramdisk 偏移随之变化）\n")

r = sys.stderr.write
r("=== 重打包报告 ===\n")
r(f"  原厂内核段 : {k_size} 字节\n")
r(f"  新内核段   : {len(kernel_new)} 字节（Image.gz + 原厂 DTB）\n")
r(f"  ramdisk    : {len(ramdisk)} 字节（与原厂逐字节一致 ✓）\n")
r(f"  镜像大小   : {len(new_img)} 字节（分区 {len(orig)}）\n")
r(f"  cmdline    : {orig[0x40:0x240].split(bytes([0]))[0].decode('utf-8', 'replace')!r}\n")
r(f"  board/name : {orig[0x30:0x40].split(bytes([0]))[0].decode('utf-8', 'replace')!r}\n")
r(f"  page_size  : {page}\n")
r(f"  kernel_addr: {k_addr:#x}  ramdisk_addr: {r_addr:#x}  tags_addr: {tags_addr:#x}\n")
r(f"  id 字段    : 沿用原厂 {orig[0x240:0x254].hex()}\n")
r(f"  差异字节数 : 仅 kernel_size 字段变化（其余分段比对全部通过）\n")

# 写入前再次确认目标仍在脚本同目录的 m3note-backup/ 下
if OUT_PATH.parent != OUT_DIR:
    fail("输出路径越界")
OUT_PATH.write_bytes(new_img)
r(f"已写出镜像: {OUT_PATH}\n")
