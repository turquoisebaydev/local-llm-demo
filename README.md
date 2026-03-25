# local-llm-demo

Benchmarks and demos for local multi-GPU llama.cpp inference.

## Demo 1 — Same Model, Different GPUs

Qwen3.5-27B Q4_K_M running on four GPUs simultaneously (RTX PRO 6000 Max-Q, RTX 5090, RTX 4090, RTX 3090). Each GPU runs an independent agent that iteratively generates SVG artwork using native vision. Compares tokens/sec, power draw, and output quality.

**→ [Demo 1 Results](demo-1/)**

## Demo 2 — Highest Practical Model per GPU

Each GPU runs the largest Qwen3.5 it can fit: 122B-A10B Q4_K_M on the RTX PRO 6000 Max-Q (96GB), 27B Q5_K_M on the 5090, 27B Q4_K_M on the 4090/3090. Same SVG task with native vision, comparing how model size affects output quality and throughput.

**→ [Demo 2 Results](demo-2/)**

## Demo 3 — 9B on All GPUs

Qwen3.5-9B Q4_K_M across all four GPUs at 131072 context with native vision. Tests how a smaller model performs — dramatically faster tok/s but lower GPU utilization.

**→ [Demo 3 Results](demo-3/)**

## Demo 4 — Split Models across GPU Pairs

Tensor-parallel splits: 122B-A10B UD-Q6_K_XL across RTX PRO 6000 Max-Q + RTX 5090 (3:1 split), and 27B Q6_K across RTX 4090 + RTX 3090 (1:1 split). Tests multi-GPU inference overhead and scaling with native vision.

**→ [Demo 4 Results](demo-4/)**
