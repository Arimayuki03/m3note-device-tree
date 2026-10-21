#!/usr/bin/env python3
"""分析 MTK seccfg 分区结构，并检验其中的哈希是否是可自行伪造的无密钥 SHA-256。

安全约束：本脚本不读取命令行传入的任意路径（避免路径穿越），
只处理「与脚本同目录下」的白名单文件名。

背景：魅蓝 note3 的 LK 中存在 seccfg 结构（magic "MMMM"，
字段后跟 "EEEE" + 32 字节哈希）。若该哈希为纯 SHA-256（无密钥），
则理论上可自行修改 lock_state 字段并重算哈希。
"""
import hashlib
import os
import struct

ALLOWED_FILES = ("m3note-backup/seccfg.img",)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def load(name):
    """只允许读取白名单内的相对路径，且解析后必须仍在脚本所在目录内。"""
    if name not in ALLOWED_FILES:
        raise ValueError(f"不在白名单内: {name}")
    base_real = os.path.realpath(BASE_DIR)
    path_real = os.path.realpath(os.path.join(BASE_DIR, name))
    if not path_real.startswith(base_real + os.sep):
        raise ValueError("路径越界")
    with open(path_real, "rb") as fh:
        return fh.read(0x40)


data = load("m3note-backup/seccfg.img")

print("=" * 62)
print(f"seccfg.img 前 64 字节:")
for i in range(0, 64, 16):
    print(f"  {i:04x}: " + " ".join(f"{b:02x}" for b in data[i:i + 16]))

print()
print("按 7 个 32 位小端字解析字段：")
for i, v in enumerate(struct.unpack("<7I", data[:28])):
    raw = v.to_bytes(4, "little")
    ascii_repr = "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in raw)
    print(f"  off 0x{i * 4:02x} = 0x{v:08x} ({v})   ascii=\"{ascii_repr}\"")

stored = data[28:60]
print()
print(f"存储的哈希 (off 0x1c, 32B): {stored.hex()}")

print()
print("候选哈希比对：")
candidates = {
    "sha256(data[0:28])": hashlib.sha256(data[0:28]).digest(),
    "sha256(data[0:24])": hashlib.sha256(data[0:24]).digest(),
    "sha256(data[0:24]+EEEE)": hashlib.sha256(data[0:24] + b"EEEE").digest(),
    "sha256(data[0:28]+EEEE)": hashlib.sha256(data[0:28] + b"EEEE").digest(),
    "sha256(data[0:28]+zeros32)": hashlib.sha256(data[0:28] + b"\0" * 32).digest(),
}
hit = False
for label, digest in candidates.items():
    ok = digest == stored
    hit = hit or ok
    print(f"  {'[匹配] ' if ok else '        '}{label}: {digest.hex()[:32]}...")

print()
if hit:
    print(">>> 结论：哈希可自行重算 —— seccfg 字段（含 lock_state）可被伪造修改。")
else:
    print(">>> 结论：无密钥候选均不匹配，seccfg 可能使用硬编码密钥或设备唯一密钥。")
