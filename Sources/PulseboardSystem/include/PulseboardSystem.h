#ifndef PULSEBOARD_SYSTEM_H
#define PULSEBOARD_SYSTEM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PB_PROCESS_NAME_LENGTH 256
#define PB_PROCESS_PATH_LENGTH 4096

typedef struct {
    int32_t pid;
    int32_t ppid;
    uint32_t uid;
    int32_t status;
    int32_t thread_count;
    uint64_t resident_size;
    uint64_t virtual_size;
    uint64_t total_user_time_ns;
    uint64_t total_system_time_ns;
    uint64_t start_time_sec;
    uint64_t start_time_usec;
    char name[PB_PROCESS_NAME_LENGTH];
    char path[PB_PROCESS_PATH_LENGTH];
} PBProcessSample;

typedef struct {
    uint64_t cpu_user_ticks;
    uint64_t cpu_nice_ticks;
    uint64_t cpu_system_ticks;
    uint64_t cpu_idle_ticks;
    uint64_t total_memory;
    uint64_t free_memory;
    uint64_t active_memory;
    uint64_t inactive_memory;
    uint64_t wired_memory;
    uint64_t compressed_memory;
    uint64_t page_ins;
    uint64_t page_outs;
    uint64_t swap_used;
    uint64_t swap_total;
    uint64_t network_in_bytes;
    uint64_t network_out_bytes;
    double load_average_1;
    double load_average_5;
    double load_average_15;
    int32_t logical_cpu_count;
} PBSystemSample;

int PBProcessCount(void);
int PBListProcesses(PBProcessSample *buffer, size_t capacity);
int PBReadSystem(PBSystemSample *sample);
int PBTerminateProcess(int32_t pid, int32_t force);

#ifdef __cplusplus
}
#endif

#endif
