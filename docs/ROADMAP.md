# 路线图

## 阶段 0：项目骨架（进行中）

- [x] 统一启动方式：S0 入口 / S1 harnoa-init / S2 宿主段 / S3 隔离段 / S4 鸿蒙 init
- [x] 板级接口：`board.conf` + 钩子
- [x] 参考设备板目录（xiaomi-myron）
- [ ] 参考设备上用 HarNOA 核心替换原型启动链并完成真机验收
- [ ] 调试通道：屏幕日志、USB ACM 串口、无线 shell

## 阶段 1：能开机（任意新设备的第一个里程碑）

- [ ] kernel：GKI 增量配置清单（`CONFIG_PID_NS` 等）与独立 IPC 模块源码
- [ ] 模块清单自动生成（由 vendor_boot / vendor_dlkm / system_dlkm 合并）
- [ ] 显示：DRM composer VDI，GPU 走 Mesa Turnip（Adreno）/ Panfrost 等
- [ ] 输入：通用 evdev，以及厂商触摸方案的桥
- [ ] 进到桌面

## 阶段 2：能日常用

- [ ] 音频（Qualcomm AGM/ADSP 平台桥）、通话音频
- [ ] 基带：数据、短信、通话
- [ ] Wi-Fi、蓝牙、GNSS
- [ ] 功耗：cgroup、冻结、调频、深度休眠
- [ ] 相机、传感器、振动、指纹
- [ ] 存储、文件管理、侧载安装

## 阶段 3：能分发

- [ ] installer：一键 RAM 启动、双系统写入/恢复（写前校验、可回滚）
- [ ] 内核与 ramdisk 变更后自动重建全部入口
- [ ] 按 SoC 平台抽取公共层（`platforms/<SoC>/`），新设备只写差异
- [ ] 鸿蒙系统镜像获取与校验工具（不分发镜像本身）

## 阶段 4：生态

- [ ] HUKS / 设备证明 / TEE 兼容研究
- [ ] 应用市场、账号、推送
- [ ] 社区设备适配流程、CI（脚本检查、镜像构建）

## 子系统负责目录（规划）

| 目录 | 子系统 |
|---|---|
| `core/` `boot/` | 启动 |
| `kernel/` | 内核配置、IPC 模块 |
| `bridge/` | 显示、GPU、输入、音频、相机、传感器、振动 |
| `connectivity/` | 基带、Wi-Fi、蓝牙、GNSS |
| `system/` | 服务、功耗、存储 |
| `platforms/<SoC>/` | 同平台共享的桥与配置 |
| `boards/<设备>/` | 单台设备差异 |
| `installer/` | 安装与恢复 |
