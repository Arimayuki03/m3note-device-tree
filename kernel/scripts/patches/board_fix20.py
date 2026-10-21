from pathlib import Path
import shutil
root = Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
backup = Path('<BUILD_ROOT>/fix-20261015/pre20')
rel = 'drivers/staging/iio/imu/inv_mpu/inv_mpu_core.c'
p = root / rel
b = backup / rel
b.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(p,b)
s = p.read_text()
s = s.replace('/* Flyme CompassSensor uses 2 to select the external MTK magnetic-input ABI.\n * It selects no compass backend if this board-identification node is absent. */', '/* This early board has ST480 at I2C1/0x0d, identified by command 0x50/ID 0x7c.\n * Flyme type 1 selects the raw compass backend with built-in sensor fusion. */')
s = s.replace('return scnprintf(buf, PAGE_SIZE, "2\\n");', 'return scnprintf(buf, PAGE_SIZE, "1\\n");',1)
start=s.index('static ssize_t diagnostic_registers_show(')
end=s.index('static DEVICE_ATTR(diagnostic_registers, 0400, diagnostic_registers_show, NULL);',start)
end+=len('static DEVICE_ATTR(diagnostic_registers, 0400, diagnostic_registers_show, NULL);')
s=s[:start]+s[end:]
s=s.replace('device_create_file(m3note_msensor_device, &dev_attr_msensor_type) ||\n            device_create_file(m3note_msensor_device, &dev_attr_diagnostic_registers)', 'device_create_file(m3note_msensor_device, &dev_attr_msensor_type)')
needle='static int __init inv_mpu_init(void)'
assert needle in s
addition='''static struct i2c_client *m3note_compass_client;
static void m3note_register_compass(void)
{
    struct i2c_adapter *adapter = i2c_get_adapter(1);
    struct i2c_board_info info = { I2C_BOARD_INFO("st480", 0x0d) };
    if (!adapter) {
        pr_err("m3note ST480: I2C1 unavailable\\n");
        return;
    }
    m3note_compass_client = i2c_new_device(adapter, &info);
    i2c_put_adapter(adapter);
    if (!m3note_compass_client)
        pr_err("m3note ST480: cannot create I2C1/0x0d client\\n");
}

'''
s=s.replace(needle,addition+needle)
needle='\tint result = i2c_add_driver(&inv_mpu_driver);'
assert needle in s
s=s.replace(needle, needle+'\n\tm3note_register_compass();')
s=s.replace('static void __exit inv_mpu_exit(void)\n{', 'static void __exit inv_mpu_exit(void)\n{\n\tif (m3note_compass_client)\n\t\ti2c_unregister_device(m3note_compass_client);')
p.write_text(s)
p=root/'.config'
shutil.copy2(p,backup/'kernel.config')
s=p.read_text().replace('CONFIG_MTK_AKM09911_NEW=y','# CONFIG_MTK_AKM09911_NEW is not set').replace('# CONFIG_MTK_ST480 is not set','CONFIG_MTK_ST480=y')
p.write_text(s)
local=Path('<PROJECT_ROOT>/kernel')
for old,new in [('build_fix19.sh','build_fix20.sh'),('pack_fix19.py','pack_fix20.py')]:
    data=(local/old).read_text().replace('VERSION=19','VERSION=20').replace('fix19','fix20').replace('build19','build20')
    (local/new).write_text(data)
print('ST480 board client/type configured; waiting for driver port before build')
