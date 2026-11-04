# 公共函数与板级配置加载。被 harnoa.sh source。

# 运行环境：原生（harnoa-init 为 PID1）或寄居（Android root 下调试，镜像已挂好）
# harnoa-init 启动后写 /tmp/harnoa.native（rec 入口下 PID1 名字是 init，不能靠 comm 判断）
if [ -f /tmp/harnoa.native ]; then
	HN_NATIVE=1
else
	HN_NATIVE=
fi

hn_log() { echo "[harnoa $(cut -d' ' -f1 /proc/uptime)] $*"; }
hn_die() { hn_log "错误: $*"; exit 1; }
hn_ismnt() { grep -q " $1 " /proc/mounts; }

hn_load_board() {
	# 部署布局：$HN_HOME/core/stage2/harnoa.sh，$HN_HOME/board -> boards/<板>
	HN_HOME=${HN_HOME:-$(cd "$HN_CORE/../.." && pwd)}
	HN_BOARD_DIR=${HN_BOARD_DIR:-$HN_HOME/board}
	[ -f "$HN_BOARD_DIR/board.conf" ] || hn_die "缺少 $HN_BOARD_DIR/board.conf"
	. "$HN_BOARD_DIR/board.conf"

	# 默认值（board.conf 未设置时）
	: "${HN_MNT:=/hn}"
	: "${HN_ROOT:=$HN_MNT/root}"
	: "${HN_IMG:=$HN_MNT/img}"
	: "${HN_DATA:=$HN_MNT/data}"
	: "${HN_AROOT:=}"
	: "${HN_IMAGES:=vendor sys_prod chip_prod}"
	: "${HN_IPC_KO:=$HN_MNT/ipc/hn_ipc.ko}"
	: "${HN_BINDER_PREFIX:=hn_}"
	: "${HN_PROFILE:=minimal}"
	: "${HN_HARDWARE:=generic}"
	: "${HN_BB:=busybox}"
	HN_LOG=$HN_HOME/log
	HN_WORK=$HN_HOME/work
	mkdir -p "$HN_LOG" "$HN_WORK"
	export HN_HOME HN_BOARD_DIR HN_NATIVE HN_MNT HN_ROOT HN_IMG HN_DATA HN_AROOT
}

# hn_hook <名字>：执行板级钩子，失败只记录（HN_HOOK_STRICT=1 时中止）
hn_hook() {
	h=$HN_BOARD_DIR/hooks/$1.sh
	[ -f "$h" ] || return 0
	hn_log "hook $1"
	if ! sh "$h" >> "$HN_LOG/hook-$1.log" 2>&1; then
		hn_log "hook $1 失败，见 $HN_LOG/hook-$1.log"
		[ "$HN_HOOK_STRICT" = 1 ] && exit 1
	fi
	return 0
}

hn_root_pids() {
	for p in /proc/[0-9]*; do
		[ "$(readlink "$p/root" 2>/dev/null)" = "$HN_ROOT" ] && echo "${p#/proc/}"
	done
}

hn_init_pid() {
	for p in $(hn_root_pids); do
		grep -q '^/system/bin/init' "/proc/$p/cmdline" 2>/dev/null && { echo "$p"; return; }
	done
}

hn_status() {
	for p in $(hn_root_pids); do
		echo "$p $(tr '\0' ' ' < "/proc/$p/cmdline")"
	done
	[ -f "$HN_LOG/inner.log" ] && { echo "--- inner.log"; tail -20 "$HN_LOG/inner.log"; }
}

hn_exec() {
	ipid=$(hn_init_pid)
	[ -n "$ipid" ] || hn_die "鸿蒙 init 未运行"
	exec $HN_BB nsenter -t "$ipid" -m -u $HN_BB chroot "$HN_ROOT" \
		/system/bin/toybox env -i PATH=/system/bin:/vendor/bin \
		LD_PRELOAD=/data/.hnshim.so "$@"
}
