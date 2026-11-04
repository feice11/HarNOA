#!/bin/sh
# myron：在 Android vendor 视图（$HN_AROOT）中拉起鸿蒙缺少对应驱动适配的 HAL。
# 骨架阶段只列出需要的桥，实现后续逐个加入（各自守护循环 + 日志）。
[ -n "$HN_NATIVE" ] || exit 0
# - 触摸：小米 THP，坐标由 vendor touchfeature HAL 计算后写回 input 节点
# - Wi-Fi：cnss-daemon 上报 fs_ready 后 cld 驱动才探测出 wlan0
# - 音频：鸿蒙 audio VDI ←→ 宿主 PCM 守护 ←→ AGM/ADSP；通话另需 audioadsprpcd
# - 蓝牙：vendor 蓝牙 HAL + H4 套接字桥
# - 振动：qcom-hv-haptics（input FF）适配为鸿蒙期望的 sysfs 接口
# - 基带/GNSS、相机：独立桥进程
exit 0
