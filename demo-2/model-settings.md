# Demo 2 model settings (highest quality practical Qwen3.5 per GPU)

Timestamp: 2026-03-25 (Australia/Sydney)

## Goal

For each GPU, run the highest practical Qwen3.5-27B variant at `-c 131072`.

## Shared runtime targets

- Chat template: `/home/turq/models/qwen3.5_chat_template.jinja`
- Context: `-c 131072`
- Slots: `-np 1`
- KV quant: `-ctk q4_0 -ctv q4_0`
- Reasoning disabled for consistency:
  - `--reasoning-format none --reasoning-budget 0`

## Per-GPU model assignment

1. pg1 RTX PRO 6000 (96GB)
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/BF16/Qwen3.5-27B-BF16-00001-of-00002.gguf`
   - unit: `llama-demo2-6000.service`
   - port: `18080`

2. pg1 RTX 5090 (32GB)
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B.Q5_K_M.gguf`
   - unit: `llama-demo2-5090.service`
   - port: `18181`

3. turqette RTX 4090 (24GB)
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf`
   - unit: `llama-demo2-4090.service`
   - port: `8080`

4. turqette RTX 3090 (24GB)
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf`
   - unit: `llama-demo2-3090.service`
   - port: `8081`

## Notes

- This is the canonical "best-per-GPU" Demo 2 mapping.
- Demo 3/4 services should be stopped while Demo 2 is active to avoid GPU contention.
