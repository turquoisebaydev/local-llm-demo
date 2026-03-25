# Demo 2 — Highest Practical Qwen3.5 per GPU: Iterative SVG Generation

Each GPU runs the **largest Qwen3.5 model it can fit** at 131K context, same task, 10 minutes each.
Tests how different model sizes and quantizations compare on the same workload.

## GPUs & Models

| GPU | VRAM | Model | Quant |
|-----|------|-------|-------|
| RTX PRO 6000 Max-Q (300W) | 48 GB | Qwen3.5-122B-A10B | Q4_K_M |
| RTX 5090 | 32 GB | Qwen3.5-27B | Q5_K_M |
| RTX 4090 | 24 GB | Qwen3.5-27B | Q4_K_M |
| RTX 3090 | 24 GB | Qwen3.5-27B | Q4_K_M |

All running:
- **Server:** llama.cpp with `--jinja --chat-template-file qwen3.5_chat_template.jinja`
- **Context:** 131072 tokens
- **KV cache:** Q4_0 keys + Q4_0 values
- **Thinking:** Disabled via `chat_template_kwargs` proxy

## Reference Image

<img src="results/reference.jpg" width="300">

## Task

Same as Demo 1 — each agent iteratively draws an SVG reproduction of a cat on a desk, writing and improving in a loop for 10 minutes.

> **Note:** This run used text-description prompts. Vision prompt template is prepared for re-run with native multimodal vision.

## Results

### SVG Output (after 10 minutes)

<table>
<tr>
<td align="center"><strong>RTX PRO 6000 Max-Q</strong><br>122B Q4_K_M<br>(11 iterations)</td>
<td align="center"><strong>RTX 5090</strong><br>27B Q5_K_M<br>(12 iterations)</td>
<td align="center"><strong>RTX 4090</strong><br>27B Q4_K_M<br>(10 iterations)</td>
<td align="center"><strong>RTX 3090</strong><br>27B Q4_K_M<br>(9 iterations)</td>
</tr>
<tr>
<td><img src="results/6000-122b.svg" width="250"></td>
<td><img src="results/5090-27b-q5.svg" width="250"></td>
<td><img src="results/4090-27b-q4.svg" width="250"></td>
<td><img src="results/3090-27b-q4.svg" width="250"></td>
</tr>
</table>

### Performance Metrics

Collected via `nvidia-smi` (power, utilization) and llama.cpp `/slots` (token throughput) polled every 2 seconds during the 10-minute run.

| Metric | RTX PRO 6000 Max-Q (122B) | RTX 5090 (27B Q5) | RTX 4090 (27B Q4) | RTX 3090 (27B Q4) |
|--------|:-------------------------:|:-----------------:|:-----------------:|:-----------------:|
| **Iterations completed** | 11 | **12** | 10 | 9 |
| **TPS (avg)** | — | — | 42.5 | 33.1 |
| TPS (median) | — | — | 42.8 | 33.2 |
| TPS (max) | — | — | 50.6 | 40.1 |
| **Power avg (W)** | **375** | 336 | 374 | 336 |
| Power max (W) | 457 | 343 | 449 | 342 |
| GPU utilization (avg) | 94% | 95% | 94% | 95% |
| GPU utilization (max) | 100% | 100% | 100% | 100% |

*TPS for RTX PRO 6000 and RTX 5090 not captured due to remote `/slots` polling issue — to be fixed in next run.*

### Key Takeaways

- **122B on RTX PRO 6000** completed 11 iterations — impressively close to the 27B models despite being a 4.5x larger model. The 48GB VRAM on the Max-Q card makes running 122B-A10B (MoE) practical.
- **5090 with Q5_K_M** quantization completed the most iterations (12), showing that higher quality quantization on the 27B doesn't hurt throughput meaningfully.
- **4090 and 3090** running the same Q4_K_M 27B model show the expected generational gap (42.5 vs 33.1 tok/s).
- All GPUs at 94-95% utilization — fully saturated.
- The 122B model draws more power (375W avg vs 336W for the 27B lanes) on the 6000, which is near its 300W TDP — likely boosting above rated power under sustained load.

## Infrastructure

```
  Agent 1 ──► nothink proxy ──► llama.cpp (122B Q4 on RTX PRO 6000 Max-Q)
  Agent 2 ──► nothink proxy ──► llama.cpp (27B Q5 on RTX 5090)
  Agent 3 ──► nothink proxy ──► llama.cpp (27B Q4 on RTX 4090)
  Agent 4 ──► nothink proxy ──► llama.cpp (27B Q4 on RTX 3090)
                                     │
  metrics_collector.py ── polls nvidia-smi + /slots ─┘
```

## Reproduce

See `framework/` for the launcher, proxies, metrics collector, and live viewer.
See `services/` for the systemd unit files.

```bash
cd demo-2/framework
HOST_A=<gpu-host-1> HOST_B=<gpu-host-2> DURATION=600 ./launch_agents.sh
```
