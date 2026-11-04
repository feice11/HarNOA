# HarNOA

**Har**mony **N**ative **O**n **A**ndroid-hardware —— 在已有 Android 内核与驱动的设备上，以最小代价把 OpenHarmony / HarmonyOS 用户态拉起来的通用启动框架。

> 状态：**骨架阶段**。目前只定义启动方式、目录约定与板级接口，还不能直接在任何设备上开机。

## 思路

不移植内核、不重写驱动、不动 Android 分区。复用设备现成的 Android GKI 内核与 vendor 驱动，只在内核上补少量配置（如 `CONFIG_PID_NS`）和一个独立命名的 IPC（binder）模块，然后：

```
S0 入口      fastboot boot（RAM，零写入） / recovery 槽（无内核 ramdisk） / boot 槽仅换内核
S1 harnoa-init   静态 PID1：挂 /proc /sys /dev、按清单加载模块、找数据分区、失败安全回 Android
S2 harnoa up     宿主段：拉起 Android vendor 桥（板级钩子）、加载 IPC 模块、挂 erofs 系统镜像
S3 harnoa inner  隔离段：私有 mount/UTS 命名空间，组装 /dev /proc /sys、服务清单、覆盖层
S4 鸿蒙 init     exec /system/bin/init --second-stage（带垫片：伪 PID1 + seccomp）
```

设备相关的一切放进 `boards/<厂商>-<代号>/`：一个 `board.conf` 加若干钩子脚本。`core/` 保持与设备无关。

## 目录

| 路径 | 内容 |
|---|---|
| `core/stage1/` | `harnoa-init`：通用第一阶段 init（C，静态链接） |
| `core/stage2/` | `harnoa.sh`：用户态拉起器（busybox sh），`lib/` 为分段实现 |
| `core/shim/` | `hnshim.so`：注入鸿蒙 init 的垫片（伪 PID1、拦危险系统调用） |
| `boot/` | `mkimg.sh`：按板级配置生成 ram / rec / dual 三种入口镜像 |
| `boards/_template/` | 新设备模板 |
| `boards/xiaomi-myron/` | 参考板：Redmi K90 Pro Max（SM8850） |
| `profiles/` | 服务清单（最小桌面集等） |
| `docs/` | 架构、启动流程、移植指南 |

## 快速了解

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 分层与各阶段职责
- [docs/BOOT_ENTRIES.md](docs/BOOT_ENTRIES.md) — 三种入口为什么这样设计
- [docs/PORTING.md](docs/PORTING.md) — 新设备移植步骤

## 致谢

分层（通用核心 / 板级描述 / 组件）的组织方式受 UniXNU（如 [zg7681/UniXNU-myron](https://github.com/zg7681/UniXNU-myron)）启发；HarNOA 的启动方式、配置格式与实现均为独立设计。

## 许可

Apache-2.0。不包含任何厂商固件、系统镜像或闭源二进制，这些需由使用者从自己的设备/官方渠道获取。
