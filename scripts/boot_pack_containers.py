#!/usr/bin/env python3
"""用自编内核（Image.gz-containers）重打包当前固件（Flyme 8.0.0.0A + Magisk 16.3）的 boot 镜像。
早期备份的 boot-magisk.img 可能来自 Flyme 7.8.6.25；以实际基线镜像为准。
纯只读 + 输出到 stdout（由 shell 重定向落盘），脚本自身不打开任何写入路径。

与 boot_pack.py 的区别：基线不再是旧固件 boot-orig.img，而是从设备 dump 出的
当前 boot 分区（boot-magisk.img）——因此 ramdisk 沿用 Magisk 补丁版，
刷完直接保留 root，无需再刷 magisk.zip。

打包原则（与 boot_pack.py 相同的保守策略）：
  * 除 kernel_size 字段与内核段外，header 其余字段逐字节沿用基线
  * 内核段 = Image.gz-containers + 原机 DTB（与基线内核段内嵌 DTB 逐字节比对）
  * ramdisk 段逐字节沿用基线的 Magisk 补丁版 ramdisk，只是整体前移
    （新内核更小 → ramdisk 存放位置随页对齐变化）
  * 新映像结束之后的全部字节补零

自检（任一失败即不产出镜像）：
  ① 基线镜像尺寸必须等于 boot 分区 16 MiB，且 header 魔数为 ANDROID!
  ② 新内核段以 gzip 魔数开头、gzip CRC 可完整解压、内嵌 DTB 与基线 DTB 一致
  ③ ramdisk 段 gzip CRC 可解压且解压产物含 magisk 字样
  ④ 差异审计：header 除 kernel_size 外不得变化，补零区两镜像必须同为全零
  ⑤ 新镜像 header 的页大小与各段地址字段与基线完全一致

用法：python3 boot_pack_containers.py > m3note-backup/boot-containers.img
      （报告打到 stderr；自检失败时 stdout 无任何输出）

安全约束：只读脚本所在目录下的白名单文件；不接受任何命令行参数。
"""
import hashlib
import os
import struct
import sys
import zlib

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ALLOWED_INPUTS = (
    "m3note-backup/boot-magisk.img",
    "kernel/kernel-new-payload.bin",
    "kernel/ramdisk-current.bin",
)
F_BASE, F_KERNEL, F_RAMDISK = ALLOWED_INPUTS
PART_SIZE = 16 * 1024 * 1024


def die(msg):
    print(f"自检失败: {msg}", file=sys.stderr)
    sys.exit(1)


def safe_read(rel_name):
    """只读白名单文件；规范化后必须仍位于脚本所在目录内。"""
    if rel_name not in ALLOWED_INPUTS:
        raise ValueError(f"不在白名单内: {rel_name}")
    base_real = os.path.realpath(BASE_DIR)
    path_real = os.path.realpath(os.path.join(BASE_DIR, rel_name))
    if not path_real.startswith(base_real + os.sep):
        raise ValueError("路径越界")
    if os.path.basename(path_real) != os.path.basename(rel_name):
        raise ValueError("文件名异常")
    with open(path_real, "rb") as fh:
        return fh.read()


def pad(n, page):
    return (n + page - 1) // page * page


base = safe_read(F_BASE)
payload = safe_read(F_KERNEL)
ramdisk = safe_read(F_RAMDISK)

# ---- ① 基线格式 ----
if len(base) != PART_SIZE:
    die(f"基线镜像尺寸 {len(base)} != {PART_SIZE}")
if base[:8] != b"ANDROID!":
    die("基线不是 Android boot 镜像")

page = struct.unpack_from("<I", base, 0x24)[0]
if page != 2048:
    die(f"页大小 {page} != 2048")
ks_old, rs_old = struct.unpack_from("<I", base, 8)[0], struct.unpack_from("<I", base, 16)[0]
old_ram_off = page + pad(ks_old, page)
old_end = old_ram_off + pad(rs_old, page)

if base[old_ram_off:old_ram_off + rs_old] != ramdisk:
    die("基线中的 ramdisk 段与 ramdisk-current.bin 不一致（dump 过期？）")

# ---- ② 新内核段 ----
if payload[:2] != b"\x1f\x8b":
    die("新内核段不以 gzip 魔数开头")
ks_new = len(payload)
dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
image = dec.decompress(payload) + dec.flush()
tail_dtb = dec.unused_data
if not image:
    die("新内核 gzip 流为空")
old_kernel = base[page:page + ks_old]
fi = old_kernel.rfind(b"\xd0\x0d\xfe\xed")
if fi < 0:
    die("基线内核段内未找到 DTB 魔数")
if tail_dtb != old_kernel[fi:]:
    die("新内核段的内嵌 DTB 与基线 DTB 不一致")
if payload == old_kernel:
    die("新内核段与基线内核段相同（未换内核？）")

# ---- ③ ramdisk ----
raw_ram = zlib.decompress(ramdisk, 16 + zlib.MAX_WBITS)
if raw_ram[:6] not in (b"070701", b"070702"):
    die("ramdisk 解压产物不是 newc cpio")
if b"magisk" not in raw_ram:
    die("ramdisk 内未找到 magisk（root 会丢）")

# ---- 组装新镜像 ----
new_ram_off = page + pad(ks_new, page)
new_end = new_ram_off + pad(rs_old, page)
if new_end > PART_SIZE:
    die(f"新映像 ({new_end}) 超出分区大小")

hdr = bytearray(base[:page])
struct.pack_into("<I", hdr, 8, ks_new)          # 唯一改动的 header 字段
new = bytes(hdr) + payload + b"\0" * (new_ram_off - page - ks_new) \
    + ramdisk + b"\0" * (PART_SIZE - new_ram_off - rs_old)

# ---- ④ 差异审计 ----
if len(new) != PART_SIZE:
    die("新镜像尺寸异常")
if new[:8] != base[:8] or new[12:page] != base[12:page]:
    die("header 除 kernel_size 外发生变化")
if new[8:12] != struct.pack("<I", ks_new):
    die("kernel_size 字段写入失败")
if base[old_end:] != b"\0" * (PART_SIZE - old_end):
    die("基线映像尾部有非零数据（缩小映像会丢东西）")
if new[new_end:] != b"\0" * (PART_SIZE - new_end):
    die("新映像尾部未补零")
if new[page:page + len(payload)] != payload:
    die("内核段写入失败")
if new[new_ram_off:new_ram_off + rs_old] != ramdisk:
    die("ramdisk 段写入失败")

# ---- ⑤ header 地址字段 ----
for off, name in ((0x0C, "kernel_addr"), (0x14, "ramdisk_addr"), (0x18, "second_size"),
                  (0x1C, "second_addr"), (0x20, "tags_addr"), (0x24, "page_size")):
    if new[off:off + 4] != base[off:off + 4]:
        die(f"{name} 与基线不一致")

print("=== 重打包自检全部通过 ===", file=sys.stderr)
print(f"基线  {F_BASE}  sha256={hashlib.sha256(base).hexdigest()[:16]}…  kernel={ks_old} ramdisk={rs_old}", file=sys.stderr)
print(f"新镜像 sha256={hashlib.sha256(new).hexdigest()}", file=sys.stderr)
print(f"        kernel={ks_new} ramdisk={rs_old}(原样) 映像结束={hex(new_end)}", file=sys.stderr)
print(f"        gzip 流止于 {len(payload) - len(tail_dtb)}，内嵌 DTB {len(tail_dtb)} 字节（与基线一致）", file=sys.stderr)
print("\n刷入提示：先在 TWRP 里把 boot-magisk.img 留作回滚，再 dd 本镜像到 boot 分区。", file=sys.stderr)

sys.stdout.buffer.write(new)
