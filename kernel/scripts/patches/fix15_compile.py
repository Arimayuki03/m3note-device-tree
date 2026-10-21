from pathlib import Path
p=Path('<PROJECT_ROOT>/kernel/m3note_flash_ioctl.c')
s=p.read_text().replace('#include <linux/module.h>', '#include <linux/module.h>\n#include <linux/platform_device.h>')
p.write_text(s)
k=Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
p=k/'drivers/misc/mediatek/imgsensor/src/mt6755/s5k5e8yx_mipi_raw/s5k5e8yxmipiraw_Sensor.c'
s=p.read_text().replace('static bool front_otp_awb = true;\nmodule_param(front_otp_awb, bool, 0644);','')
p.write_text(s)
