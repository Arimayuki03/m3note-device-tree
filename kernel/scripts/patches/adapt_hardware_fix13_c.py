from pathlib import Path
import re
k=Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
p=k/'drivers/staging/iio/imu/inv_mpu/inv_mpu_ring.c'
s=p.read_text().replace('result = iio_sw_buffer_preenable(indio_dev);', '/* 3.18 IIO core computes buffer datum sizes after preenable. */\n\tresult = 0;')
p.write_text(s)
for d in (k/'drivers/misc/mediatek/imgsensor/src/mt6755').glob('*'):
    if not d.name.startswith(('ov13853','ov5670','s5k5e8')): continue
    for p in d.glob('*.c'):
        s=p.read_text()
        s=re.sub(r'(scenarioId:%llu\\n", )(?:(?:\(UINT32\))?\*feature_data)',r'\1(unsigned long long)*feature_data',s)
        s=s.replace('framerate = %d, min framelength should enable? \\n','framerate = %d, min framelength should enable? %d\\n')
        p.write_text(s)
    p=d/'Makefile'
    p.write_text(p.read_text()+'\nccflags-y += -Wno-unused-function -Wno-declaration-after-statement\n')
p=k/'drivers/misc/mediatek/imgsensor/inc/kd_imgsensor_define.h'
s=p.read_text().replace('\tSENSOR_FEATURE_MAX\n', '\t/* Legacy board sensor extensions; retain the existing 3.18 ABI above. */\n\tSENSOR_FEATURE_SET_LONGEXP_PARAM,\n\tSENSOR_FEATURE_CANCEL_LONGEXP,\n\tSENSOR_FEATURE_GET_CAP_PIXEL_CLOCK_FREQ,\n\tSENSOR_FEATURE_GET_CAP_PERIOD,\n\tSENSOR_FEATURE_GET_MAXFRAMELENGTH_MARGIN,\n\tSENSOR_FEATURE_MAX\n')
p.write_text(s)
