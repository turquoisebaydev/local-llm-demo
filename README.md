# local-llm-demo

Demo configs for local multi-GPU llama.cpp layouts.

## Demo 1

Qwen3.5-27B Q4_K_M loaded across all four GPUs:

- pg1 RTX PRO 6000 (`-c 262144`, port `18080`)
- pg1 RTX 5090 (`-c 196608`, port `18181`)
- turqette RTX 4090 (`-c 131072`, port `8080`)
- turqette RTX 3090 (`-c 131072`, port `8081`)

See `demo-1/` for exact settings and service files.
