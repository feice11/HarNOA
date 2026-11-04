// SPDX-License-Identifier: Apache-2.0
/*
 * harnoa-init: HarNOA 第一阶段 init（PID 1），设备无关。
 *
 * 职责（骨架）：
 *   1. 早期挂载（已挂载则跳过，兼容 rec 入口下 Android 第一阶段 init 先挂过的情况）
 *   2. 按清单加载内核模块，多轮重试解决依赖顺序
 *   3. 按 GPT PARTNAME 找到数据分区并挂载
 *   4. 执行一次 S2：sh $HN_STAGE2 up
 *   5. 失败安全：HN_FAILSAFE_SEC 内未出现 /tmp/harnoa.stay 则重启回 Android
 *   6. 作为 PID1 回收子进程
 *
 * 配置：/etc/harnoa/stage1.conf（KEY=VALUE，由 boot/mkimg.sh 从 board.conf 生成）。
 * TODO：屏幕日志、USB ACM 调试串口、电源键回 Android，以可选模块加入。
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CONF_FILE  "/etc/harnoa/stage1.conf"
#define STAY_FLAG  "/tmp/harnoa.stay"
#define MOD_ROUNDS 5

static struct {
	char part[64];      /* HN_PART：数据分区 GPT 名 */
	char mnt[128];      /* HN_MNT：挂载点 */
	char fstype[16];    /* HN_FS */
	char modlist[128];  /* HN_MODLIST：模块清单（ramdisk 内路径） */
	char stage2[192];   /* HN_STAGE2：相对 HN_MNT 的 S2 入口 */
	char shell[64];     /* HN_SHELL */
	int failsafe;       /* HN_FAILSAFE_SEC，0 为关闭 */
} cfg = {
	.part = "harnoa", .mnt = "/hn", .fstype = "ext4",
	.modlist = "/etc/harnoa/modules.list",
	.stage2 = "harnoa/core/stage2/harnoa.sh",
	.shell = "/bin/sh", .failsafe = 900,
};

static int kmsg_fd = -1;

static void hnlog(const char *fmt, ...)
{
	char buf[512];
	int n = snprintf(buf, sizeof(buf), "<6>harnoa-init: ");
	va_list ap;
	va_start(ap, fmt);
	n += vsnprintf(buf + n, sizeof(buf) - n - 1, fmt, ap);
	va_end(ap);
	if (n > (int)sizeof(buf) - 2)
		n = sizeof(buf) - 2;
	buf[n++] = '\n';
	if (kmsg_fd >= 0)
		write(kmsg_fd, buf, n);
}

static long uptime_sec(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_BOOTTIME, &ts);
	return ts.tv_sec;
}

static void set_str(char *dst, size_t cap, const char *v)
{
	snprintf(dst, cap, "%s", v);
}

static void load_conf(void)
{
	FILE *f = fopen(CONF_FILE, "r");
	char line[256];
	if (!f) {
		hnlog("no %s, using defaults", CONF_FILE);
		return;
	}
	while (fgets(line, sizeof(line), f)) {
		char *eq, *v;
		line[strcspn(line, "\r\n")] = 0;
		if (line[0] == '#' || !(eq = strchr(line, '=')))
			continue;
		*eq = 0;
		v = eq + 1;
		if (*v == '"') {
			v++;
			v[strcspn(v, "\"")] = 0;
		}
		if (!strcmp(line, "HN_PART")) set_str(cfg.part, sizeof(cfg.part), v);
		else if (!strcmp(line, "HN_MNT")) set_str(cfg.mnt, sizeof(cfg.mnt), v);
		else if (!strcmp(line, "HN_FS")) set_str(cfg.fstype, sizeof(cfg.fstype), v);
		else if (!strcmp(line, "HN_MODLIST")) set_str(cfg.modlist, sizeof(cfg.modlist), v);
		else if (!strcmp(line, "HN_STAGE2")) set_str(cfg.stage2, sizeof(cfg.stage2), v);
		else if (!strcmp(line, "HN_SHELL")) set_str(cfg.shell, sizeof(cfg.shell), v);
		else if (!strcmp(line, "HN_FAILSAFE_SEC")) cfg.failsafe = atoi(v);
	}
	fclose(f);
}

/* 已挂载（EBUSY）视为成功 */
static void try_mount(const char *src, const char *dst, const char *type,
		      unsigned long flags, const char *data)
{
	mkdir(dst, 0755);
	if (mount(src, dst, type, flags, data) && errno != EBUSY)
		hnlog("mount %s on %s: %s", type, dst, strerror(errno));
}

static void early_mounts(void)
{
	try_mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
	try_mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	try_mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	try_mount("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
	try_mount("configfs", "/sys/kernel/config", "configfs", 0, NULL);
	mkdir("/dev/pts", 0755);
	try_mount("devpts", "/dev/pts", "devpts", 0, "mode=0620,ptmxmode=0666");
	kmsg_fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
}

/* ---------- 模块 ---------- */

static int load_module(const char *path)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	int rc;
	if (fd < 0)
		return -errno;
	rc = syscall(SYS_finit_module, fd, "", 0) ? -errno : 0;
	close(fd);
	return rc == -EEXIST ? 0 : rc;
}

static void load_modules(void)
{
	FILE *f;
	char line[256];
	int round, pending = 1;

	for (round = 0; round < MOD_ROUNDS && pending; round++) {
		int ok = 0;
		pending = 0;
		if (!(f = fopen(cfg.modlist, "r"))) {
			hnlog("no module list %s", cfg.modlist);
			return;
		}
		while (fgets(line, sizeof(line), f)) {
			line[strcspn(line, "\r\n")] = 0;
			if (!line[0] || line[0] == '#')
				continue;
			int rc = load_module(line);
			if (!rc)
				ok++;
			else if (rc != -ENOENT)
				pending++;
		}
		fclose(f);
		hnlog("modules round %d: ok=%d pending=%d", round, ok, pending);
	}
	/* TODO：记录最后仍失败的模块名到 /tmp/harnoa.modfail */
}

/* ---------- 数据分区 ---------- */

static int find_part(char *devpath, size_t cap)
{
	DIR *d = opendir("/sys/class/block");
	struct dirent *e;
	char path[300], buf[512], want[80];
	int found = 0;

	if (!d)
		return 0;
	snprintf(want, sizeof(want), "PARTNAME=%s\n", cfg.part);
	while (!found && (e = readdir(d))) {
		int fd, n;
		if (e->d_name[0] == '.')
			continue;
		snprintf(path, sizeof(path), "/sys/class/block/%s/uevent", e->d_name);
		if ((fd = open(path, O_RDONLY | O_CLOEXEC)) < 0)
			continue;
		n = read(fd, buf, sizeof(buf) - 1);
		close(fd);
		if (n <= 0)
			continue;
		buf[n] = 0;
		if (strstr(buf, want)) {
			snprintf(devpath, cap, "/dev/block/%s", e->d_name);
			/* devtmpfs 下节点在 /dev/<名>，统一建一份到 /dev/block */
			mkdir("/dev/block", 0755);
			char src[300];
			snprintf(src, sizeof(src), "/dev/%s", e->d_name);
			symlink(src, devpath);
			found = 1;
		}
	}
	closedir(d);
	return found;
}

static int mount_data(void)
{
	char dev[300];
	if (!find_part(dev, sizeof(dev)))
		return 0;
	mkdir(cfg.mnt, 0755);
	if (mount(dev, cfg.mnt, cfg.fstype, MS_NOATIME, NULL) && errno != EBUSY) {
		hnlog("mount %s: %s", dev, strerror(errno));
		return 0;
	}
	hnlog("data %s -> %s", dev, cfg.mnt);
	return 1;
}

/* ---------- S2 ---------- */

static pid_t spawn_stage2(void)
{
	char path[400];
	pid_t pid;

	snprintf(path, sizeof(path), "%s/%s", cfg.mnt, cfg.stage2);
	if (access(path, R_OK)) {
		hnlog("stage2 %s missing", path);
		return -1;
	}
	if ((pid = fork()) == 0) {
		setsid();
		execl(cfg.shell, cfg.shell, path, "up", (char *)NULL);
		_exit(127);
	}
	hnlog("stage2 pid %d", pid);
	return pid;
}

static void go_android(const char *why)
{
	hnlog("return to Android: %s", why);
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, "");
	reboot(RB_AUTOBOOT);
}

int main(void)
{
	pid_t s2 = 0;
	int data_ok = 0;

	if (getpid() != 1) {
		fprintf(stderr, "harnoa-init must run as PID 1\n");
		return 1;
	}
	signal(SIGPIPE, SIG_IGN);
	early_mounts();
	hnlog("start");
	close(open("/tmp/harnoa.native", O_WRONLY | O_CREAT | O_CLOEXEC, 0644));
	load_conf();
	load_modules();

	for (;;) {
		int st;
		pid_t p;

		if (!data_ok && (data_ok = mount_data()))
			s2 = spawn_stage2();
		/* 回收所有子进程（包括被托孤的） */
		while ((p = waitpid(-1, &st, WNOHANG)) > 0)
			if (p == s2)
				hnlog("stage2 exited %d", WIFEXITED(st) ? WEXITSTATUS(st) : -1);

		if (cfg.failsafe > 0 && uptime_sec() > cfg.failsafe &&
		    access(STAY_FLAG, F_OK))
			go_android("failsafe timeout");
		sleep(1);
	}
}
