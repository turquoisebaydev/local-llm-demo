# Demo 3 — Qwen3.5-9B on all GPUs

This demo runs the same Qwen3.5-9B model on all four GPUs with matched context settings for clean comparison.

## Recommended baseline

- Model: `Qwen3.5-9B-Q4_K_M.gguf`
- Context: `-c 131072` on all GPUs
- Parallel slots: `-np 1`
- KV cache quant: `-ctk q4_0 -ctv q4_0`
- Reasoning disabled for throughput consistency: `--reasoning-format none --reasoning-budget 0`

## Service files

- `services/pg1/llama-qwen9-6000.service`
- `services/pg1/llama-qwen9-5090.service`
- `services/turqette/llama-qwen9-4090.service`
- `services/turqette/llama-qwen9-3090.service`
