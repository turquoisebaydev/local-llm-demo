# Demo 2 model settings (Qwen3.5-27B split by GPU capability)

Timestamp: 2026-03-25 (Australia/Sydney)

## Target state

- Chat template: `/home/turq/models/qwen3.5_chat_template.jinja`
- Context: `-c 131072` (all 4 GPUs)
- Slots: `-np 1`
- KV quant: `-ctk q4_0 -ctv q4_0`
- Reasoning: `--reasoning-format none --reasoning-budget 0`

## Per-GPU model assignment

1. pg1 RTX PRO 6000
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B.Q5_K_M.gguf`
   - unit: `llama-demo2-6000.service`
   - port: `18080`

2. pg1 RTX 5090
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B.Q5_K_M.gguf`
   - unit: `llama-demo2-5090.service`
   - port: `18181`

3. turqette RTX 4090
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf`
   - unit: `llama-demo2-4090.service`
   - port: `8080`

4. turqette RTX 3090
   - model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf`
   - unit: `llama-demo2-3090.service`
   - port: `8081`

## Notes

- This matches the “best reasonable at 131072 context” plan using currently available local model files.
- Demo 3 services (9B) should be stopped while Demo 2 is active to avoid GPU contention.
