# xiaomi-myron

Redmi K90 Pro Max（SM8850 / canoe），HarNOA 的参考板。

- 内核：Android16 6.12 GKI + `CONFIG_PID_NS`，独立 IPC 模块节点前缀 `hmos_`
- 数据分区：GPT 名 `unixnu`，ext4，挂到 `/hm`
- 入口：三种均已在该机型的原型实现中验证（ram / rec / dual）；HarNOA 骨架尚在迁移中
- 已知需要的 Android 侧桥：触摸（THP）、Wi-Fi（cnss）、音频（AGM/ADSP）、蓝牙、振动、基带/GNSS、相机
