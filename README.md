# HarNOA

**HarmonyOS NEXT On Android devices**

让 HarmonyOS NEXT（纯血鸿蒙）跑在 Android 手机上。

HarNOA 是一个开放的移植项目：对象是任何能解锁 bootloader 的 Android 设备，目标是让鸿蒙 NEXT 成为这些设备上能日常使用的系统，最终要能装官方镜像、和 Android 双系统共存，并由社区一台台适配。

> 当前阶段：**项目骨架**。已经定下统一的启动方式和设备适配接口；其余子系统按[路线图](docs/ROADMAP.md)陆续并入。参考设备 Redmi K90 Pro Max 上的原型已经能日常使用：桌面、网页、短信、音频、Wi-Fi、蓝牙等。这些成果会逐步整理进本仓库。

## 为什么能做

鸿蒙 NEXT 的用户态（init、samgr、ArkUI、ArkWeb、应用框架）本身与硬件无关，需要的只是：

- 一个满足鸿蒙要求的 Linux 内核：Android GKI 只需补少量配置，再加一个独立的 IPC 模块
- 一层硬件适配：显示、输入、音频、通信……可以直接复用 Android vendor 现成的驱动和 HAL

所以 HarNOA **不重写驱动，也不碰 Android 分区**，只在中间搭一座桥。每接入一台新设备，主要工作量都在“桥”这一层，而且大部分是同一 SoC 平台通用的。

## 项目范围

| 子系统 | 说明 | 状态 |
|---|---|---|
| **boot** | 启动入口（RAM / recovery 双系统 / 仅内核）、第一阶段 init、用户态拉起 | 骨架已有 |
| **kernel** | GKI 增量配置、独立 IPC（binder）模块、鸿蒙依赖的内核特性 | 规划 |
| **hal-bridge** | 显示合成、GPU（Mesa/Turnip）、触摸、音频、相机、传感器、振动：鸿蒙 HDI ⇄ Android HAL | 规划 |
| **connectivity** | 基带（通话/短信/数据）、Wi-Fi、蓝牙、GNSS | 规划 |
| **system** | 服务裁剪、SA 管理、cgroup 与功耗、存储、调度 | 规划 |
| **security** | HUKS、设备证明、TEE 兼容 | 研究 |
| **app-compat** | 应用市场、账号、推送、第三方应用兼容 | 研究 |
| **installer** | 一键 RAM 启动、双系统写入与恢复、OTA | 规划 |
| **devices** | 每台设备一个板目录；按 SoC 平台共享公共部分 | 1 台参考设备 |

## 架构一览

```
          ┌──────────────── HarmonyOS NEXT 用户态（原版，只读） ────────────────┐
          │  init · samgr · foundation · render_service · ArkWeb · 应用          │
          └──────────────▲───────────────────────────────▲─────────────────────────┘
                         │ 鸿蒙 HDI / VDI                 │ IPC
   ┌─────────────────────┴────────────┐         ┌──────────┴──────────┐
   │ HarNOA hal-bridge / connectivity │         │ 独立 IPC 模块        │
   └─────────────────────▲────────────┘         └──────────▲──────────┘
                         │ Android HAL（vendor 原样）      │
   ┌─────────────────────┴───────────────────────────────┴─────────────────────┐
   │        Android GKI 内核 + vendor 模块（增量配置，Android 照常可用）          │
   └───────────────────────────────────▲───────────────────────────────────────┘
                                       │ HarNOA boot：RAM / rec / dual 入口
                              设备原厂 bootloader（已解锁）
```

## 仓库结构

| 路径 | 内容 |
|---|---|
| `core/` | 与设备无关的启动核心（stage1 init、stage2 拉起器、垫片） |
| `boot/` | 入口镜像生成 |
| `boards/` | 设备适配：`_template/` 为模板，`xiaomi-myron/` 为参考设备 |
| `profiles/` | 鸿蒙服务清单（core / minimal / …） |
| `docs/` | 架构、启动入口、移植指南、路线图 |

后续子系统会以 `kernel/`、`bridge/`、`connectivity/`、`platforms/<SoC>/` 等目录加入。

## 文档

- [路线图](docs/ROADMAP.md)
- [架构](docs/ARCHITECTURE.md)：分层与启动阶段
- [启动入口](docs/BOOT_ENTRIES.md)：三种入口的设计
- [移植新设备](docs/PORTING.md)
- [参与贡献](CONTRIBUTING.md)

## 设备

| 设备 | SoC | 状态 |
|---|---|---|
| Redmi K90 Pro Max（myron） | Snapdragon 8 Elite Gen 5 / SM8850 | 参考设备，原型可日常使用，正在并入 |

欢迎提交你的设备。

## 致谢

“通用核心 + 板级描述”的组织方式受 UniXNU（如 [zg7681/UniXNU-myron](https://github.com/zg7681/UniXNU-myron)）启发；HarNOA 的启动方式、接口与实现均为独立设计。

## 声明与许可

代码采用 Apache-2.0。本项目**不分发**任何华为系统镜像、厂商固件或闭源二进制，请使用者从自己的设备或官方渠道合法获取。HarmonyOS 是华为技术有限公司的商标，本项目与华为、小米及其他厂商无关。
