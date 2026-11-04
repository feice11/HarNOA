# 架构

## 设计原则

1. **借内核，不改内核**：Android GKI 内核 + vendor 模块原样使用，只增量补配置和独立 IPC 模块（节点名与 Android binder 不冲突，两套用户态可共存）。
2. **零写入优先**：首选 `fastboot boot` RAM 启动；持久入口只写 recovery 槽，并保证 Android 正常开机不受影响。
3. **失败安全**：S1 在限定时间内未收到“已就绪”标记就重启回 Android；电源键长按随时回 Android。
4. **核心与设备分离**：`core/` 不出现任何设备名、分区号、驱动名；设备差异全部通过 `board.conf` 变量和钩子表达。
5. **鸿蒙镜像只读**：系统镜像以 erofs 只读挂载，所有修改走覆盖层（单文件 bind / 整目录替换），可随时撤掉。

## 阶段

### S0 入口（boot/）

见 [BOOT_ENTRIES.md](BOOT_ENTRIES.md)。三种入口共用同一内核与同一 ramdisk 内容。

### S1 harnoa-init（core/stage1/）

静态 PID1，只做内核到用户态之间不可省略的事：

| 步骤 | 说明 |
|---|---|
| 早期挂载 | devtmpfs/proc/sysfs/configfs/tmpfs，`/dev/kmsg` 日志 |
| 设备节点 | devtmpfs 不可用时扫描 `/sys/dev` 补节点 |
| 模块 | 按 `HN_MODLIST` 多轮 `finit_module`，依赖顺序靠重试解决 |
| 数据分区 | 按 GPT `PARTNAME=$HN_PART` 查找并挂到 `$HN_MNT`（不依赖分区编号） |
| 拉起 S2 | `sh $HN_STAGE2 up`，只执行一次 |
| 失败安全 | `HN_FAILSAFE_SEC` 内未出现 `/tmp/harnoa.stay` → 重启回 Android |
| 收尸 | 作为 PID1 回收孤儿进程 |

调试通道（屏幕日志、USB ACM 串口 shell）以可选模块形式后续加入，骨架只留接口。

### S2 harnoa up（core/stage2/lib/up.sh）

在宿主命名空间运行，负责“鸿蒙用户态之外但它离不开”的部分：

1. `hook pre_up` —— 板级：固件路径、调速器、远程处理器（DSP）启动等
2. `hook bridges` —— 板级：在 Android vendor chroot（`$HN_AROOT`）里拉起 HAL 桥（触摸、Wi-Fi、音频、蓝牙……）
3. 加载 IPC 模块，等待 `/dev/$HN_BINDER_PREFIX*binder` 出现
4. 挂载 erofs：`system` 为根，其余分区按 `HN_IMAGES` 挂到子目录
5. `unshare -m -u` 进入 S3

### S3 harnoa inner（core/stage2/lib/inner.sh）

在私有 mount/UTS 命名空间中组装鸿蒙根：

1. **服务清单**：按 `profiles/*.list` 从镜像 init 目录取 cfg，统一改写（去 critical、去 restorecon），其余 init 目录用空 tmpfs 遮住
2. **SA 隐藏**：进程未启用的 SA profile 从 samgr 视野中移除，避免按需加载时空等
3. **覆盖层**：先整目录替换（`overlay_dir/**/.dir`），后单文件 bind（`overlay/`）
4. **/dev**：tmpfs + 基础节点 + IPC 节点按鸿蒙名字建立 + 宿主字符设备补齐（块设备一律不给）
5. **/proc /sys**：伪造 `/proc/cmdline`（追加 `ohos.boot.*`），`hook inner_dev` 做板级绑定
6. **cgroup**：替 init 挂好 cpuset/cpuctl/freezer（init 内 mount 被垫片拦截）
7. `exec chroot $ROOT /system/bin/init --second-stage`，`LD_PRELOAD=hnshim.so`

### S4 鸿蒙 init

原版 init 第二阶段，不做修改。垫片 `hnshim.so` 让它以为自己是 PID1，并拦截 reboot / 模块加载 / `kill(-1)` 等会伤到宿主的调用。

## 板级接口

`board.conf` 是 busybox sh 可 source 的 `KEY=VALUE` 文件；钩子是 `boards/<板>/hooks/<名字>.sh`，存在才执行，失败只记录不中断（`pre_up`/`bridges` 例外可设 `HN_HOOK_STRICT=1`）。

| 钩子 | 时机 | 典型用途 |
|---|---|---|
| `pre_up` | S2 开头 | 固件路径、调速器、DSP |
| `bridges` | IPC 加载前 | Android vendor HAL 桥 |
| `post_mount` | 镜像挂载后 | 额外分区/数据目录 |
| `inner_dev` | S3 组装 /dev 后 | 节点权限、桥接套接字 bind |
| `pre_exec` | exec init 前 | 最后的修补 |
| `down` | 停止时 | 停桥、解冻 |
