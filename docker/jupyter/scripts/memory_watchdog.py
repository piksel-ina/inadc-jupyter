#!/usr/bin/env python3
import os
import signal
import sys
import time

import psutil

THRESHOLD = float(os.environ.get("MEM_WATCHDOG_THRESHOLD", "0.90"))
CHECK_INTERVAL = int(os.environ.get("MEM_WATCHDOG_INTERVAL", "5"))
COOLDOWN = int(os.environ.get("MEM_WATCHDOG_COOLDOWN", "30"))

LOG_PREFIX = "memory_watchdog"


def get_mem_limit():
    mem_limit = os.environ.get("MEM_LIMIT")
    if mem_limit:
        try:
            return int(mem_limit)
        except ValueError:
            pass

    try:
        with open("/sys/fs/cgroup/memory.max" if os.path.exists("/sys/fs/cgroup/memory.max") else "/sys/fs/cgroup/memory/memory.limit_in_bytes") as f:
            val = int(f.read().strip())
            return val if val < 9223372036854771712 else None
    except (FileNotFoundError, ValueError):
        pass

    return psutil.virtual_memory().total


def get_mem_usage():
    try:
        if os.path.exists("/sys/fs/cgroup/memory.current"):
            with open("/sys/fs/cgroup/memory.current") as f:
                return int(f.read().strip())
        if os.path.exists("/sys/fs/cgroup/memory/memory.usage_in_bytes"):
            with open("/sys/fs/cgroup/memory/memory.usage_in_bytes") as f:
                return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        pass

    return psutil.virtual_memory().used


def find_kernel_pids():
    kernels = []
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            cmdline = " ".join(proc.info["cmdline"] or [])
            if "ipykernel_launcher" in cmdline:
                kernels.append((proc.info["pid"], proc))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return kernels


def kill_kernels():
    kernels = find_kernel_pids()
    if not kernels:
        return False

    for pid, proc in kernels:
        try:
            print(f"{LOG_PREFIX}: sending SIGTERM to kernel PID {pid}", flush=True)
            proc.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    gone, alive = psutil.wait_procs([p for _, p in kernels], timeout=5)
    for proc in alive:
        try:
            print(f"{LOG_PREFIX}: sending SIGKILL to stubborn PID {proc.pid}", flush=True)
            proc.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    return True


def main():
    mem_limit = get_mem_limit()
    if not mem_limit:
        print(f"{LOG_PREFIX}: cannot determine memory limit, exiting", flush=True)
        sys.exit(1)

    threshold_bytes = int(mem_limit * THRESHOLD)
    print(
        f"{LOG_PREFIX}: monitoring memory — limit {mem_limit >> 20}Mi, "
        f"threshold {THRESHOLD:.0%} ({threshold_bytes >> 20}Mi), "
        f"check every {CHECK_INTERVAL}s",
        flush=True,
    )

    last_kill_time = 0

    while True:
        try:
            usage = get_mem_usage()
            if usage > threshold_bytes:
                now = time.time()
                if now - last_kill_time < COOLDOWN:
                    time.sleep(CHECK_INTERVAL)
                    continue

                pct = usage / mem_limit
                print(
                    f"{LOG_PREFIX}: memory at {pct:.1%} ({usage >> 20}Mi / {mem_limit >> 20}Mi) — killing kernels",
                    flush=True,
                )
                if kill_kernels():
                    last_kill_time = now
        except Exception as e:
            print(f"{LOG_PREFIX}: error: {e}", flush=True)

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
