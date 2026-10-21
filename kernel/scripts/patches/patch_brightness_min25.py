from pathlib import Path

root = Path('<BUILD_ROOT>/k318/android_kernel_m3note-master')
path = root / 'drivers/misc/mediatek/video/common/aal20/ddp_pwm.c'
text = path.read_text()

old = '''static int disp_pwm_level_remap(disp_pwm_id_t id, int level_1024)
{
\treturn level_1024;
}
'''
new = '''/*
 * The panel is still powered while Android moves the brightness slider to
 * its lowest position.  A raw zero disables the PWM and makes the panel
 * completely black.  Keep a visible floor while the display path is on;
 * ddp_pwm_power_off() still disables the PWM for a real screen-off event.
 */
#define M3NOTE_MIN_BACKLIGHT 20

static int disp_pwm_level_remap(disp_pwm_id_t id, int level_1024)
{
\tif (level_1024 == 0 && g_pwm_is_power_on)
\t\treturn M3NOTE_MIN_BACKLIGHT;

\treturn level_1024;
}
'''
if text.count(old) != 1:
    raise SystemExit('unexpected disp_pwm_level_remap source; refusing to patch')
path.write_text(text.replace(old, new))
print('patched', path)
