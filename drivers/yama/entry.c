#include <linux/module.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include "comm.h"
#include "memory.h"
#include "process.h"

#define DEVICE_NAME "Yama"

static DEFINE_MUTEX(driver_mutex);

static uintptr_t get_exec_base(pid_t pid) {
    struct task_struct *task;
    struct mm_struct *mm;
    struct vm_area_struct *vma;

    task = pid_task(find_vpid(pid), PIDTYPE_PID);
    if (!task) return 0;

    mm = task->mm;
    if (!mm) return 0;

    down_read(&mm->mmap_lock);

    for (vma = mm->mmap; vma; vma = vma->vm_next) {
        if (vma->vm_start <= mm->start_code && vma->vm_end >= mm->start_code) {
            uintptr_t base = vma->vm_start;
            up_read(&mm->mmap_lock);
            return base;
        }
    }

    up_read(&mm->mmap_lock);
    return 0;
}

static uintptr_t get_rw_base(pid_t pid) {
    struct task_struct *task;
    struct mm_struct *mm;
    struct vm_area_struct *vma;

    task = pid_task(find_vpid(pid), PIDTYPE_PID);
    if (!task) return 0;

    mm = task->mm;
    if (!mm) return 0;

    down_read(&mm->mmap_lock);

    for (vma = mm->mmap; vma; vma = vma->vm_next) {
        if (vma->vm_flags & (VM_READ | VM_WRITE)) {
            uintptr_t base = vma->vm_start;
            up_read(&mm->mmap_lock);
            return base;
        }
    }

    up_read(&mm->mmap_lock);
    return 0;
}

static int dispatch_open(struct inode *node, struct file *file) {
    if (!mutex_trylock(&driver_mutex))
        return -EBUSY;
    return 0;
}

static int dispatch_close(struct inode *node, struct file *file) {
    mutex_unlock(&driver_mutex);
    return 0;
}

static long dispatch_ioctl(struct file *const file, unsigned int const cmd, unsigned long const arg) {
    struct CopyMemory cm;
    struct ModuleBase mb;
    char name[0x100] = {0};

    switch (cmd) {
    case OP_READ_MEM:
    {
        if (!access_ok(VERIFY_READ, (void __user *)arg, sizeof(cm))) {
            return -1;
        }
        return readwrite_process_memory(cm.pid, cm.addr, cm.buffer, cm.size, false);
    }
    case OP_WRITE_MEM:
    {
        if (!access_ok(VERIFY_WRITE, (void __user *)arg, sizeof(cm))) {
            return -1;
        }
        return readwrite_process_memory(cm.pid, cm.addr, cm.buffer, cm.size, true);
    }
    case OP_MODULE_BASE:
    {
        if (copy_from_user(&mb, (void __user *)arg, sizeof(mb)) != 0 || copy_from_user(name, (void __user *)mb.name, sizeof(name) - 1) != 0) {
            return -1;
        }
        mb.base = get_module_base(mb.pid, name);
        if (copy_to_user((void __user *)arg, &mb, sizeof(mb)) != 0) {
            return -1;
        }
        break;
    }
    case OP_GET_EXEC_BASE:
    {
        pid_t pid;
        uintptr_t exec_base = 0;

        if (copy_from_user(&pid, (void __user *)arg, sizeof(pid)) != 0) {
            return -1;
        }

        exec_base = get_exec_base(pid);

        if (copy_to_user((void __user *)arg, &exec_base, sizeof(exec_base)) != 0) {
            return -1;
        }
        break;
    }
    case OP_GET_RW_BASE:
    {
        pid_t pid;
        uintptr_t rw_base = 0;

        if (copy_from_user(&pid, (void __user *)arg, sizeof(pid)) != 0) {
            return -1;
        }

        rw_base = get_rw_base(pid);

        if (copy_to_user((void __user *)arg, &rw_base, sizeof(rw_base)) != 0) {
            return -1;
        }
        break;
    }
    default:
        return -EINVAL;
    }
    return 0;
}

static struct file_operations dispatch_functions = {
    .owner = THIS_MODULE,
    .open = dispatch_open,
    .release = dispatch_close,
    .unlocked_ioctl = dispatch_ioctl,
};

static struct miscdevice misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = DEVICE_NAME,
    .fops = &dispatch_functions,
};

int __init memkernel_entry(void) {
    int ret;
    ret = misc_register(&misc);
    return ret;
}

void __exit memkernel_unload(void) {
    misc_deregister(&misc);
}

module_init(memkernel_entry);
module_exit(memkernel_unload);

MODULE_DESCRIPTION("Linux Kernel.");
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Linux");
