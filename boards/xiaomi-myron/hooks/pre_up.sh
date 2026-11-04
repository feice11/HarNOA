#!/bin/sh
# myron：S2 开头的平台准备。
[ -n "$HN_NATIVE" ] || exit 0
. "$HN_BOARD_DIR/board.conf"

# 没有 ueventd：固件由内核直接从合并目录读取，否则 GPU sqe/gmu/zap 加载失败
[ -d "$HN_FW" ] && echo -n "$HN_FW" > /sys/module/firmware_class/parameters/path

# 内核默认 performance 会一直满频发热，换成 walt（没有则 schedutil）
for p in /sys/devices/system/cpu/cpufreq/policy*; do
	echo walt > "$p/scaling_governor" 2>/dev/null || echo schedutil > "$p/scaling_governor"
done

# ADSP（音频本体）与 CDSP（AGM 注册 PD 通知依赖）：设为崩溃自恢复并确保运行，后台进行
(for n in adsp cdsp; do
	for r in /sys/class/remoteproc/remoteproc*; do
		case "$(cat "$r/name" 2>/dev/null)" in *remoteproc-$n)
			echo enabled > "$r/recovery"
			case "$(cat "$r/state")" in running|attached) ;; *) echo start > "$r/state" ;; esac ;;
		esac
	done
done) &

# TODO：rec 入口下清除 misc 中残留的 boot-recovery（仅这一条，写前备份、写后校验）
# TODO：原厂 post_boot 等价调优（DDR/LLCC 调频、CPU 空闲、core_ctl）
exit 0
