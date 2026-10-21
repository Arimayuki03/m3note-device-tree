from pathlib import Path
k=Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
p=k/'drivers/misc/mediatek/imgsensor/src/mt6755/m3note_camera_eeprom.c'
p.write_text(p.read_text().replace('\tu32 offset = addr ;',''))
p=k/'drivers/misc/mediatek/imgsensor/src/mt6755/s5k5e8yx_mipi_raw/s5k5e8yxmipiraw_Sensor.c'
s=p.read_text().replace('static void set_shutter(kal_uint16 shutter)', 'static void set_shutter(kal_uint32 shutter)')
s=s.replace('set_shutter((UINT16)*feature_data);','set_shutter((UINT32)*feature_data);')
s=s.replace('Read sensor id fail, id: 0x%x\\n','Read sensor id fail, write id: 0x%x, id: 0x%x\\n')
s=s.replace('current fps :%d\\n", *feature_data','current fps :%llu\\n", (unsigned long long)*feature_data')
p.write_text(s)
