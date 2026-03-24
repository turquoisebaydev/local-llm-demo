# Demo 1 model settings (Qwen3.5-27B Q4_K_M)

## Model config

- Model: `Qwen3.5-27B-Q4_K_M.gguf`
- Chat template: `qwen3.5_chat_template.jinja` (with `--jinja` flag)
- Vision projector: `/home/turq/models/Qwen3.5-27B-GGUF/mmproj-F16.gguf` (required for image input)
- KV quant: `-ctk q4_0 -ctv q4_0`
- Flash attention: `-fa auto`

### Per-GPU settings

Each GPU runs one llama-server instance with identical model and settings, differing only in port and CUDA device.

| GPU | Context | Service unit |
|-----|---------|-------------|
| RTX PRO 6000 | 131072 | `llama-qwen27-6000.service` |
| RTX 5090 | 131072 | `llama-qwen27-5090.service` |
| RTX 4090 | 131072 | `llama-qwen27-4090.service` |
| RTX 3090 | 131072 | `llama-qwen27-3090.service` |

## Services unloaded for this demo

Other llama.cpp instances were stopped to free VRAM:
- `llama-qwen122-6000.service`
- `llama-qwen9-3090.service`
- `luxtts-4090.service`
