#!/bin/bash
# Launch 4 subagents — same model (Qwen3.5-27B) on 4 different GPUs
# Each agent gets an isolated HERMES_HOME with a locked config pointing
# to its metrics proxy.  No fallback, no provider resolution magic.
# Captures TTFT, TPS, duration per GPU via metrics proxies.
# Records a video of the demo viewer via periodic screenshots.

set -e

echo "🎬 Starting demo with metrics + video recording..."

DURATION=120  # 2 minutes in seconds
TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/svg_demo_${TIMESTAMP}"
METRICS_DIR="${OUTPUT_DIR}/metrics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
HERMES_AGENT_DIR="$HOME/.hermes/hermes-agent"
DEMO_PORT=8766
mkdir -p "$OUTPUT_DIR" "$METRICS_DIR"

# ── GPU backends (all running Qwen3.5-27B Q4_K_M) ────────────
declare -A GPU_LABEL=( [1]="6000" [2]="5090" [3]="4090" [4]="3090" )
declare -A GPU_BACKEND=(
    [1]="http://10.0.20.9:18080/v1"
    [2]="http://10.0.20.9:18181/v1"
    [3]="http://10.0.20.107:8080/v1"
    [4]="http://10.0.20.107:8081/v1"
)
declare -A PROXY_PORT=( [1]=9101 [2]=9102 [3]=9103 [4]=9104 )

# ── Build isolated HERMES_HOME per agent ──────────────────────
make_agent_home() {
    local idx=$1
    local proxy_url="http://127.0.0.1:${PROXY_PORT[$idx]}"
    local agent_home="$OUTPUT_DIR/agent_home_${GPU_LABEL[$idx]}"
    mkdir -p "$agent_home"
    cat > "$agent_home/config.yaml" <<EOF
model:
  default: Qwen3.5-27B-Q4_K_M.gguf
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

    echo "   Stopping proxies (triggering metric summaries)..."
    for pid in "${PROXY_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    sleep 2

    echo "   Stopping HTTP server..."
    kill $HTTP_PID 2>/dev/null || true

    # Wait for video recorder (it finishes on its own after DURATION)
    if [ -n "$RECORDER_PID" ]; then
        echo "   Waiting for video to finish encoding..."
        wait $RECORDER_PID 2>/dev/null || true
    fi

    wait 2>/dev/null

    # Generate combined report
    echo ""
    echo "📊 Generating combined metrics report..."
    python3 "$FRAMEWORK_DIR/metrics_report.py" "$METRICS_DIR"

    echo ""
    echo "✅ Demo complete!"
    echo "   🎬 Video: $OUTPUT_DIR/demo.mp4"
    echo "   📁 Canvas files: $FRAMEWORK_DIR/canvas[1-4].svg"
    echo "   📊 Metrics: $METRICS_DIR/"
    echo "   📂 Output dir: $OUTPUT_DIR"
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

# ── 2. Start metrics proxies ─────────────────────────────────
echo "   Starting metrics proxies..."
declare -a PROXY_PIDS
for i in 1 2 3 4; do
    python3 "$FRAMEWORK_DIR/metrics_proxy.py" \
        --listen "127.0.0.1:${PROXY_PORT[$i]}" \
        --backend "${GPU_BACKEND[$i]}" \
        --label "${GPU_LABEL[$i]}" \
        --metrics-dir "$METRICS_DIR" &
    PROXY_PIDS+=($!)
done
sleep 1

# ── 3. Start HTTP server for demo viewer ─────────────────────
echo "   Starting demo viewer on :${DEMO_PORT}..."
cd "$FRAMEWORK_DIR"
python3 -m http.server "$DEMO_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
HTTP_PID=$!
cd - >/dev/null
sleep 0.5

# ── 4. Start video recorder ──────────────────────────────────
echo "   Starting video recorder..."
bash "$FRAMEWORK_DIR/record_demo.sh" "$OUTPUT_DIR" "$DURATION" "http://127.0.0.1:${DEMO_PORT}/demo.html" &
RECORDER_PID=$!

# ── 5. Launch 4 agents via isolated homes ─────────────────────
echo "   Launching 4 agents (Qwen3.5-27B on 4 GPUs)..."
declare -a AGENT_PIDS
for i in 1 2 3 4; do
    agent_home=$(make_agent_home $i)
    echo "     Agent $i: ${GPU_LABEL[$i]} → proxy :${PROXY_PORT[$i]} → ${GPU_BACKEND[$i]}"

    HERMES_HOME="$agent_home" OPENAI_API_KEY="not-needed" \
      hermes chat -q "$(cat "$FRAMEWORK_DIR/prompt${i}.txt")" --yolo \
      > "$OUTPUT_DIR/agent_${GPU_LABEL[$i]}.log" 2>&1 &
    AGENT_PIDS+=($!)
done

echo ""
echo "   PIDs: ${AGENT_PIDS[*]}"
echo "   Recording for $DURATION seconds..."
echo "   Metrics: $METRICS_DIR/"
echo "   Agent logs: $OUTPUT_DIR/agent_*.log"

# ── 6. Wait for duration ─────────────────────────────────────
sleep $DURATION
