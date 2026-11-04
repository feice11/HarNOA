# S2 宿主段。

hn_up() {
	exec >> "$HN_LOG/up.log" 2>&1
	hn_log "up native=${HN_NATIVE:-0} board=$HN_BOARD"
	[ -n "$(hn_root_pids)" ] && hn_die "已在运行"

	hn_hook pre_up
	hn_hook bridges

	# IPC：独立命名的 binder 模块，节点为 /dev/${HN_BINDER_PREFIX}binder 等
	if ! grep -q "${HN_BINDER_PREFIX}binder" /proc/misc; then
		insmod "$HN_IPC_KO" || hn_die "IPC 模块加载失败: $HN_IPC_KO"
	fi
	for i in 1 2 3 4 5; do
		grep -q "${HN_BINDER_PREFIX}binder" /proc/misc && break
		sleep 1
	done

	# 系统镜像：erofs 只读，system 为根，其余挂到同名子目录
	mkdir -p "$HN_ROOT"
	hn_ismnt "$HN_ROOT" || mount -t erofs -o ro "$HN_IMG/system.img" "$HN_ROOT" \
		|| hn_die "挂载 system.img 失败"
	for p in $HN_IMAGES; do
		img=$HN_IMG/$p.img
		[ -f "$img" ] || { hn_log "跳过缺失镜像 $p"; continue; }
		hn_ismnt "$HN_ROOT/$p" || mount -t erofs -o ro "$img" "$HN_ROOT/$p" \
			|| hn_log "挂载 $p 失败"
	done
	hn_hook post_mount

	# 垫片放进鸿蒙 /data，供 LD_PRELOAD
	mkdir -p "$HN_DATA"
	[ -f "$HN_HOME/core/shim/hnshim.so" ] && \
		cp "$HN_HOME/core/shim/hnshim.so" "$HN_DATA/.hnshim.so" && chmod 755 "$HN_DATA/.hnshim.so"

	# 进入隔离段：私有 mount/UTS 命名空间
	nohup $HN_BB unshare -m -u --propagation private \
		$HN_BB sh "$HN_CORE/harnoa.sh" inner > "$HN_LOG/inner.log" 2>&1 &

	# 告诉 harnoa-init 已就绪，取消失败安全重启。
	# TODO：改为等鸿蒙关键服务（如桌面）就绪后再置位
	[ -n "$HN_NATIVE" ] && touch /tmp/harnoa.stay
	hn_log "up done"
}
