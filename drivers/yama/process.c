#include "process.h"
#include <linux/sched.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 11, 0)
#include <linux/sched/mm.h>
#include <linux/sched/task.h>
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0))
#include <linux/mmap_lock.h>
#define MM_READ_LOCK(mm) mmap_read_lock(mm);
#define MM_READ_UNLOCK(mm) mmap_read_unlock(mm);
#else
#include <linux/rwsem.h>
#define MM_READ_LOCK(mm) down_read(&(mm)->mmap_sem);
#define MM_READ_UNLOCK(mm) up_read(&(mm)->mmap_sem);
#endif

uintptr_t find_library_base(pid_t pid, const char *lib_name) {
    struct task_struct *task = get_pid_task(find_get_pid(pid), PIDTYPE_PID);
    if (!task || !task->mm)
        return 0;

    struct mm_struct *mm = task->mm;
    struct vm_area_struct *vma;
    uintptr_t base = 0;

    MM_READ_LOCK(mm);
    vma = mm->mmap;
    while (vma) {
        if (vma->vm_file) {
            char file_name[256];
            char *path = d_path(&vma->vm_file->f_path, file_name, sizeof(file_name));
            if (!IS_ERR(path) && strstr(path, lib_name) && (vma->vm_flags & VM_EXEC)) {
                base = vma->vm_start;
                break;
            }
        }
        vma = vma->vm_next;
    }
    MM_READ_UNLOCK(mm);

    return base;
}

uintptr_t get_module_base(pid_t pid, char *name)
{
    struct pid *pid_struct;
    struct task_struct *task;
    struct mm_struct *mm;
    struct vm_area_struct *vma;
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
    struct vma_iterator vmi;
#endif
    uintptr_t module_base = 0;

    pid_struct = find_get_pid(pid);
    if (!pid_struct) {
        return false;
    }
    task = get_pid_task(pid_struct, PIDTYPE_PID);
    put_pid(pid_struct);
    if (!task) {
        return false;
    }
    mm = get_task_mm(task);
    put_task_struct(task);
    if (!mm) {
        return false;
    }

    MM_READ_LOCK(mm);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0))
    vma_iter_init(&vmi, mm, 0);
    for_each_vma(vmi, vma)
#else
    for (vma = mm->mmap; vma; vma = vma->vm_next)
#endif
    {
        char buf[ARC_PATH_MAX];
        char *path_nm = "";

        if (vma->vm_file) {
            path_nm = file_path(vma->vm_file, buf, ARC_PATH_MAX - 1);
            if (!strcmp(kbasename(path_nm), name)) {
                module_base = vma->vm_start;
                break;
            }
        }
    }

    MM_READ_UNLOCK(mm);
    mmput(mm);
    return module_base;
}
