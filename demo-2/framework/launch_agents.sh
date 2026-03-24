#!/bin/bash
# Launch 4 subagents with different models + metrics collection
# Auto-records demo video (headless, automatic)
# Captures TTFT, TPS, duration per model via metrics proxies

set -e

echo "🎬 Starting demo with video recording + metrics..."

DURATION=120  # 2 minutes in seconds
TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/svg_demo_${TIMESTAMP}"
METRICS_DIR="${OUTPUT_DIR}/metrics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
mkdir -p "$OUTPUT_DIR" "$METRICS_DIR"

# ── Cleanup function ──────────────────────────────────────────
cleanup() {
    echo ""
    echo "   Stopping agents..."
    kill $PID1 $PID2 $PID3 $PID4 2>/dev/null || true

    echo "   Stopping proxies (triggering metric summaries)..."
    kill -TERM $PROXY1_PID $PROXY2_PID $PROXY3_PID $PROXY4_PID 2>/dev/null || true
    sleep 2

    echo "   Stopping recording..."
    kill $FFMPEG_PID $XVFB_PID 2>/dev/null || true
    wait 2>/dev/null

    # Generate combined report
    echo ""
    echo "📊 Generating combined metrics report..."
    python3 "$FRAMEWORK_DIR/metrics_report.py" "$METRICS_DIR"

    echo ""
    echo "✅ Demo complete!"
    echo "   🎬 Video: $OUTPUT_DIR/demo.mp4"
    echo "   📸 Initial screenshot: $OUTPUT_DIR/initial.png"
    echo "   📁 Canvas files: $FRAMEWORK_DIR/canvas[1-4].svg"
    echo "   📊 Metrics: $METRICS_DIR/"
    echo "   📂 Output dir: $OUTPUT_DIR"
}
trap cleanup EXIT

# ── 1. Start metrics proxies ─────────────────────────────────
# Each proxy intercepts API calls and logs TTFT + TPS
echo "   Starting metrics proxies..."

python3 "$FRAMEWORK_DIR/metrics_proxy.py" \
    --listen 127.0.0.1:9101 \
    --backend "http://10.0.20.9:11434/qwen27/v1" \
    --label "27b" \
    --metrics-dir "$METRICS_DIR" &
PROXY1_PID=$!

python3 "$FRAMEWORK_DIR/metrics_proxy.py" \
    --listen 127.0.0.1:9102 \
    --backend "http://10.0.20.9:11434/qwen9/v1" \
    --label "9b" \
    --metrics-dir "$METRICS_DIR" &
PROXY2_PID=$!

python3 "$FRAMEWORK_DIR/metrics_proxy.py" \
    --listen 127.0.0.1:9103 \
    --backend "http://10.0.20.9:11434/qwen122/v1" \
    --label "122b" \
    --metrics-dir "$METRICS_DIR" &
PROXY3_PID=$!

# Anthropic proxy — passes through to real API
python3 "$FRAMEWORK_DIR/metrics_proxy.py" \
    --listen 127.0.0.1:9104 \
    --backend "https://api.anthropic.com/v1" \
    --label "opus" \
    --metrics-dir "$METRICS_DIR" &
PROXY4_PID=$!

sleep 1  # Let proxies start

# ── 2. Start virtual display (headless) ──────────────────────
echo "   Setting up virtual display..."
Xvfb :99 -screen 0 1920x1080x24 &
XVFB_PID=$!
export DISPLAY=:99

# ── 3. Start FFmpeg recording ────────────────────────────────
echo "   Starting FFmpeg recording..."
ffmpeg -f x11grab -r 30 -i :99 -c:v libx264 -preset fast -crf 20 \
  "$OUTPUT_DIR/demo.mp4" -y 2>/dev/null &
FFMPEG_PID=$!

# ── 4. Open demo page in browser (for the recording) ────────
echo "   Opening demo page..."
timeout 10 chromium --headless --disable-gpu --no-sandbox \
  --virtual-time-budget=60000 \
  --screenshot="$OUTPUT_DIR/initial.png" \
  "http://10.0.20.107:8766/demo.html" 2>/dev/null &

# ── 5. Launch 4 agents via proxies ───────────────────────────
# Agents point to local proxy ports instead of real backends
echo "   Launching 4 agents..."

HERMES_INFERENCE_PROVIDER=custom OPENAI_BASE_URL="http://127.0.0.1:9101" \
  hermes chat -q "$(cat $FRAMEWORK_DIR/prompt1.txt)" --yolo &
PID1=$!

HERMES_INFERENCE_PROVIDER=custom OPENAI_BASE_URL="http://127.0.0.1:9102" \
  hermes chat -q "$(cat $FRAMEWORK_DIR/prompt2.txt)" --yolo &
PID2=$!

HERMES_INFERENCE_PROVIDER=custom OPENAI_BASE_URL="http://127.0.0.1:9103" \
  hermes chat -q "$(cat $FRAMEWORK_DIR/prompt3.txt)" --yolo &
PID3=$!

ANTHROPIC_BASE_URL="http://127.0.0.1:9104" HERMES_INFERENCE_PROVIDER=anthropic \
  hermes chat -q "$(cat $FRAMEWORK_DIR/prompt4.txt)" --yolo &
PID4=$!

echo "   Agents: PID1=$PID1(27b) PID2=$PID2(9b) PID3=$PID3(122b) PID4=$PID4(opus)"
echo "   Recording for $DURATION seconds..."
echo "   Metrics logging to: $METRICS_DIR/"

# ── 6. Wait for duration ─────────────────────────────────────
sleep $DURATION
