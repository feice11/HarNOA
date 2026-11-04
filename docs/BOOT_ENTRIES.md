# 启动入口

三种入口按“写入代价”从低到高排列，**共用同一内核与同一 ramdisk 内容**。改了内核或 ramdisk，持久入口必须重建重写；只改数据分区上的鸿蒙文件则三者自动同步。

| 入口 | 写入 | 怎么进 | 适用 |
|---|---|---|---|
| `ram` | 无 | `fastboot boot harnoa-ram.img` | 首次移植、调试 |
| `rec` | recovery 槽 | 关机后 电源+音量上 / `adb reboot recovery` | 日常双系统 |
| `dual` | boot 槽（仅内核） | 配合 `rec`，Android 正常开机也跑新内核 | 内核需要补配置时 |

## ram

标准 boot 镜像（内核 + HarNOA ramdisk），由 bootloader 直接加载到内存。不碰任何分区，重启即回原系统。

## rec

许多 Qualcomm ABL 会拒绝自带内核的 recovery 镜像，并在 recovery 模式下同样拼接 `init_boot` 的 Android ramdisk。HarNOA 的做法：

1. recovery 镜像为 v4、`kernel_size=0`，借用 boot 槽内核；
2. ramdisk 中放 `/system/bin/recovery` 标记文件，Android 第一阶段 init 据此判定 recovery 模式、跳过挂 system；
3. `/system/bin/init` 指向 `harnoa-init`，第一阶段 init 直接 exec 它；
4. `harnoa-init` 容忍 `/proc` `/sys` `/dev` 已被挂载、模块 `EEXIST`。

进入 recovery 后 misc（BCB）可能残留 `boot-recovery`，S2 需要在确认是本入口后清除这一条（仅这一条），否则普通重启仍会回到鸿蒙。实现放在板级 `pre_up` 钩子，因为 misc 布局与设备相关。

## dual

boot 槽只替换内核（v4、无 ramdisk），bootloader 照常拼 `init_boot`，Android 在新内核上完整开机。前提是新内核对 Android 完全兼容（只做增量配置），并已在 `ram` 入口下验证过 Android 侧。

## 写入前检查（boot/mkimg.sh 只生成，不刷写）

刷写由使用者自己执行。建议的检查：产品代号、解锁状态、非 fastbootd、目标分区双槽存在且容量与镜像完全相等、已备份原分区。
