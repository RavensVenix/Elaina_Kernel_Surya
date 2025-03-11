#ifndef MEMKERNEL_COMM_H
#define MEMKERNEL_COMM_H

#include <linux/types.h>
#include <linux/pid.h>

struct CopyMemory
{
    pid_t pid;
    uintptr_t addr;
    void *buffer;
    size_t size;
};

struct ModuleBase
{
    pid_t pid;
    char *name;
    uintptr_t base;
};

enum Operations
{
    OP_READ_MEM = 0x801,
    OP_WRITE_MEM = 0x802,
    OP_MODULE_BASE = 0x803,
    OP_GET_EXEC_BASE = 0x804,
    OP_GET_RW_BASE = 0x805
};

#endif
