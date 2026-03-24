# Demo 4 — Split-tier best-fit (Q6 lanes)

This demo defines the next split configuration:

- **pg1 big split (6000+5090):** Qwen3.5-122B-A10B UD-Q6_K_XL
- **turqette split (4090+3090):** Qwen3.5-27B Q6_K

Both services target `-c 131072` and use q4_0 KV cache.

## Service specs

Vision is enabled by adding `--mmproj` to each split service unit (see `services/`).


- `services/pg1/llama-demo4-122b-q6-split.service`
- `services/turqette/llama-demo4-27b-q6-split.service`

## Backend endpoints

- pg1 (122B split): `http://10.0.20.9:18084/v1`
- turqette (27B split): `http://10.0.20.107:8084/v1`

## Prep notes

- Ensure 27B Q6 is present at:
  `/home/turq/models/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q6_K.gguf`
- Keep this as the canonical spec for the renamed split demo target (previously tracked under demo-2 discussions).
