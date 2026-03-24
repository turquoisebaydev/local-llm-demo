# Demo 2 — Multi-Agent SVG Reproduction + Performance Metrics

Four AI agents race to reproduce a reference image as SVG.
This Demo 2 profile is the **highest-quality practical per-GPU Qwen3.5 mapping** at 131072 context.
A metrics proxy captures **TTFT**, **TPS**, and **duration** per API call.

## Models

| Agent | GPU | Model | Backend |
|-------|-----|-------|---------|
| 1 | RTX PRO 6000 (pg1, 96GB) | Qwen3.5-27B BF16 | `http://10.0.20.9:18080/v1` |
| 2 | RTX 5090 (pg1) | Qwen3.5-27B Q5_K_M | `http://10.0.20.9:18181/v1` |
| 3 | RTX 4090 (turqette) | Qwen3.5-27B Q4_K_M | `http://10.0.20.107:8080/v1` |
| 4 | RTX 3090 (turqette) | Qwen3.5-27B Q4_K_M | `http://10.0.20.107:8081/v1` |

## How it works

```
  Hermes Agent 1 ──► nothink proxy :9101 ──► pg1:18080/v1  (27B BF16 on 6000)
  Hermes Agent 2 ──► nothink proxy :9102 ──► pg1:18181/v1  (27B Q5 on 5090)
  Hermes Agent 3 ──► nothink proxy :9103 ──► turqette:8080/v1 (27B Q4 on 4090)
  Hermes Agent 4 ──► nothink proxy :9104 ──► turqette:8081/v1 (27B Q4 on 3090)
```

The nothink proxy injects `chat_template_kwargs.enable_thinking=false` for reliable tool-calling behavior during iterative SVG writes.

Collected metrics:

- **TTFT** / **TPS** from llama.cpp timings where available
- **Duration** per request
- **Power/utilization/memory** from `nvidia-smi` sidecar sampling
- **Token progress** from llama.cpp `/slots`

## Prerequisites

```bash
# System packages (for video recording — optional)
apt install xvfb ffmpeg chromium

# Hermes Agent CLI
hermes --version
```

## Quick start

```bash
cd demo-2/framework

# Optional: start the live viewer
python3 -m http.server 8766 --bind 0.0.0.0 &

# Run the demo (2 minutes, auto-records video)
./launch_agents.sh
```

## Output

```
/tmp/svg_demo_<timestamp>/
├── demo.mp4                  # Screen recording (if Xvfb/ffmpeg available)
├── initial.png               # Screenshot at start
└── metrics/
    ├── 27b.jsonl             # Per-request metrics (Agent 1)
    ├── 9b.jsonl              # Per-request metrics (Agent 2)
    ├── 122b.jsonl            # Per-request metrics (Agent 3)
    ├── opus.jsonl            # Per-request metrics (Agent 4)
    ├── *_summary.json        # Per-model summary
    └── combined_report.json  # Combined comparison
```

Final SVGs are written to `framework/canvas[1-4].svg`.

## Metrics report

The report is auto-generated on exit. To re-run manually:

```bash
python3 framework/metrics_report.py /tmp/svg_demo_<timestamp>/metrics
```

Example output:

```
================================================================================
  📊 MODEL PERFORMANCE COMPARISON
================================================================================
Metric                         27b           9b          122b          opus
--------------------------------------------------------------------------------
Requests                        12           18             8             6
Completion tokens            3,200        4,800         1,600         2,400
Prompt tokens                2,400        3,600         1,200         1,800

  ⏱️  Time to First Token (ms)
  ------------------------------------------------------------------
  MIN                        85.2         42.1         320.5             -
  MAX                       450.3        180.6       1,200.4             -
  MEDIAN                    120.5         65.3         580.2             -
  AVG                       148.7         78.4         620.1             -

  🚀 Tokens Per Second
  ------------------------------------------------------------------
  MIN                        28.4         58.2          12.1          35.0
  MAX                        45.6         82.4          18.9          52.0
  MEDIAN                     38.2         72.1          15.4          44.0
  AVG                        37.5         70.8          15.0          43.5
================================================================================
  Note: TTFT from llama.cpp timings (exact); Anthropic TTFT unavailable
        TPS for Anthropic estimated from total duration (includes network)
================================================================================
```

*(Numbers are illustrative — actual results depend on hardware load, context length, and quantization.)*

## Customization

| Setting | Where | Default |
|---------|-------|---------|
| Duration | `launch_agents.sh` → `DURATION` | 120s |
| Models / endpoints | `launch_agents.sh` → proxy `--backend` URLs | See above |
| Reference image | `framework/reference.jpg` | Included |
| Agent prompts | `framework/prompt[1-4].txt` | Identical task |
| Video resolution | `launch_agents.sh` → Xvfb args | 1920×1080 |

## Live viewer

`demo.html` shows 5 panels: reference image + 4 agent canvases (auto-refreshes every 2s).

```bash
cd framework
python3 -m http.server 8766 --bind 0.0.0.0
# Open http://<your-ip>:8766/demo.html
```

## Files

```
demo-2/
├── README.md                 # This file
├── framework/
│   ├── launch_agents.sh      # Main launcher (agents + proxies + recording)
│   ├── metrics_proxy.py      # HTTP proxy capturing TTFT/TPS per request
│   ├── metrics_report.py     # Report generator (table + JSON)
│   ├── demo.html             # 5-panel live viewer
│   ├── reference.jpg         # Target image
│   ├── reference.svg         # Reference SVG (ground truth)
│   ├── prompt[1-4].txt       # Agent prompts
│   └── canvas[1-4].svg       # Agent output (created at runtime)
└── metrics/                  # (placeholder for saved results)
```
