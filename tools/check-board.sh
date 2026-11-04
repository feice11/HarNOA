#!/bin/sh
# 检查板目录是否完整：sh tools/check-board.sh boards/<板>
B=${1:?板目录}
rc=0
[ -f "$B/board.conf" ] || { echo "缺少 board.conf"; exit 1; }
. "$B/board.conf"
for k in HN_BOARD HN_HARDWARE HN_PART HN_MNT HN_BINDER_PREFIX HN_PROFILE; do
	eval v=\$$k
	[ -n "$v" ] || { echo "未设置 $k"; rc=1; }
done
[ -f "$(dirname "$0")/../profiles/$HN_PROFILE.list" ] || { echo "profile $HN_PROFILE 不存在"; rc=1; }
for h in "$B"/hooks/*.sh; do
	[ -f "$h" ] || continue
	sh -n "$h" || { echo "语法错误: $h"; rc=1; }
done
[ $rc = 0 ] && echo "$HN_BOARD: OK"
exit $rc
