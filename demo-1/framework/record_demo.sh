#!/bin/bash
# Record the demo viewer by taking periodic screenshots and stitching into video.
# Uses wkhtmltoimage (no browser needed) + ffmpeg.
#
# Usage: ./record_demo.sh <output_dir> <duration_secs> <demo_url>

OUTPUT_DIR="${1:?Usage: record_demo.sh <output_dir> <duration> <url>}"
DURATION="${2:-120}"
DEMO_URL="${3:-http://127.0.0.1:8766/demo.html}"
FPS=2  # screenshots per second (2 is plenty for SVG updates)
FRAMES_DIR="$OUTPUT_DIR/frames"
mkdir -p "$FRAMES_DIR"

echo "   📹 Recording: $DEMO_URL for ${DURATION}s @ ${FPS}fps"

INTERVAL=$(python3 -c "print(1.0/$FPS)")
FRAME=0
END=$((SECONDS + DURATION))

while [ $SECONDS -lt $END ]; do
    PADDED=$(printf "%06d" $FRAME)
    wkhtmltoimage --quiet --quality 80 --width 1920 --height 1080 \
        "$DEMO_URL" "$FRAMES_DIR/frame_${PADDED}.jpg" 2>/dev/null &
    FRAME=$((FRAME + 1))
    sleep "$INTERVAL"
done
wait

# Stitch into video
FRAME_COUNT=$(ls "$FRAMES_DIR"/frame_*.jpg 2>/dev/null | wc -l)
if [ "$FRAME_COUNT" -gt 0 ]; then
    ffmpeg -y -framerate "$FPS" -i "$FRAMES_DIR/frame_%06d.jpg" \
        -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p \
        "$OUTPUT_DIR/demo.mp4" 2>/dev/null
    echo "   📹 Video: $OUTPUT_DIR/demo.mp4 ($FRAME_COUNT frames)"
else
    echo "   ⚠️ No frames captured"
fi
