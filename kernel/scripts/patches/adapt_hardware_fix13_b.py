from pathlib import Path
import re
k=Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
p=k/'drivers/staging/iio/imu/inv_mpu/inv_mpu_core.c'
s=p.read_text().replace('#if INV_GYRO_AUTO_CALI==1', '#if defined(INV_GYRO_AUTO_CALI) && INV_GYRO_AUTO_CALI==1')
p.write_text(s)
for d in (k/'drivers/misc/mediatek/imgsensor/src/mt6755').glob('*'):
    if not d.name.startswith(('ov13853','ov5670','s5k5e8')): continue
    for p in d.glob('*.c'):
        s=p.read_text()
        s=re.sub(r'(static\s+(?:void|int|kal_uint32|kal_uint16|kal_uint8)\s+\w+)\(\)', r'\1(void)', s)
        s=s.replace('scenarioId:%d', 'scenarioId:%llu')
        p.write_text(s)
    p=d/'Makefile'
    p.write_text(p.read_text()+'\nccflags-y += -Wno-unused-variable\n')
