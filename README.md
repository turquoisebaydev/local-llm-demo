# local-llm-demo

Benchmarks and demos for local multi-GPU llama.cpp inference.

## Demo 1 — Same Model, Different GPUs

Qwen3.5-27B Q4_K_M running on four GPUs simultaneously (RTX PRO 6000, RTX 5090, RTX 4090, RTX 3090). Each GPU runs an independent agent that iteratively generates SVG artwork from a text description. Compares tokens/sec, power draw, and output quality.

**→ [Demo 1 Results](demo-1/)**
