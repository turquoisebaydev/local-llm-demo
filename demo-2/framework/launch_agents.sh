#!/bin/bash
# Launch 4 subagents for Demo 2 across 4 GPUs.
# Model split: BF16 on 6000, Q5 on 5090, Q4 on turqette (4090/3090).
# Metrics collected via sidecar polling llama.cpp /slots + nvidia-smi.

set -e

echo "🎬 Starting demo with metrics collection..."

DURATION=120  # 2 minutes
TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/svg_demo_${TIMESTAMP}"
METRICS_DIR="${OUTPUT_DIR}/metrics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
mkdir -p "$OUTPUT_DIR" "$METRICS_DIR"

# ── GPU backends / model labels ───────────────────────────────
declare -A GPU_LABEL=( [1]="6000" [2]="5090" [3]="4090" [4]="3090" )
declare -A GPU_MODEL=(
    [1]="Qwen3.5-27B-BF16"
    [2]="Qwen3.5-27B.Q5_K_M.gguf"
    [3]="Qwen3.5-27B-Q4_K_M.gguf"
    [4]="Qwen3.5-27B-Q4_K_M.gguf"
)
declare -A GPU_BACKEND=(
    [1]="http://10.0.20.9:18080/v1"
    [2]="http://10.0.20.9:18181/v1"
    [3]="http://10.0.20.107:8080/v1"
    [4]="http://10.0.20.107:8081/v1"
)
# ── Proxy ports (nothink proxy injects chat_template_kwargs) ──
declare -A PROXY_PORT=( [1]=9101 [2]=9102 [3]=9103 [4]=9104 )

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

    if [ -n "$RECORDER_PID" ]; then
        echo "   Waiting for video to finish..."
        wait $RECORDER_PID 2>/dev/null || true
    fi

    wait 2>/dev/null

    # Generate report
    echo ""
    echo "📊 Metrics report:"
    python3 "$FRAMEWORK_DIR/metrics_report.py" "$METRICS_DIR" 2>/dev/null || true

    echo ""
    echo "✅ Demo complete!"
    echo "   📁 Canvas files: $FRAMEWORK_DIR/canvas[1-4].svg"
    echo "   📊 Metrics: $METRICS_DIR/"
    echo "   📂 Output dir: $OUTPUT_DIR"
    [ -f "$OUTPUT_DIR/demo.mp4" ] && echo "   🎬 Video: $OUTPUT_DIR/demo.mp4"
}
trap cleanup EXIT

# ── 1. Reset canvases ─────────────────────────────────────────
echo "   Resetting canvases..."
for i in 1 2 3 4; do
    cat > "$FRAMEWORK_DIR/canvas${i}.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <rect width="800" height="600" fill="#f0f0f0"/>
</svg>
EOF
done

# ── 2. Start nothink proxies ──────────────────────────────────
echo "   Starting nothink proxies..."
declare -a PROXY_PIDS
for i in 1 2 3 4; do
    python3 "$FRAMEWORK_DIR/nothink_proxy.py" \
        --listen "127.0.0.1:${PROXY_PORT[$i]}" \
        --backend "${GPU_BACKEND[$i]}" &
    PROXY_PIDS+=($!)
done
sleep 1

# ── 3. Start metrics collector (nvidia-smi + /slots) ─────────
echo "   Starting metrics collector..."
python3 "$FRAMEWORK_DIR/metrics_collector.py" \
    --config "6000=local:0:18080,5090=local:1:18181,4090=turqette:0:8080,3090=turqette:1:8081" \
    --turqette-host turqette \
    --metrics-dir "$METRICS_DIR" \
    --interval 2 \
    --duration "$DURATION" &
COLLECTOR_PID=$!

# ── 3. Start video recorder (optional) ───────────────────────
DEMO_PORT=8766
HTTP_PID=""
RECORDER_PID=""
if command -v wkhtmltoimage &>/dev/null; then
    echo "   Starting video recorder..."
    # HTTP server should already be running on 8766 from user
    # If not, start one
    if ! ss -tlnp | grep -q ":${DEMO_PORT}"; then
        cd "$FRAMEWORK_DIR"
        python3 -m http.server "$DEMO_PORT" --bind 0.0.0.0 >/dev/null 2>&1 &
        HTTP_PID=$!
        cd - >/dev/null
        sleep 0.5
    fi
    bash "$FRAMEWORK_DIR/record_demo.sh" "$OUTPUT_DIR" "$DURATION" "http://127.0.0.1:${DEMO_PORT}/demo.html" &
    RECORDER_PID=$!
fi

# ── 4. Launch 4 agents directly at GPU backends ──────────────
echo "   Launching 4 agents (Demo2 model split across 4 GPUs)..."
declare -a AGENT_PIDS
for i in 1 2 3 4; do
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
echo "   Watch live: http://$(hostname -I | awk '{print $1}'):8766/demo.html"

# ── 5. Wait for duration ─────────────────────────────────────
sleep $DURATION
