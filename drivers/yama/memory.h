#ifndef YAMA_MEM_H
#define YAMA_MEM_H

#include <linux/kernel.h>
#include <linux/sched.h>

ssize_t readwrite_process_memory(pid_t pid, uintptr_t addr, void *buffer, size_t size, bool iswrite);

#endif