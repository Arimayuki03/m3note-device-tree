#!/system/bin/sh
MODDIR=${0%/*}
# Keep all eight cores online; disable HPS core hotplug.
echo 0 > /proc/hps/enabled 2>/dev/null
for i in 0 1 2 3 4 5 6 7; do
  echo 1 > /sys/devices/system/cpu/cpu${i}/online 2>/dev/null
done
echo 8 8 > /proc/hps/num_limit_thermal 2>/dev/null
echo 8 8 > /proc/hps/num_limit_low_battery 2>/dev/null
# Disable MTK software thermal performance limiting; kernel emergency protection remains.
echo 3 0 > /proc/ppm/policy_status 2>/dev/null
