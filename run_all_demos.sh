#!/bin/bash
# Automation script: finish demo-2 metrics, run demo-3 & demo-4, write READMEs, commit all
set -e
cd /home/turq/dev/local-llm-demo

DEMO2_TMPDIR=$(ls -td /tmp/svg_demo_* 2>/dev/null | head -1)

############################################
# HELPER: Extract metrics from JSONL files
############################################
extract_metrics() {
    local metrics_dir="$1"
    python3 - "$metrics_dir" <<'PYEOF'
import json, sys, statistics, os
from pathlib import Path

metrics_dir = Path(sys.argv[1])
labels = sorted([f.stem for f in metrics_dir.glob("*.jsonl")])

for label in labels:
    records = []
    with open(metrics_dir / f"{label}.jsonl") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    
    power = [r["power_w"] for r in records if r.get("power_w")]
    util = [r["util_pct"] for r in records if r.get("util_pct") is not None]
    tps_vals = [r["tps"] for r in records if r.get("tps")]
    mem = [r["mem_mib"] for r in records if r.get("mem_mib")]
    final_turns = records[-1]["turns"] if records else 0
    
    # Get idle power (first 5 samples or min)
    idle_power = min(power[:5]) if len(power) >= 5 else (min(power) if power else 0)
    
    print(f"LABEL:{label}")
    print(f"TURNS:{final_turns}")
    print(f"TPS_AVG:{round(statistics.mean(tps_vals), 1) if tps_vals else 'N/A'}")
    print(f"TPS_MEDIAN:{round(statistics.median(tps_vals), 1) if tps_vals else 'N/A'}")
    print(f"TPS_MAX:{round(max(tps_vals), 1) if tps_vals else 'N/A'}")
    print(f"POWER_AVG:{round(statistics.mean(power)) if power else 'N/A'}")
    print(f"POWER_MAX:{round(max(power)) if power else 'N/A'}")
    print(f"POWER_IDLE:{round(idle_power) if power else 'N/A'}")
    print(f"UTIL_AVG:{round(statistics.mean(util)) if util else 'N/A'}%")
    print(f"UTIL_MAX:{round(max(util)) if util else 'N/A'}%")
    print(f"MEM_MIB:{round(max(mem)) if mem else 'N/A'}")
    print(f"---")
PYEOF
}

############################################
# Wait for demo-2 to finish
############################################
echo "=== Waiting for demo-2 to finish ==="
while ps aux | grep -v grep | grep -q "launch_agents.sh"; do
    sleep 10
    echo "  Still running... $(date +%H:%M:%S)"
done
echo "Demo-2 finished!"
sleep 2

echo "=== Demo-2 Metrics ==="
extract_metrics "$DEMO2_TMPDIR/metrics"

# Copy SVG results
cp demo-2/framework/canvas1.svg demo-2/results/6000-122b.svg
cp demo-2/framework/canvas2.svg demo-2/results/5090-27b-q5.svg
cp demo-2/framework/canvas3.svg demo-2/results/4090-27b-q4.svg
cp demo-2/framework/canvas4.svg demo-2/results/3090-27b-q4.svg

echo ""
echo "=== Deploying Demo-3 services ==="

# Deploy demo-3 services on pg1
ssh turq@10.0.20.9 "mkdir -p ~/.config/systemd/user/"
scp demo-3/services/pg1/*.service turq@10.0.20.9:~/.config/systemd/user/
ssh turq@10.0.20.9 "systemctl --user daemon-reload && systemctl --user enable --now llama-qwen9-6000.service llama-qwen9-5090.service"

# Deploy demo-3 services on turqette (local)
cp demo-3/services/turqette/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now llama-qwen9-4090.service llama-qwen9-3090.service

echo "Waiting for demo-3 services to become healthy..."
for i in $(seq 1 60); do
    ALL_OK=true
    for url in "http://10.0.20.9:19080/health" "http://10.0.20.9:19181/health" "http://10.0.20.107:9080/health" "http://10.0.20.107:9081/health"; do
        STATUS=$(curl -s --max-time 3 "$url" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
        if [ "$STATUS" != "ok" ]; then
            ALL_OK=false
            break
        fi
    done
    if $ALL_OK; then
        echo "  All demo-3 backends healthy!"
        break
    fi
    echo "  Waiting... ($i/60)"
    sleep 10
done

# Kill leftover processes
pkill -f 'nothink_proxy|metrics_collector|hermes chat' 2>/dev/null || true
sleep 2
fuser -k 9101/tcp 9102/tcp 9103/tcp 9104/tcp 2>/dev/null || true
sleep 1

echo ""
echo "=== Running Demo-3 (10 min) ==="
cd demo-3/framework && HOST_A=10.0.20.9 HOST_B=10.0.20.107 DURATION=600 bash launch_agents.sh 2>&1 &
DEMO3_PID=$!
wait $DEMO3_PID || true
cd /home/turq/dev/local-llm-demo

DEMO3_TMPDIR=$(ls -td /tmp/svg_demo3_* 2>/dev/null | head -1)
echo "=== Demo-3 Metrics ==="
extract_metrics "$DEMO3_TMPDIR/metrics"

# Copy SVG results
mkdir -p demo-3/results
cp demo-3/framework/canvas1.svg demo-3/results/6000.svg
cp demo-3/framework/canvas2.svg demo-3/results/5090.svg
cp demo-3/framework/canvas3.svg demo-3/results/4090.svg
cp demo-3/framework/canvas4.svg demo-3/results/3090.svg
cp demo-3/framework/reference.jpg demo-3/results/reference.jpg

echo ""
echo "=== Stopping Demo-3 services, deploying Demo-4 ==="

# Stop demo-3 services to free GPUs
ssh turq@10.0.20.9 "systemctl --user stop llama-qwen9-6000.service llama-qwen9-5090.service" || true
systemctl --user stop llama-qwen9-4090.service llama-qwen9-3090.service || true

# Also stop demo-1/demo-2 services that may conflict
ssh turq@10.0.20.9 "systemctl --user stop llama-qwen27-6000.service llama-qwen27-5090.service llama-qwen122-6000.service 2>/dev/null" || true
systemctl --user stop llama-qwen27-4090.service llama-qwen27-3090.service 2>/dev/null || true

# Deploy demo-4 services
scp demo-4/services/pg1/*.service turq@10.0.20.9:~/.config/systemd/user/
ssh turq@10.0.20.9 "systemctl --user daemon-reload && systemctl --user enable --now llama-demo4-122b-q6-split.service"

cp demo-4/services/turqette/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now llama-demo4-27b-q6-split.service

echo "Waiting for demo-4 services to become healthy..."
for i in $(seq 1 90); do
    ALL_OK=true
    for url in "http://10.0.20.9:18084/health" "http://10.0.20.107:8084/health"; do
        STATUS=$(curl -s --max-time 3 "$url" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
        if [ "$STATUS" != "ok" ]; then
            ALL_OK=false
            break
        fi
    done
    if $ALL_OK; then
        echo "  All demo-4 backends healthy!"
        break
    fi
    echo "  Waiting... ($i/90)"
    sleep 10
done

# Kill leftover processes
pkill -f 'nothink_proxy|metrics_collector|hermes chat' 2>/dev/null || true
sleep 2
fuser -k 9101/tcp 9102/tcp 9103/tcp 9104/tcp 2>/dev/null || true
sleep 1

echo ""
echo "=== Running Demo-4 (10 min) ==="
cd demo-4/framework && HOST_A=10.0.20.9 HOST_B=10.0.20.107 DURATION=600 bash launch_agents.sh 2>&1 &
DEMO4_PID=$!
wait $DEMO4_PID || true
cd /home/turq/dev/local-llm-demo

DEMO4_TMPDIR=$(ls -td /tmp/svg_demo4_* 2>/dev/null | head -1)
echo "=== Demo-4 Metrics ==="
extract_metrics "$DEMO4_TMPDIR/metrics"

# Copy SVG results
mkdir -p demo-4/results
cp demo-4/framework/canvas1.svg demo-4/results/122b-q6.svg
cp demo-4/framework/canvas2.svg demo-4/results/27b-q6.svg
cp demo-4/framework/reference.jpg demo-4/results/reference.jpg

echo ""
echo "=== All demos complete! ==="
echo "Demo-2 metrics dir: $DEMO2_TMPDIR/metrics"
echo "Demo-3 metrics dir: $DEMO3_TMPDIR/metrics"
echo "Demo-4 metrics dir: $DEMO4_TMPDIR/metrics"

# Re-enable demo-1/2 services
ssh turq@10.0.20.9 "systemctl --user start llama-qwen122-6000.service llama-qwen27-5090.service 2>/dev/null" || true
systemctl --user start llama-qwen27-4090.service llama-qwen27-3090.service 2>/dev/null || true

echo "DONE - metrics saved. Write READMEs and commit manually with the numbers."
