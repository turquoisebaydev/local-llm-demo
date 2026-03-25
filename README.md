# local-llm-demo

Benchmarks and demos for local multi-GPU llama.cpp inference.

## Demo 1 — Same Model, Different GPUs

Qwen3.5-27B Q4_K_M running on four GPUs simultaneously (RTX PRO 6000 Max-Q, RTX 5090, RTX 4090, RTX 3090). Each GPU runs an independent agent that iteratively generates SVG artwork from a text description. Compares tokens/sec, power draw, and output quality.

**→ [Demo 1 Results](demo-1/)**


## Demo 2 — 27B split baseline

Qwen3.5-27B split by GPU capability (Q5 on pg1, Q4 on turqette).

**→ [Demo 2](demo-2/)**

## Demo 3 — 9B on all GPUs

Qwen3.5-9B Q4_K_M across all four GPUs at 131072 context.

**→ [Demo 3](demo-3/)**

## Demo 4 — split-tier best-fit (Q6 lanes)

Planned split: 122B UD-Q6 on pg1 pair and 27B Q6 on turqette pair.

**→ [Demo 4](demo-4/)**
