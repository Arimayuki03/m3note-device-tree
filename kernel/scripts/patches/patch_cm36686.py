from pathlib import Path

p = Path('<BUILD_ROOT>/k318/android_kernel_m3note-master/drivers/misc/mediatek/alsps/cm36686-new/cm36686.c')
s = p.read_text()
old = '''\thw = get_alsps_dts_func(name, hw);
\tif (!hw) {
\t\tAPS_ERR("get_alsps_dts_func fail\\n");
\t\treturn 0;
\t}
'''
new = '''\thw = get_alsps_dts_func(name, hw);
\t/* This M3 Note DT labels the physical CM36686 node as
\t * mediatek,alsps. Accept that legacy label as a fallback;
\t * otherwise the driver exits before registering its I2C driver. */
\tif (!hw)
\t\thw = get_alsps_dts_func("mediatek,alsps", hw);
\tif (!hw) {
\t\tAPS_ERR("get_alsps_dts_func fail\\n");
\t\treturn 0;
\t}
'''
if old not in s:
    raise SystemExit('target block not found')
p.write_text(s.replace(old, new, 1))
print(p)
