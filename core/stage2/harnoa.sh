#!/bin/sh
# HarNOA S2/S3 拉起器（busybox sh）。
# 用法: sh harnoa.sh up|inner|down|status|exec <命令...>
#   up      宿主段：板级桥、IPC 模块、挂镜像，然后进入隔离段
#   inner   隔离段（由 up 经 unshare 调用，不要手动执行）
#   down    停止鸿蒙用户态
#   status  列出鸿蒙根内进程
#   exec    进入鸿蒙 init 的命名空间执行命令
umask 022
HN_CORE=$(cd "$(dirname "$0")" && pwd)
. "$HN_CORE/lib/common.sh"
hn_load_board

case "$1" in
up)     . "$HN_CORE/lib/up.sh";    hn_up ;;
inner)  . "$HN_CORE/lib/inner.sh"; hn_inner ;;
down)   . "$HN_CORE/lib/down.sh";  hn_down ;;
status) hn_status ;;
exec)   shift; hn_exec "$@" ;;
*)      echo "用法: $0 up|down|status|exec <命令>"; exit 2 ;;
esac
