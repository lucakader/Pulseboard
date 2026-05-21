#include "PulseboardSystem.h"

#include <errno.h>
#include <ifaddrs.h>
#include <libproc.h>
#include <mach/mach.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

static uint64_t pb_page_bytes(uint64_t pages, vm_size_t page_size) {
    return pages * (uint64_t)page_size;
}

int PBProcessCount(void) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) {
        return 0;
    }
    return bytes / (int)sizeof(pid_t);
}

int PBListProcesses(PBProcessSample *buffer, size_t capacity) {
    int pid_count = PBProcessCount();
    if (pid_count <= 0 || buffer == NULL || capacity == 0) {
        return pid_count;
    }

    size_t pid_bytes = (size_t)pid_count * sizeof(pid_t);
    pid_t *pids = (pid_t *)malloc(pid_bytes);
    if (pids == NULL) {
        return -1;
    }

    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)pid_bytes);
    if (bytes <= 0) {
        free(pids);
        return 0;
    }

    int observed = bytes / (int)sizeof(pid_t);
    size_t written = 0;

    for (int index = 0; index < observed && written < capacity; index++) {
        pid_t pid = pids[index];
        if (pid <= 0) {
            continue;
        }

        struct proc_taskallinfo task_info;
        memset(&task_info, 0, sizeof(task_info));

        int task_size = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &task_info, sizeof(task_info));
        if (task_size <= 0) {
            struct proc_bsdinfo bsd_info;
            memset(&bsd_info, 0, sizeof(bsd_info));
            int bsd_size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd_info, sizeof(bsd_info));
            if (bsd_size <= 0) {
                continue;
            }

            PBProcessSample sample;
            memset(&sample, 0, sizeof(sample));
            sample.pid = (int32_t)bsd_info.pbi_pid;
            sample.ppid = (int32_t)bsd_info.pbi_ppid;
            sample.uid = (uint32_t)bsd_info.pbi_uid;
            sample.status = (int32_t)bsd_info.pbi_status;
            sample.start_time_sec = (uint64_t)bsd_info.pbi_start_tvsec;
            sample.start_time_usec = (uint64_t)bsd_info.pbi_start_tvusec;

            const char *name = strlen(bsd_info.pbi_name) > 0 ? bsd_info.pbi_name : bsd_info.pbi_comm;
            snprintf(sample.name, sizeof(sample.name), "%s", name);
            proc_pidpath(pid, sample.path, sizeof(sample.path));
            buffer[written++] = sample;
            continue;
        }

        PBProcessSample sample;
        memset(&sample, 0, sizeof(sample));
        sample.pid = (int32_t)task_info.pbsd.pbi_pid;
        sample.ppid = (int32_t)task_info.pbsd.pbi_ppid;
        sample.uid = (uint32_t)task_info.pbsd.pbi_uid;
        sample.status = (int32_t)task_info.pbsd.pbi_status;
        sample.thread_count = (int32_t)task_info.ptinfo.pti_threadnum;
        sample.resident_size = (uint64_t)task_info.ptinfo.pti_resident_size;
        sample.virtual_size = (uint64_t)task_info.ptinfo.pti_virtual_size;
        sample.total_user_time_ns = (uint64_t)task_info.ptinfo.pti_total_user;
        sample.total_system_time_ns = (uint64_t)task_info.ptinfo.pti_total_system;
        sample.start_time_sec = (uint64_t)task_info.pbsd.pbi_start_tvsec;
        sample.start_time_usec = (uint64_t)task_info.pbsd.pbi_start_tvusec;

        const char *name = strlen(task_info.pbsd.pbi_name) > 0 ? task_info.pbsd.pbi_name : task_info.pbsd.pbi_comm;
        snprintf(sample.name, sizeof(sample.name), "%s", name);
        proc_pidpath(pid, sample.path, sizeof(sample.path));
        buffer[written++] = sample;
    }

    free(pids);
    return (int)written;
}

int PBReadSystem(PBSystemSample *sample) {
    if (sample == NULL) {
        return -1;
    }

    memset(sample, 0, sizeof(PBSystemSample));

    host_cpu_load_info_data_t cpu_info;
    mach_msg_type_number_t cpu_count = HOST_CPU_LOAD_INFO_COUNT;
    kern_return_t cpu_result = host_statistics(
        mach_host_self(),
        HOST_CPU_LOAD_INFO,
        (host_info_t)&cpu_info,
        &cpu_count
    );

    if (cpu_result == KERN_SUCCESS) {
        sample->cpu_user_ticks = cpu_info.cpu_ticks[CPU_STATE_USER];
        sample->cpu_nice_ticks = cpu_info.cpu_ticks[CPU_STATE_NICE];
        sample->cpu_system_ticks = cpu_info.cpu_ticks[CPU_STATE_SYSTEM];
        sample->cpu_idle_ticks = cpu_info.cpu_ticks[CPU_STATE_IDLE];
    }

    vm_statistics64_data_t vm_info;
    mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
    kern_return_t vm_result = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&vm_info,
        &vm_count
    );

    vm_size_t page_size = 0;
    host_page_size(mach_host_self(), &page_size);

    if (vm_result == KERN_SUCCESS) {
        sample->free_memory = pb_page_bytes(vm_info.free_count, page_size);
        sample->active_memory = pb_page_bytes(vm_info.active_count, page_size);
        sample->inactive_memory = pb_page_bytes(vm_info.inactive_count, page_size);
        sample->wired_memory = pb_page_bytes(vm_info.wire_count, page_size);
        sample->compressed_memory = pb_page_bytes(vm_info.compressor_page_count, page_size);
        sample->page_ins = vm_info.pageins;
        sample->page_outs = vm_info.pageouts;
    }

    uint64_t memory_size = 0;
    size_t memory_size_len = sizeof(memory_size);
    if (sysctlbyname("hw.memsize", &memory_size, &memory_size_len, NULL, 0) == 0) {
        sample->total_memory = memory_size;
    }

    int logical_cpu_count = 0;
    size_t logical_cpu_len = sizeof(logical_cpu_count);
    if (sysctlbyname("hw.logicalcpu", &logical_cpu_count, &logical_cpu_len, NULL, 0) == 0) {
        sample->logical_cpu_count = (int32_t)logical_cpu_count;
    }

    struct xsw_usage swap_usage;
    size_t swap_len = sizeof(swap_usage);
    if (sysctlbyname("vm.swapusage", &swap_usage, &swap_len, NULL, 0) == 0) {
        sample->swap_used = swap_usage.xsu_used;
        sample->swap_total = swap_usage.xsu_total;
    }

    double loads[3] = {0, 0, 0};
    if (getloadavg(loads, 3) == 3) {
        sample->load_average_1 = loads[0];
        sample->load_average_5 = loads[1];
        sample->load_average_15 = loads[2];
    }

    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) == 0) {
        for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_LINK) {
                continue;
            }

            if ((ifa->ifa_flags & IFF_LOOPBACK) != 0 || (ifa->ifa_flags & IFF_UP) == 0) {
                continue;
            }

            struct if_data *data = (struct if_data *)ifa->ifa_data;
            if (data == NULL) {
                continue;
            }

            sample->network_in_bytes += data->ifi_ibytes;
            sample->network_out_bytes += data->ifi_obytes;
        }
        freeifaddrs(ifaddr);
    }

    return 0;
}

int PBTerminateProcess(int32_t pid, int32_t force) {
    if (pid <= 0) {
        errno = EINVAL;
        return -1;
    }

    int signal_number = force ? SIGKILL : SIGTERM;
    return kill((pid_t)pid, signal_number);
}
