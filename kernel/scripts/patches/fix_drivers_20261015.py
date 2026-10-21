from pathlib import Path
root = Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
bk = Path('<BUILD_ROOT>/fix-20261015')
# Remove the speculative generic PWM match: stock DT lacks its clock bindings.
p = root/'drivers/pwm/pwm-mtk-disp.c'
s = p.read_text().replace('\t/* MT6755 device tree uses the legacy generic compatible. */\n\t{ .compatible = "mediatek,disp_pwm", .data = &mt8173_pwm_data},\n', '')
p.write_text(s)
# Store a baseline without this session's temporary flashlight changes.
p = root/'drivers/misc/mediatek/flashlight/src/mt6755/kd_flashlightlist.c'
s = p.read_text()
start = s.index('\n/*\n * The Flyme camera HAL controls')
end = s.index('/* ======================================================================== */\n#define ALLOC_DEVNO', start)
s = s[:start]+'\n'+s[end:]
start = s.index('\tret = device_create_file(flashlight_device, &dev_attr_flash1);')
end = s.index('\t/* initialize members */', start)
s = s[:start]+s[end:]
start = s.index('\tmutex_lock(&flashlight_sysfs_lock);')
end = s.index('\tdevice_destroy(flashlight_class, flashlight_devno);',start)
s = s[:start]+s[end:]
(bk/'kd_flashlightlist.before.c').write_text(s)
compat = r'''
/* Flyme legacy torch ABI. Negative values turn a channel off; 0..5 are levels. */
extern int m3note_torch_set(int channel, int level);
static int m3note_torch_level[2] = { -1, -1 };
static DEFINE_MUTEX(m3note_torch_sysfs_lock);

static ssize_t m3note_torch_show(struct device *dev,
		struct device_attribute *attr, char *buf)
{
	int channel = !strcmp(attr->attr.name, "flash2");
	return scnprintf(buf, PAGE_SIZE, "%d\n", m3note_torch_level[channel]);
}

static ssize_t m3note_torch_store(struct device *dev,
		struct device_attribute *attr, const char *buf, size_t count)
{
	int channel = !strcmp(attr->attr.name, "flash2");
	int level, ret;

	ret = kstrtoint(buf, 0, &level);
	if (ret)
		return ret;
	level = clamp(level, -1, 5);
	mutex_lock(&m3note_torch_sysfs_lock);
	ret = m3note_torch_set(channel, level);
	if (!ret)
		m3note_torch_level[channel] = level;
	mutex_unlock(&m3note_torch_sysfs_lock);
	if (ret)
		return ret;
	return count;
}

static DEVICE_ATTR(flash1, 0666, m3note_torch_show, m3note_torch_store);
static DEVICE_ATTR(flash2, 0666, m3note_torch_show, m3note_torch_store);
static struct attribute *m3note_torch_attrs[] = {
	&dev_attr_flash1.attr,
	&dev_attr_flash2.attr,
	NULL,
};
static const struct attribute_group m3note_torch_group = {
	.attrs = m3note_torch_attrs,
};
'''
s = s.replace('static struct cdev *g_pFlash_CharDrv;\n','static struct cdev *g_pFlash_CharDrv;\n'+compat)
s = s.replace('if (NULL == flashlight_device) {','if (IS_ERR(flashlight_device)) {')
s = s.replace('\t/* initialize members */', '\tret = sysfs_create_group(&flashlight_device->kobj, &m3note_torch_group);\n\tif (ret)\n\t\treturn ret;\n\n\t/* initialize members */',1)
s = s.replace('\tdevice_destroy(flashlight_class, flashlight_devno);','\tsysfs_remove_group(&flashlight_device->kobj, &m3note_torch_group);\n\tdevice_destroy(flashlight_class, flashlight_devno);',1)
p.write_text(s)
# Protocol A reports an empty frame on release, not a Protocol B tracking ID.
p = root/'drivers/input/touchscreen/mediatek/GT1151/gt1x_tpd.c'
s = p.read_text()
(bk/'gt1x_tpd.before.c').write_text(s)
start = s.index('\t/* 释放事件')
end = s.index('\tinput_report_key(tpd->dev, BTN_TOUCH, 0);', start)
s = s[:start]+'\t/* Protocol A: an empty MT frame releases all contacts. */\n'+s[end:]
anchor = '\tinput_set_abs_params(tpd->dev, ABS_MT_TRACKING_ID, 0, (GTP_MAX_TOUCH - 1), 0, 0);'
s = s.replace(anchor, anchor+'\n\tinput_set_abs_params(tpd->dev, ABS_MT_PRESSURE, 0, 255, 0, 0);',1)
p.write_text(s)
# Vendor backlight driver owns the PWM. Keep its source mux running with it.
p = root/'drivers/misc/mediatek/video/common/aal20/ddp_pwm.c'
s = p.read_text()
(bk/'ddp_pwm.before.c').write_text(s)
s = s.replace('\t\tddp_clk_enable(DISP_PWM);', '\t\tddp_clk_enable(MUX_PWM);\n\t\tddp_clk_enable(DISP_PWM);',1)
s = s.replace('\t\tddp_clk_disable(DISP_PWM);', '\t\tddp_clk_disable(DISP_PWM);\n\t\tddp_clk_disable(MUX_PWM);',1)
p.write_text(s)

