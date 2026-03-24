# local-llm-demo

Demo configs and benchmarks for local multi-GPU llama.cpp layouts.

## Demos

### Demo 1 — Multi-GPU Context Scaling

Qwen3.5-27B Q4_K_M loaded across all four GPUs simultaneously, each with different context sizes:

| GPU | Host | Context | Port |
|-----|------|---------|------|
| RTX PRO 6000 | pg1 | 262144 | 18080 |
| RTX 5090 | pg1 | 196608 | 18181 |
| RTX 4090 | turqette | 131072 | 8080 |
| RTX 3090 | turqette | 131072 | 8081 |

See [`demo-1/`](demo-1/) for exact settings and systemd service files.

### Demo 2 — Multi-Agent SVG Reproduction + Performance Metrics

Four AI agents (27B, 9B, 122B, Claude Opus) race to reproduce a reference image as SVG. Metrics proxies capture **TTFT**, **TPS**, and **duration** per API call, producing a formatted comparison report.

See [`demo-2/`](demo-2/) for the full framework, launcher, and docs.
