# Demo 1 model settings (Qwen3.5-27B Q4_K_M)

Timestamp: 2026-03-24 (Australia/Sydney)

## Target state

- Model: `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf`
- Chat template: `/home/turq/models/qwen3.5_chat_template.jinja`
- KV quant: `-ctk q4_0 -ctv q4_0`

### Per-GPU contexts / ports

1. pg1 RTX PRO 6000
   - context: `131072`
   - port: `18080`
   - unit: `llama-qwen27-6000.service`

2. pg1 RTX 5090
   - context: `131072`
   - port: `18181` *(18081 was occupied by docker-proxy)*
   - unit: `llama-qwen27-5090.service`

3. turqette RTX 4090
   - context: `131072`
   - port: `8080`
   - unit: `llama-qwen27-4090.service`

4. turqette RTX 3090
   - context: `131072`
   - port: `8081`
   - unit: `llama-qwen27-3090.service`

## Unloaded to make this work

- pg1: `llama-qwen122-6000.service` (stopped)
- turqette: `llama-qwen9-3090.service` (stopped)
- turqette: `luxtts-4090.service` (stopped)

## Health checks

- pg1: `curl http://127.0.0.1:18080/health`
- pg1: `curl http://127.0.0.1:18181/health`
- turqette: `curl http://127.0.0.1:8080/health`
- turqette: `curl http://127.0.0.1:8081/health`
