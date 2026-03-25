#!/usr/bin/env python3
"""
Generate a combined metrics report from all model proxy JSONL files.
Prints a formatted table and writes a combined JSON summary.

Usage:
    python3 metrics_report.py /path/to/metrics_dir
"""

import json
import statistics
import sys
from pathlib import Path


def calc_stats(vals):
    if not vals:
        return {"min": "-", "max": "-", "median": "-", "avg": "-", "count": 0}
    return {
        "min": round(min(vals), 1),
        "max": round(max(vals), 1),
        "median": round(statistics.median(vals), 1),
        "avg": round(statistics.mean(vals), 1),
        "count": len(vals),
    }


def load_metrics(metrics_dir: Path) -> dict:
    """Load all .jsonl files and compute per-model stats."""
    results = {}
    for jsonl_file in sorted(metrics_dir.glob("*.jsonl")):
        label = jsonl_file.stem
        records = []
        with open(jsonl_file) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        records.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue

        if not records:
            results[label] = {"request_count": 0}
            continue

        # Filter to chat completion requests only
        chat_reqs = [r for r in records if "/chat/completions" in r.get("path", "")]

        ttfts = [r["ttft_ms"] for r in chat_reqs if r.get("ttft_ms") is not None]
        tps_vals = [r["tps"] for r in chat_reqs if r.get("tps") is not None and r["tps"] > 0]
        durations = [r["duration_ms"] for r in chat_reqs if r.get("duration_ms") is not None]
        total_completion = sum(r.get("completion_tokens", 0) or 0 for r in chat_reqs)
        total_prompt = sum(r.get("prompt_tokens", 0) or 0 for r in chat_reqs)

        results[label] = {
            "request_count": len(chat_reqs),
            "total_completion_tokens": total_completion,
            "total_prompt_tokens": total_prompt,
            "ttft_ms": calc_stats(ttfts),
            "tps": calc_stats(tps_vals),
            "duration_ms": calc_stats(durations),
        }

    return results


def print_report(results: dict):
    """Print a formatted comparison table."""
    labels = list(results.keys())
    if not labels:
        print("No metrics data found.")
        return

    print("")
    print("=" * 80)
    print("  📊 MODEL PERFORMANCE COMPARISON")
    print("=" * 80)

    # Header
    col_w = 14
    header = f"{'Metric':<22}"
    for label in labels:
        header += f"{label:>{col_w}}"
    print(header)
    print("-" * (22 + col_w * len(labels)))

    # Requests
    row = f"{'Requests':<22}"
    for label in labels:
        r = results[label]
        row += f"{r.get('request_count', 0):>{col_w}}"
    print(row)

    # Total tokens
    row = f"{'Completion tokens':<22}"
    for label in labels:
        r = results[label]
        row += f"{r.get('total_completion_tokens', 0):>{col_w},}"
    print(row)

    row = f"{'Prompt tokens':<22}"
    for label in labels:
        r = results[label]
        row += f"{r.get('total_prompt_tokens', 0):>{col_w},}"
    print(row)

    print("")

    # TTFT section
    print("  ⏱️  Time to First Token (ms)")
    print("  " + "-" * (20 + col_w * len(labels)))
    for stat in ["min", "max", "median", "avg"]:
        row = f"  {stat.upper():<20}"
        for label in labels:
            r = results[label]
            val = r.get("ttft_ms", {}).get(stat, "-")
            row += f"{val:>{col_w}}"
        print(row)

    print("")

    # TPS section
    print("  🚀 Tokens Per Second")
    print("  " + "-" * (20 + col_w * len(labels)))
    for stat in ["min", "max", "median", "avg"]:
        row = f"  {stat.upper():<20}"
        for label in labels:
            r = results[label]
            val = r.get("tps", {}).get(stat, "-")
            row += f"{val:>{col_w}}"
        print(row)

    print("")

    # Duration section
    print("  ⏳ Request Duration (ms)")
    print("  " + "-" * (20 + col_w * len(labels)))
    for stat in ["min", "max", "median", "avg"]:
        row = f"  {stat.upper():<20}"
        for label in labels:
            r = results[label]
            val = r.get("duration_ms", {}).get(stat, "-")
            row += f"{val:>{col_w}}"
        print(row)

    print("")
    print("=" * 80)
    print(f"  Note: TTFT from llama.cpp timings (exact); Anthropic TTFT unavailable")
    print(f"        TPS for Anthropic estimated from total duration (includes network)")
    print("=" * 80)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <metrics_dir>")
        sys.exit(1)

    metrics_dir = Path(sys.argv[1])
    if not metrics_dir.exists():
        print(f"Metrics directory not found: {metrics_dir}")
        sys.exit(1)

    results = load_metrics(metrics_dir)
    print_report(results)

    # Save combined summary
    summary_path = metrics_dir / "combined_report.json"
    summary_path.write_text(json.dumps(results, indent=2))
    print(f"\n  💾 Full report saved to: {summary_path}")


if __name__ == "__main__":
    main()
