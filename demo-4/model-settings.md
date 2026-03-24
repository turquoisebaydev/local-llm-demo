# Demo 4 model settings (split-by-tier, both Q6)

Timestamp: 2026-03-25 (Australia/Sydney)

## Goal

Use each host pair at its best practical tier:

- **pg1 (RTX PRO 6000 + RTX 5090)**: Qwen3.5-122B-A10B **UD-Q6_K_XL** (split)
- **turqette (RTX 4090 + RTX 3090)**: Qwen3.5-27B **Q6_K** (split)

## Shared runtime targets

- Chat template: `/home/turq/models/qwen3.5_chat_template.jinja`
- Context: `-c 131072`
- Slots: `-np 1`
- KV quant: `-ctk q4_0 -ctv q4_0`
- Reasoning disabled for benchmark consistency:
  - `--reasoning-format none --reasoning-budget 0`

## Service layout

1. **pg1 122B split service**
   - unit: `llama-demo4-122b-q6-split.service`
   - GPUs: `6000 + 5090` (`CUDA_VISIBLE_DEVICES=0,1`)
   - tensor split: `-ts 3,1`
   - backend: `http://10.0.20.9:18084/v1`

2. **turqette 27B split service**
   - unit: `llama-demo4-27b-q6-split.service`
   - GPUs: `4090 + 3090` (`CUDA_VISIBLE_DEVICES=0,1`)
   - tensor split: `-ts 1,1`
   - backend: `http://10.0.20.107:8084/v1`

## Notes

- This is the **Demo 4** replacement for the previous "Demo 2" split concept.
- 27B Q6 file expected at:
  `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q6_K.gguf`
- Keep Demo 3 (9B) services stopped while running Demo 4 to avoid GPU contention.
