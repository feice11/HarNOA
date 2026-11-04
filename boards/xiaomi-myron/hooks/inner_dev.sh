#!/bin/sh
# myron：S3 中 /dev 组装后的板级处理（私有命名空间内执行）。
[ -n "$HN_NATIVE" ] || exit 0
# 没有鸿蒙 ueventd，显示/GPU/输入节点权限在这里放开
chmod 666 "$HN_ROOT"/dev/dri/* "$HN_ROOT"/dev/dma_heap/* "$HN_ROOT"/dev/kgsl* "$HN_ROOT"/dev/input/* 2>/dev/null
# 鸿蒙 netsys 用 /dev/tun
[ -c "$HN_ROOT/dev/net/tun" ] && chmod 666 "$HN_ROOT/dev/net/tun" && ln -sf net/tun "$HN_ROOT/dev/tun"
ip link set lo up
# 亮度：powermgr 以非 root 写面板背光
chmod 666 /sys/class/backlight/panel0-backlight/brightness 2>/dev/null
exit 0
