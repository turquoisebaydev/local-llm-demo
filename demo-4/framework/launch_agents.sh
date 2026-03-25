#!/bin/bash
# Launch 2 subagents for Demo 4 — split models across GPU pairs.
# 122B Q6 split on 6000+5090, 27B Q6 split on 4090+3090.
# Metrics collected via sidecar polling llama.cpp /slots + nvidia-smi.

set -e

echo "🎬 Starting Demo 4 with metrics collection..."

DURATION=${DURATION:-120}  # default 2 minutes, override with env
TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/svg_demo4_${TIMESTAMP}"
METRICS_DIR="${OUTPUT_DIR}/metrics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
mkdir -p "$OUTPUT_DIR" "$METRICS_DIR"

# ── GPU backends / model labels ───────────────────────────────
HOST_A="${HOST_A:-192.168.1.10}"   # Host with RTX PRO 6000 + RTX 5090
HOST_B="${HOST_B:-192.168.1.11}"   # Host with RTX 4090 + RTX 3090

declare -A GPU_LABEL=( [1]="122b-q6" [2]="27b-q6" )
declare -A GPU_MODEL=(
    [1]="Qwen3.5-122B-A10B-UD-Q6_K_XL"
    [2]="Qwen3.5-27B-Q6_K"
)
declare -A GPU_BACKEND=(
    [1]="http://${HOST_A}:18084/v1"
    [2]="http://${HOST_B}:8084/v1"
)
# ── Proxy ports (nothink proxy injects chat_template_kwargs) ──
declare -A PROXY_PORT=( [1]=9101 [2]=9102 )

# ── Build isolated HERMES_HOME per agent ──────────────────────
make_agent_home() {
    local idx=$1
    local proxy_url="http://127.0.0.1:${PROXY_PORT[$idx]}"
    local agent_home="$OUTPUT_DIR/agent_home_${GPU_LABEL[$idx]}"
    mkdir -p "$agent_home"
    cat > "$agent_home/config.yaml" <<EOF
model:
  default: ${GPU_MODEL[$idx]}
  provider: custom
  base_url: ${proxy_url}
agent:
  max_turns: 60
  reasoning_effort: none
_config_version: 10
custom_providers: []
EOF
    # Generate prompt from template with correct vision URL
    sed -e "s|__CANVAS_NUM__|${idx}|g" -e "s|__VISION_URL__|${proxy_url}|g" \
        "$FRAMEWORK_DIR/prompt_template.txt" > "$FRAMEWORK_DIR/prompt${idx}.txt"

    echo "$agent_home"
}

# ── Cleanup function ──────────────────────────────────────────
cleanup() {
    echo ""
    echo "   Stopping agents..."
    for pid in "${AGENT_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done

    echo "   Stopping proxies..."
    for pid in "${PROXY_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done

    echo "   Stopping metrics collector..."
    kill $COLLECTOR_PID 2>/dev/null || true

    echo "   Stopping HTTP server..."
    kill $HTTP_PID 2>/dev/null || true

    wait 2>/dev/null

    # Generate report
    echo ""
    echo "📊 Metrics report:"
    python3 "$FRAMEWORK_DIR/metrics_report.py" "$METRICS_DIR" 2>/dev/null || true

    echo ""
    echo "✅ Demo 4 complete!"
    echo "   📁 Canvas files: $FRAMEWORK_DIR/canvas[1-2].svg"
    echo "   📊 Metrics: $METRICS_DIR/"
    echo "   📂 Output dir: $OUTPUT_DIR"
}
trap cleanup EXIT

# ── 1. Reset canvases ─────────────────────────────────────────
echo "   Resetting canvases..."
for i in 1 2; do
    cat > "$FRAMEWORK_DIR/canvas${i}.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <rect width="800" height="600" fill="#f0f0f0"/>
</svg>
EOF
done

# ── 2. Start nothink proxies ──────────────────────────────────
echo "   Starting nothink proxies..."
declare -a PROXY_PIDS
for i in 1 2; do
    python3 "$FRAMEWORK_DIR/nothink_proxy.py" \
        --listen "127.0.0.1:${PROXY_PORT[$i]}" \
        --backend "${GPU_BACKEND[$i]}" &
    PROXY_PIDS+=($!)
done
sleep 1

# ── 3. Start metrics collector (nvidia-smi + /slots) ─────────
# For split models: 122B uses GPUs 0+1 on pg1, 27B uses GPUs 0+1 on local
echo "   Starting metrics collector..."
python3 "$FRAMEWORK_DIR/metrics_collector.py" \
    --config "6000=pg1:0:18084,5090=pg1:1:18084,4090=local:0:8084,3090=local:1:8084" \
    --metrics-dir "$METRICS_DIR" \
    --interval 2 \
    --duration "$DURATION" &
COLLECTOR_PID=$!

# ── 3b. Start video recorder (optional) ──────────────────────
DEMO_PORT=8766
HTTP_PID=""
RECORDER_PID=""

# ── 4. Launch 2 agents ────────────────────────────────────────
echo "   Launching 2 agents (Demo4 — split models)..."
declare -a AGENT_PIDS
for i in 1 2; do
    agent_home=$(make_agent_home $i)
    echo "     Agent $i: ${GPU_LABEL[$i]} (${GPU_MODEL[$i]}) → ${GPU_BACKEND[$i]}"

    HERMES_HOME="$agent_home" OPENAI_API_KEY="not-needed" \
      hermes chat -q "$(cat "$FRAMEWORK_DIR/prompt${i}.txt")" --yolo \
      > "$OUTPUT_DIR/agent_${GPU_LABEL[$i]}.log" 2>&1 &
    AGENT_PIDS+=($!)
done

echo ""
echo "   PIDs: ${AGENT_PIDS[*]}"
echo "   Running for $DURATION seconds..."
echo "   Agent logs: $OUTPUT_DIR/agent_*.log"

# ── 5. Wait for duration ─────────────────────────────────────
sleep $DURATION
