from pathlib import Path
import re
k = Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
for d in (k/'drivers/misc/mediatek/imgsensor/src/mt6755').glob('*'):
    if d.name.startswith(('ov13853', 'ov5670', 's5k5e8')):
        p = d/'Makefile'
        p.write_text(p.read_text().replace('include $(srctree)/drivers/misc/mediatek/Makefile.custom', ''))
p = k/'drivers/staging/iio/imu/inv_mpu/inv_mpu_core.c'
s = p.read_text()
s = re.sub(r'(?<!struct )\b(GSENSOR_VECTOR3D|SENSOR_DATA)\b', r'struct \1', s)
s = s.replace('#if INV_GYRO_AUTO_CALI == 1', '#if defined(INV_GYRO_AUTO_CALI) && INV_GYRO_AUTO_CALI == 1')
marker = 'extern' if False else 'static char g_sensor_info[40];'
s = s.replace(marker, '''/* Preserve the old Flyme HAL's world-writable sysfs ABI locally. */
#undef __ATTR
#define __ATTR(_name, _mode, _show, _store) { \\
    .attr = { .name = __stringify(_name), .mode = _mode }, \\
    .show = _show, .store = _store }
''' + marker, 1)
a = s.index('int inv_get_gyro_data(struct inv_mpu_state *st, short *gyr)\n{')
z = s.index('\nvoid inv_set_accel_offset_reg', a)
s = s[:a] + '''int inv_get_gyro_data(struct inv_mpu_state *st, short *gyr)
{
    u8 raw[6];
    int i, ret = inv_i2c_read(st, 0x43, sizeof(raw), raw);
    if (ret < 0)
        return ret;
    for (i = 0; i < 3; i++)
        gyr[i] = (s16)((raw[2 * i] << 8) | raw[2 * i + 1]) - st->gyro_bias[i];
    return 0;
}
''' + s[z:]
a = s.index('void inv_set_accel_offset_reg(')
z = s.index('\n}', a)
s = s[:a] + s[a:z].replace('return -EINVAL;', 'return;') + s[z:]
s = s.replace('f->f_op->read(f, &acc_gyr_calib,', 'f->f_op->read(f, (char __user *)&acc_gyr_calib,')
s = s.replace('write_block(&acc_gyr_calib,', 'write_block((char *)&acc_gyr_calib,')
s = s.replace('STORE_FILE,IS_ERR(f)', 'STORE_FILE,PTR_ERR(f)')
a = s.index('static ssize_t icm20608d_store_acc_gyro_factory_read_calibbias(')
z = s.index('\n}', a) + 2
s = s[:a] + '''static ssize_t icm20608d_store_acc_gyro_factory_read_calibbias(struct device *dev,
    struct device_attribute *attr, const char *buf, size_t count)
{
    int ret = init_factory_calibration();
    return ret < 0 ? ret : count;
}''' + s[z:]
p.write_text(s)
p = k/'drivers/staging/iio/imu/inv_mpu/Makefile'
s = p.read_text() + '\nccflags-y += -Wno-unused-variable -Wno-unused-function -Wno-declaration-after-statement\n'
p.write_text(s)
print('Applied 3.18 API and callback type adaptations')
