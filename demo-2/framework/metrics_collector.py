#!/usr/bin/env python3
"""
Sidecar metrics collector — polls nvidia-smi for power/utilization and
llama.cpp /slots for token counts and timings.

Usage:
    python3 metrics_collector.py \
        --config '6000=pg1:0:18080,5090=pg1:1:18181,4090=local:0:8080,3090=local:1:8081' \
        --pg1-host turq@10.0.20.9 \
        --metrics-dir ./metrics --interval 2 --duration 120
"""

import argparse
import json
import os
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen


def poll_nvidia_smi(host=None):
    """Poll nvidia-smi, returns {gpu_index: {power_w, util_pct, mem_mib}}."""
    cmd = "nvidia-smi --query-gpu=index,power.draw,utilization.gpu,memory.used --format=csv,noheader,nounits"
    if host:
        cmd = f"ssh {host} '{cmd}'"
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        gpus = {}
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 4:
                idx = int(parts[0])
                gpus[idx] = {
                    "power_w": float(parts[1]),
                    "util_pct": float(parts[2]),
                    "mem_mib": float(parts[3]),
                }
        return gpus
    except Exception:
        return {}


def poll_slots(base_url):
    """Poll llama.cpp /slots endpoint for token counts."""
    try:
        resp = urlopen(f"{base_url}/slots", timeout=3)
        data = json.loads(resp.read())
        if data and isinstance(data, list):
            slot = data[0]
            return {
                "n_decoded": slot.get("next_token", [{}])[0].get("n_decoded", 0),
                "is_processing": slot.get("is_processing", False),
                "id_task": slot.get("id_task", 0),
            }
    except Exception:
        pass
    return None


def calc_stats(vals):
    if not vals:
        return {"min": None, "max": None, "median": None, "avg": None, "count": 0}
    return {
        "min": round(min(vals), 2),
        "max": round(max(vals), 2),
        "median": round(statistics.median(vals), 2),
        "avg": round(statistics.mean(vals), 2),
        "count": len(vals),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True,
                        help="label=host_type:gpu_idx:port,... host_type is 'pg1' or 'local'")
    parser.add_argument("--pg1-host", default="turq@10.0.20.9")
    parser.add_argument("--metrics-dir", default="./metrics")
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--duration", type=int, default=120)
    args = parser.parse_args()

    # Parse config: label=host_type:gpu_idx:port
    gpus = {}
    for pair in args.config.split(","):
        label, spec = pair.split("=", 1)
        host_type, gpu_idx, port = spec.split(":")
        if host_type == "pg1":
            base_url = f"http://10.0.20.9:{port}"
            ssh_host = args.pg1_host
        else:
            base_url = f"http://10.0.20.107:{port}"
            ssh_host = None
        gpus[label.strip()] = {
            "host_type": host_type,
            "gpu_idx": int(gpu_idx),
            "port": int(port),
            "base_url": base_url,
            "ssh_host": ssh_host,
        }

    metrics_dir = Path(args.metrics_dir)
    metrics_dir.mkdir(parents=True, exist_ok=True)
    jsonl_files = {label: open(metrics_dir / f"{label}.jsonl", "w") for label in gpus}

    print(f"📊 Collecting metrics from {len(gpus)} GPUs every {args.interval}s for {args.duration}s")

    # Track previous task IDs for TPS estimation
    prev_task = {label: None for label in gpus}
    prev_decoded = {label: 0 for label in gpus}
    prev_time = {label: time.time() for label in gpus}

    start = time.time()
    running = True

    def stop(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    # Cache nvidia-smi by host to avoid duplicate SSH calls
    while running and (time.time() - start) < args.duration:
        now = time.time()

        # Poll nvidia-smi once per host
        smi_cache = {}
        host_types = set(g["host_type"] for g in gpus.values())
        for ht in host_types:
            ssh = gpus[next(l for l, g in gpus.items() if g["host_type"] == ht)]["ssh_host"]
            smi_cache[ht] = poll_nvidia_smi(ssh)

        for label, cfg in gpus.items():
            smi = smi_cache.get(cfg["host_type"], {}).get(cfg["gpu_idx"], {})
            slots = poll_slots(cfg["base_url"])

            # Estimate TPS from decoded token delta
            tps = None
            if slots:
                task_id = slots.get("id_task", 0)
                n_decoded = slots.get("n_decoded", 0)
                dt = now - prev_time[label]

                if dt > 0 and prev_task[label] == task_id and n_decoded > prev_decoded[label]:
                    delta_tokens = n_decoded - prev_decoded[label]
                    tps = delta_tokens / dt

                prev_task[label] = task_id
                prev_decoded[label] = n_decoded
                prev_time[label] = now

            entry = {
                "timestamp": now,
                "label": label,
                "power_w": smi.get("power_w"),
                "util_pct": smi.get("util_pct"),
                "mem_mib": smi.get("mem_mib"),
                "tps": round(tps, 2) if tps else None,
                "is_processing": slots.get("is_processing") if slots else None,
                "n_decoded": slots.get("n_decoded") if slots else None,
            }
            jsonl_files[label].write(json.dumps(entry) + "\n")
            jsonl_files[label].flush()

        time.sleep(args.interval)

    # Close and summarize
    for f in jsonl_files.values():
        f.close()

    print("\n" + "=" * 80)
    print("  📊 GPU PERFORMANCE SUMMARY")
    print("=" * 80)

    summary = {}
    for label in gpus:
        records = []
        with open(metrics_dir / f"{label}.jsonl") as f:
            for line in f:
                if line.strip():
                    records.append(json.loads(line))

        power = [r["power_w"] for r in records if r.get("power_w")]
        util = [r["util_pct"] for r in records if r.get("util_pct") is not None]
        tps_vals = [r["tps"] for r in records if r.get("tps")]

        summary[label] = {
            "samples": len(records),
            "power_w": calc_stats(power),
            "util_pct": calc_stats(util),
            "tps": calc_stats(tps_vals),
        }

    # Print table
    labels = list(summary.keys())
    col_w = 14
    header = f"{'Metric':<22}"
    for l in labels:
        header += f"{l:>{col_w}}"
    print(header)
    print("-" * (22 + col_w * len(labels)))

    for section, key, unit in [
        ("⚡ Power Draw (W)", "power_w", ""),
        ("🔥 GPU Utilization (%)", "util_pct", ""),
        ("🚀 Tokens/sec (est)", "tps", ""),
    ]:
        print(f"\n  {section}")
        print("  " + "-" * (20 + col_w * len(labels)))
        for stat in ["min", "max", "median", "avg"]:
            row = f"  {stat.upper():<20}"
            for l in labels:
                val = summary[l].get(key, {}).get(stat, "-")
                row += f"{val:>{col_w}}"
            print(row)

    print("\n" + "=" * 80)

    (metrics_dir / "combined_report.json").write_text(json.dumps(summary, indent=2))
    print(f"  💾 Saved to {metrics_dir}/combined_report.json")


if __name__ == "__main__":
    main()
