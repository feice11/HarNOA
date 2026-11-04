# 停止鸿蒙用户态。

hn_down() {
	hn_hook down
	# 冻结中的进程收不到 SIGKILL，先全部解冻
	mkdir -p /tmp/hnfrz
	if mount -t cgroup -o freezer none /tmp/hnfrz 2>/dev/null; then
		for f in /tmp/hnfrz/*/freezer.state; do [ -e "$f" ] && echo THAWED > "$f"; done
		umount /tmp/hnfrz
	fi
	# appspawn 会不断拉起新进程，杀到没有为止
	for i in 1 2 3 4 5; do
		pids=$(hn_root_pids)
		[ -z "$pids" ] && break
		kill -9 $pids
		sleep 1
	done
	hn_root_pids
}
