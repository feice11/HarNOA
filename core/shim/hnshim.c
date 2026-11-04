// SPDX-License-Identifier: Apache-2.0
/*
 * hnshim.so：经 LD_PRELOAD 注入鸿蒙 init（及其子进程）的垫片。
 *
 *   1. HN_FAKE_PID1=1 时，init 进程内 getpid() 返回 1（鸿蒙 init 以此判断自己是否为第一进程）；
 *      子进程 fork 后自动失效，并清掉该环境变量
 *   2. 装 seccomp 过滤器，让会伤到宿主的系统调用返回 EPERM：
 *      reboot / init_module / finit_module / delete_module / kexec_load / swapon / swapoff
 *      TODO：mount 按文件系统类型放行（cgroup 由 S3 预先挂好）、kill(-1) 拦截
 *
 * 编译：用鸿蒙 SDK 的 musl 工具链（垫片必须与鸿蒙 libc 一致）。
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

static pid_t real_pid;
static int fake_pid1;

pid_t getpid(void)
{
	pid_t p = (pid_t)syscall(SYS_getpid);
	return (fake_pid1 && p == real_pid) ? 1 : p;
}

#define DENY(nr) \
	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (nr), 0, 1), \
	BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA))

static void install_seccomp(void)
{
	struct sock_filter f[] = {
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 1, 0),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
		DENY(__NR_reboot),
		DENY(__NR_init_module),
		DENY(__NR_finit_module),
		DENY(__NR_delete_module),
		DENY(__NR_kexec_load),
		DENY(__NR_swapon),
		DENY(__NR_swapoff),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
	};
	struct sock_fprog prog = { .len = sizeof(f) / sizeof(f[0]), .filter = f };

	prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
	prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);
}

__attribute__((constructor)) static void hnshim_init(void)
{
	const char *v = getenv("HN_FAKE_PID1");

	real_pid = (pid_t)syscall(SYS_getpid);
	if (v && !strcmp(v, "1")) {
		fake_pid1 = 1;
		unsetenv("HN_FAKE_PID1"); /* 不传给子进程 */
		install_seccomp();        /* 过滤器随 fork/exec 继承 */
	}
}
