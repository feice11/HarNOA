# S3 隔离段：在私有命名空间里组装鸿蒙根，最后 exec 鸿蒙 init。

HN_INIT_DIRS="system/etc/init vendor/etc/init sys_prod/etc/init chip_prod/etc/init preload/etc/init cust/etc/init"

# 1. 服务清单：每行 "cfg文件名 [额外 sed 表达式]"，native: 前缀仅原生启动
hn_services() {
	list=$HN_HOME/profiles/$HN_PROFILE.list
	[ -f "$HN_BOARD_DIR/services.list" ] && list="$list $HN_BOARD_DIR/services.list"
	out=$HN_WORK/cfg
	rm -rf "$out"; mkdir -p "$out"
	cat $list | while read -r f expr; do
		case "$f" in ''|'#'*) continue ;; esac
		case "$f" in native:*) [ -n "$HN_NATIVE" ] || continue; f=${f#native:} ;; esac
		for src in "$HN_BOARD_DIR/cfg/$f" $(for d in $HN_INIT_DIRS; do echo "$HN_ROOT/$d/$f"; done); do
			[ -f "$src" ] || continue
			# critical 改名而不删（避免留尾逗号）；restorecon 换成无害命令（没有 SELinux）
			sed -e 's#"critical"#"hn_no_critical"#' \
			    -e 's#"restorecon [^"]*"#"export HN_NO_RESTORECON 1"#' \
			    ${expr:+-e "$expr"} "$src" > "$out/$f"
			break
		done
		[ -f "$out/$f" ] || hn_log "找不到服务 $f"
	done
	# 未选中的 init 目录用空 tmpfs 遮住，选中的拷进 system/etc/init
	for d in $HN_INIT_DIRS; do
		[ -d "$HN_ROOT/$d" ] && mount -t tmpfs -o mode=0755,size=1m tmpfs "$HN_ROOT/$d"
	done
	cp "$out"/* "$HN_ROOT/system/etc/init/" 2>/dev/null
	[ -f "$HN_BOARD_DIR/init.cfg" ] && mount -o bind "$HN_BOARD_DIR/init.cfg" "$HN_ROOT/system/etc/init.cfg"
}

# 2. SA 隐藏：进程没启用的 SA profile 从 samgr 视野中移除，避免按需加载空等
hn_hide_profiles() {
	[ -d "$HN_ROOT/system/profile" ] || return 0
	o=$HN_WORK/profile
	rm -rf "$o"; mkdir -p "$o"; cp -a "$HN_ROOT/system/profile/." "$o/"
	grep -ho '"name" *: *"[^"]*"' "$HN_WORK"/cfg/*.cfg 2>/dev/null \
		| sed 's/.*: *"//; s/"$//' | sort -u > "$HN_WORK/enabled_procs.txt"
	for j in "$o"/*.json; do
		p=$(grep -o '"process" *: *"[^"]*"' "$j" | head -1 | sed 's/.*: *"//; s/"$//')
		[ -n "$p" ] && ! grep -qxF "$p" "$HN_WORK/enabled_procs.txt" && rm -f "$j"
	done
	mount -o bind "$o" "$HN_ROOT/system/profile"
}

# 3. 覆盖层：先整目录替换（含 .dir 标记的目录），后单文件 bind
hn_overlays() {
	od=$HN_BOARD_DIR/overlay_dir
	[ -d "$od" ] && (cd "$od" && find . -name .dir) | while read -r f; do
		mount -o bind "$od/${f%/.dir}" "$HN_ROOT/${f%/.dir}"
	done
	of=$HN_BOARD_DIR/overlay
	[ -d "$of" ] && (cd "$of" && find . -type f) | while read -r f; do
		mount -o bind "$of/$f" "$HN_ROOT/$f"
	done
}

# 4. /dev
hn_devfs() {
	r=$HN_ROOT/dev
	mount -t tmpfs -o mode=0755,size=64m tmpfs "$r"
	mknod -m 666 "$r/null" c 1 3;    mknod -m 666 "$r/zero" c 1 5
	mknod -m 666 "$r/random" c 1 8;  mknod -m 666 "$r/urandom" c 1 9
	mknod -m 600 "$r/kmsg" c 1 11;   mknod -m 666 "$r/tty" c 5 0
	mknod -m 600 "$r/console" c 5 1
	# IPC 节点按鸿蒙名字建立：/dev/hn_binder -> /dev/binder 等
	for n in binder hwbinder vndbinder; do
		minor=$(awk -v n="${HN_BINDER_PREFIX}$n" '$2 == n { print $1 }' /proc/misc)
		[ -n "$minor" ] && mknod -m 666 "$r/$n" c 10 "$minor"
	done
	for n in access_token_id ashmem; do
		minor=$(awk -v n=$n '$2 == n { print $1 }' /proc/misc)
		[ -n "$minor" ] && mknod -m 666 "$r/$n" c 10 "$minor"
	done
	mkdir -p "$r/unix/socket" "$r/socket" "$r/pts" "$r/block"
	if [ -n "$HN_NATIVE" ]; then
		# 宿主字符设备补齐；块设备一律不给，鸿蒙碰不到 Android 分区
		(cd /dev && find . -type c) | while read -r f; do
			case $f in ./ptmx|./pts/*) continue ;; esac
			[ -e "$r/$f" ] && continue
			mkdir -p "$r/${f%/*}"; cp -a "/dev/$f" "$r/$f"
		done
	fi
	mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$r/pts"
	ln -s pts/ptmx "$r/ptmx"
}

# 5. /proc /sys 及其他挂载
hn_vfs() {
	for d in mnt storage tmp log metadata; do
		mkdir -p "$HN_ROOT/$d"
		mount -t tmpfs -o mode=0755,size=64m tmpfs "$HN_ROOT/$d"
	done
	mkdir -p "$HN_ROOT/mnt/data" "$HN_ROOT/storage/media"
	chmod 0711 "$HN_ROOT/mnt/data" "$HN_ROOT/storage/media"
	mount -o bind "$HN_DATA" "$HN_ROOT/data"
	mount -t proc proc "$HN_ROOT/proc"
	echo "$(cat /proc/cmdline) ohos.boot.hardware=$HN_HARDWARE ohos.boot.selinux=permissive" > "$HN_WORK/cmdline"
	mount -o bind "$HN_WORK/cmdline" "$HN_ROOT/proc/cmdline"
	: > "$HN_WORK/sysrq"; mount -o bind "$HN_WORK/sysrq" "$HN_ROOT/proc/sysrq-trigger"
	if [ -n "$HN_NATIVE" ]; then
		mount -t sysfs sysfs "$HN_ROOT/sys"
	else
		# 寄居模式：保护宿主 Android
		mount -o bind "$HN_ROOT/proc/sys" "$HN_ROOT/proc/sys"
		mount -o remount,bind,ro "$HN_ROOT/proc/sys"
		mount -t sysfs -o ro sysfs "$HN_ROOT/sys"
	fi
}

# 6. cgroup：init 内的 mount 被垫片拦截，这里替它挂好
hn_cgroups() {
	[ -n "$HN_NATIVE" ] || return 0
	# TODO：按鸿蒙 init.cfg 期望挂 cpuset / cpuctl / freezer，板级可在 inner_dev 覆盖
	:
}

hn_inner() {
	set -e
	hn_log "inner"
	hn_services
	hn_hide_profiles
	hn_overlays
	hn_devfs
	set +e
	hn_hook inner_dev
	hn_vfs
	hn_cgroups
	hn_hook pre_exec
	hostname localhost
	echo "harnoa: exec ohos init" > /dev/kmsg
	# 垫片只对鸿蒙 musl 程序生效，环境变量在 chroot 后由鸿蒙 toybox 设置
	exec env -i $HN_BB chroot "$HN_ROOT" /system/bin/toybox env \
		PATH=/system/bin:/vendor/bin HN_FAKE_PID1=1 LD_PRELOAD=/data/.hnshim.so \
		/system/bin/init --second-stage
}
