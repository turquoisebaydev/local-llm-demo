# Demo 3 model settings (Qwen3.5-9B Q4_K_M)

Timestamp: 2026-03-25 (Australia/Sydney)

## Target state

- Model: `/home/turq/models/Qwen3.5-small-GGUF/Qwen3.5-9B-Q4_K_M.gguf`
- Chat template: `/home/turq/models/qwen3.5_chat_template.jinja`
- Context: `-c 131072` (all 4 GPUs)
- Slots: `-np 1`
- KV quant: `-ctk q4_0 -ctv q4_0`
- Reasoning: `--reasoning-format none --reasoning-budget 0`

## Per-GPU layout

1. pg1 RTX PRO 6000
   - unit: `llama-qwen9-6000.service`
   - port: `19080`

2. pg1 RTX 5090
   - unit: `llama-qwen9-5090.service`
   - port: `19181`

3. turqette RTX 4090
   - unit: `llama-qwen9-4090.service`
   - port: `9080`

4. turqette RTX 3090
   - unit: `llama-qwen9-3090.service`
   - port: `9081`

## Notes

- Chosen ports avoid collision with demo-1 27B ports.
- For strict apples-to-apples comparisons, keep prompt, seed, and params identical across all four services.
