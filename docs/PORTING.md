# 移植新设备

## 前提

- bootloader 已解锁，能 `fastboot boot`
- 能拿到该设备 Android 内核源码或可用的 GKI 内核，并能编译模块
- 一块专用数据分区（或可新建的 GPT 分区），用 ext4/f2fs，GPT 名字自定
- 鸿蒙系统镜像（system/vendor/... 的 erofs），需自行合法取得

## 步骤

1. `cp -r boards/_template boards/<厂商>-<代号>`，填写 `board.conf`
2. **内核**：在原配置上打开 `CONFIG_PID_NS` 等鸿蒙需要的选项；编译独立命名的 IPC 模块（节点名带 `HN_BINDER_PREFIX`）
3. **模块清单**：从 Android 的 `modules.load`（vendor_boot / vendor_dlkm / system_dlkm）合并出 `modules.list`
4. **数据分区布局**：
   ```
   $HN_MNT/
     harnoa/            本仓库 core/stage2 + boards/<板>（部署时拷入）
     img/               system.img vendor.img ...（erofs）
     data/              鸿蒙 /data
     aroot/             可选：Android vendor 只读视图，供 HAL 桥使用
     fw/                可选：合并后的固件目录
   ```
5. `boot/mkimg.sh ram boards/<板>` 生成 RAM 镜像，`fastboot boot`
6. 先只跑 `profiles/minimal.list`（samgr / hilog / foundation 等）确认 IPC 与服务注册，再加显示、输入、桌面
7. 按需写钩子：显示通常最先需要 `inner_dev` 放开 DRM/GPU 节点；触摸/Wi-Fi/音频多半需要 `bridges`
8. RAM 入口稳定后再考虑 `rec` / `dual`

## 排错入口

- S1 日志：`/dev/kmsg` 与 `$HN_MNT/harnoa.log`
- S2/S3 日志：`$HN_MNT/harnoa/log/`
- 进入鸿蒙命名空间执行命令：`sh harnoa.sh exec <命令>`
