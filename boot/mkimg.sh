#!/bin/bash
# 按板级配置生成启动镜像。只生成，不刷写。
# 用法: boot/mkimg.sh ram|rec|dual <板目录> [输出目录]
#   ram   内核 + HarNOA ramdisk 的完整 boot 镜像，供 fastboot boot
#   rec   v4、kernel_size=0 的 recovery 镜像：ramdisk 带 /system/bin/recovery 标记，
#         /system/bin/init = harnoa-init（借 boot 槽内核，Android 第一阶段 init 会直接 exec 它）
#   dual  v4、仅内核的 boot 镜像（bootloader 照常拼 init_boot，Android 用新内核开机）
# 依赖: mkbootimg.py（HN_MKBOOTIMG 指定）、cpio、lz4
set -euo pipefail
MODE=${1:?ram|rec|dual}
BOARD=$(cd "${2:?板目录}" && pwd)
OUT=$(mkdir -p "${3:-out}" && cd "${3:-out}" && pwd)
TOP=$(cd "$(dirname "$0")/.." && pwd)
. "$BOARD/board.conf"
MKBOOTIMG=${HN_MKBOOTIMG:-mkbootimg.py}
INIT_BIN=${HN_INIT_BIN:-$TOP/core/stage1/harnoa-init}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

need() { [ -e "$1" ] || { echo "缺少 $1"; exit 1; }; }

build_ramdisk() {
	local rd=$W/rd
	need "$INIT_BIN"
	mkdir -p "$rd"/{dev,proc,sys,tmp,bin,etc/harnoa,lib/modules}
	install -m 0755 "$INIT_BIN" "$rd/init"
	[ -n "${HN_BUSYBOX:-}" ] && install -m 0755 "$HN_BUSYBOX" "$rd/bin/busybox" && ln -sf busybox "$rd/bin/sh"
	# S1 配置：从 board.conf 摘出 harnoa-init 关心的键
	{
		echo "HN_PART=${HN_PART}"
		echo "HN_MNT=${HN_MNT:-/hn}"
		echo "HN_FS=${HN_FS:-ext4}"
		echo "HN_MODLIST=/etc/harnoa/modules.list"
		echo "HN_STAGE2=${HN_STAGE2:-harnoa/core/stage2/harnoa.sh}"
		echo "HN_FAILSAFE_SEC=${HN_FAILSAFE_SEC:-900}"
	} > "$rd/etc/harnoa/stage1.conf"
	# 模块：清单中的路径按 ramdisk 内 /lib/modules/<名> 改写
	: > "$rd/etc/harnoa/modules.list"
	if [ -n "${HN_MODULES_DIR:-}" ] && [ -f "$BOARD/modules.list" ]; then
		grep -v '^#' "$BOARD/modules.list" | while read -r m; do
			[ -n "$m" ] || continue
			cp "$HN_MODULES_DIR/$m" "$rd/lib/modules/" && echo "/lib/modules/$(basename "$m")"
		done >> "$rd/etc/harnoa/modules.list"
	fi
	if [ "$MODE" = rec ]; then
		mkdir -p "$rd/system/bin"
		cp -p "$rd/init" "$rd/system/bin/init"
		printf 'HarNOA recovery marker\n' > "$rd/system/bin/recovery"
	fi
	(cd "$rd" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 2>/dev/null | lz4 -l -9) > "$W/ramdisk.lz4"
}

case "$MODE" in
ram)
	need "$HN_KERNEL"; build_ramdisk
	python3 "$MKBOOTIMG" --header_version "${HN_RAM_HEADER:-2}" \
		--kernel "$HN_KERNEL" --ramdisk "$W/ramdisk.lz4" \
		${HN_DTB:+--dtb "$HN_DTB"} --cmdline "${HN_CMDLINE:-}" \
		${HN_MKBOOTIMG_ARGS:-} -o "$OUT/harnoa-ram.img" ;;
rec)
	build_ramdisk
	python3 "$MKBOOTIMG" --header_version 4 --ramdisk "$W/ramdisk.lz4" -o "$OUT/harnoa-rec.img" ;;
dual)
	need "$HN_KERNEL"
	python3 "$MKBOOTIMG" --header_version 4 --kernel "$HN_KERNEL" -o "$OUT/harnoa-dual.img" ;;
*) echo "未知模式 $MODE"; exit 2 ;;
esac
ls -l "$OUT"/harnoa-"$MODE".img
sha256sum "$OUT"/harnoa-"$MODE".img
echo "提示：rec/dual 可能需要按原分区镜像补齐 AVB footer 与分区大小，见 docs/BOOT_ENTRIES.md"
