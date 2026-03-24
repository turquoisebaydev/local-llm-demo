# local-llm-demo

Benchmarks and demos for local multi-GPU llama.cpp inference.

## Demo 1 — Same Model, Different GPUs

Qwen3.5-27B Q4_K_M running on four GPUs simultaneously (RTX PRO 6000, RTX 5090, RTX 4090, RTX 3090). Each GPU runs an independent agent that iteratively generates SVG artwork from a text description. Compares tokens/sec, power draw, and output quality.

**→ [Demo 1 Results](demo-1/)**

## Framework

The test framework in [`demo-2/framework/`](demo-2/framework/) provides:
- `launch_agents.sh` — orchestrates 4 parallel Hermes Agent instances
- `nothink_proxy.py` — transparent proxy to disable Qwen3.5 thinking mode
- `metrics_collector.py` — sidecar polling nvidia-smi + llama.cpp `/slots`
- `demo.html` — live side-by-side viewer with flicker-free updates
- `record_demo.sh` — screenshots → video via wkhtmltoimage + ffmpeg
