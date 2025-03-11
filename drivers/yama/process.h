#ifndef YAMA_PROC_H
#define YAMA_PROC_H

#include <linux/kernel.h>

#define ARC_PATH_MAX 256

uintptr_t get_module_base(pid_t pid, char *name);

#endif