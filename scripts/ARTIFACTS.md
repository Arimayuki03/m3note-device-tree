# 本地镜像与分区转储

`bootimg_inspect.py`、`boot_pack.py`、`boot_pack_containers.py`、`secro_hashcheck.py`
和 `seccfg_check.py` 会读取脚本同目录下的 `m3note-backup/`。这些文件**不随仓库发布**，
需要从你自己的设备读取：

```text
scripts/m3note-backup/
├── boot-orig.img            # 原厂 boot 分区 dump
├── boot-magisk.img          # 当前/回滚用 boot（Magisk 补丁版）
├── kernel-new-payload.bin   # 新内核段（Image.gz + 原厂 DTB）
├── ramdisk-orig.bin         # 原厂 ramdisk 段
├── lk-orig.img              # 原厂 lk（只读分析）
├── secro-orig.img
├── frp.img
├── proinfo.img              # 含设备唯一标识，切勿公开
├── devinfo.img              # 含设备唯一标识，切勿公开
├── persist.img              # 含设备校准/唯一标识，切勿公开
└── seccfg.img
```

读取示例（需要 root / TWRP）：

```sh
adb shell "su -c 'dd if=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot of=/data/local/tmp/boot-orig.img bs=4096'"
adb pull /data/local/tmp/boot-orig.img scripts/m3note-backup/boot-orig.img
```

> `proinfo`、`devinfo`、`persist`、`secro`、`frp` 等分区可能包含 IMEI、序列号、
> 校准数据和锁状态。不要提交到公开仓库；`scripts/` 下的工具只应在本机使用。
