# Demo 1 — Qwen3.5-27B across 4 GPUs: Iterative SVG Generation

Same model (Qwen3.5-27B Q4_K_M), four different GPUs, same task, 2 minutes each.
Each GPU runs an independent AI agent that iteratively draws an SVG from a text description.

## GPUs

| GPU | VRAM | Context |
|-----|------|---------|
| NVIDIA RTX PRO 6000 (Blackwell) | 48 GB | 131072 |
| NVIDIA GeForce RTX 5090 | 32 GB | 131072 |
| NVIDIA GeForce RTX 4090 | 24 GB | 131072 |
| NVIDIA GeForce RTX 3090 | 24 GB | 131072 |

All running:
- **Model:** Qwen3.5-27B-Q4_K_M.gguf
- **Server:** llama.cpp with `--jinja --chat-template-file qwen3.5_chat_template.jinja`
- **KV cache:** Q4_0 keys + Q4_0 values
- **Thinking:** Disabled via `chat_template_kwargs` proxy (for reliable tool calling)

## Task

Each agent receives the same text prompt and iterates: write SVG → improve → write again → repeat until killed at 2 minutes.

```
You are an SVG artist. Draw a cat on a desk with a laptop, iteratively improving each pass.

WHAT TO DRAW:
- Dark gray wall background, light area at top (window), tan wooden desk
- Cream/tan tabby cat center, white chest, yellow-green eyes, pointed ears (pink inside), gray collar
- Silver MacBook behind cat, dark monitor in background
- Orange cable and white papers on left of desk
- Cat looks serious/focused, like it's working

RULES:
- Your FIRST action must be write_file with a basic SVG. No planning, no analysis. Just write shapes.
- After each write, immediately write an improved version. Never stop.
- Keep each response SHORT. Write the SVG, say what you'll improve next in one sentence, then write again.

ITERATION GUIDE:
Pass 1: Background rect, desk rect, cat body ellipse, basic head circle — just colored shapes
Pass 2: Add eyes, ears, laptop rectangle, monitor outline
Pass 3: Refine cat shape with paths, add whiskers, collar, ear details
Pass 4+: Gradients, shadows, cable, papers, fur texture, expression details
```

## Results

### SVG Output

<table>
<tr>
<td align="center"><strong>RTX PRO 6000</strong><br>(4 iterations)</td>
<td align="center"><strong>RTX 5090</strong><br>(5 iterations)</td>
<td align="center"><strong>RTX 4090</strong><br>(4 iterations)</td>
<td align="center"><strong>RTX 3090</strong><br>(4 iterations)</td>
</tr>
<tr>
<td><img src="results/6000.svg" width="250"></td>
<td><img src="results/5090.svg" width="250"></td>
<td><img src="results/4090.svg" width="250"></td>
<td><img src="results/3090.svg" width="250"></td>
</tr>
</table>

### Performance Metrics

Collected via `nvidia-smi` (power, utilization) and llama.cpp `/slots` (token throughput) polled every 2 seconds during the 2-minute run.

| Metric | RTX PRO 6000 | RTX 5090 | RTX 4090 | RTX 3090 |
|--------|:------------:|:--------:|:--------:|:--------:|
| **Iterations completed** | 4 | **5** | 4 | 4 |
| **TPS (avg)** | 51.3 | **62.5** | 44.0 | 35.3 |
| TPS (median) | 53.0 | 63.3 | 44.2 | 35.3 |
| TPS (max) | 56.3 | 65.6 | 45.0 | 36.8 |
| **Power avg (W)** | **282** | 542 | 346 | 323 |
| Power max (W) | 301 | 603 | 369 | 340 |
| Power idle (W) | 12 | 29 | 14 | 4 |
| GPU utilization (avg) | 88% | 89% | 91% | 93% |
| GPU utilization (max) | 99% | 98% | 98% | 98% |
| VRAM used (MiB) | 19,559 | 19,159 | 18,916 | 18,632 |

### Key Takeaways

- **RTX 5090** is the fastest at 62.5 tok/s average and completed the most iterations (5 vs 4), but draws over 540W average — nearly double the RTX PRO 6000.
- **RTX PRO 6000** delivers 51.3 tok/s at only 282W average — best **tokens per watt** efficiency by a significant margin.
- **RTX 4090** holds up well at 44 tok/s, competitive with the 6000 on a consumer-tier card.
- **RTX 3090** at 35.3 tok/s shows the generational gap but still completes 4 full iterations in 2 minutes.
- All GPUs saturate at 88-93% utilization, indicating the workload is GPU-bound (not bottlenecked by CPU/memory/network).

### Tokens per Watt

| GPU | tok/s | Avg Power (W) | **Tokens per Watt** |
|-----|------:|:-------------:|:-------------------:|
| RTX PRO 6000 | 51.3 | 282 | **0.182** |
| RTX 5090 | 62.5 | 542 | 0.115 |
| RTX 4090 | 44.0 | 346 | 0.127 |
| RTX 3090 | 35.3 | 323 | 0.109 |

The RTX PRO 6000 delivers **58% more tokens per watt** than the 5090 and **44% more** than the 4090.

## Infrastructure

```
  Agent 1 ──► nothink proxy ──► llama.cpp (RTX PRO 6000)
  Agent 2 ──► nothink proxy ──► llama.cpp (RTX 5090)
  Agent 3 ──► nothink proxy ──► llama.cpp (RTX 4090)
  Agent 4 ──► nothink proxy ──► llama.cpp (RTX 3090)
                                     │
  metrics_collector.py ── polls nvidia-smi + /slots ─┘
```

- **Agent orchestration:** [Hermes Agent](https://github.com/nousresearch/hermes-agent) CLI with isolated config per agent
- **NoThink proxy:** Injects `chat_template_kwargs: {enable_thinking: false}` into each request for reliable tool calling
- **Metrics:** Sidecar polling `nvidia-smi` and llama.cpp `/slots` every 2s

## Reproduce

See `framework/` for the launcher, proxies, metrics collector, and live viewer.
See `services/` for the systemd unit files.
