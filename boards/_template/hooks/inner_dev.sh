#!/bin/sh
# 钩子 inner_dev：S3 组装 /dev 后（私有命名空间内）：节点权限、桥接套接字 bind 到 $HN_ROOT/dev
# 可用变量：HN_NATIVE HN_MNT HN_ROOT HN_DATA HN_AROOT HN_BOARD_DIR
# 删掉本文件即跳过此钩子。
:
