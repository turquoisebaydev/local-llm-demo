#!/usr/bin/env python3
"""Quick vision smoke test for demo backends."""
import urllib.request, json, base64, sys

ref_path = "/home/turq/dev/local-llm-demo/demo-2/framework/reference.jpg"
with open(ref_path, "rb") as f:
    img_b64 = base64.b64encode(f.read()).decode()

endpoints = sys.argv[1:] if len(sys.argv) > 1 else [
    "http://10.0.20.9:18080/v1",
    "http://10.0.20.9:18181/v1",
    "http://10.0.20.107:8080/v1",
    "http://10.0.20.107:8081/v1",
]

for url in endpoints:
    try:
        payload = json.dumps({
            "model": "default",
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"}},
                {"type": "text", "text": "Describe this image in one sentence."}
            ]}],
            "max_tokens": 100,
            "chat_template_kwargs": {"enable_thinking": False}
        }).encode()

        req = urllib.request.Request(f"{url}/chat/completions",
            data=payload, headers={"Content-Type": "application/json"})
        resp = urllib.request.urlopen(req, timeout=120)
        data = json.loads(resp.read())
        content = data["choices"][0]["message"]["content"][:200]
        print(f"✅ {url}: {content}")
    except Exception as e:
        print(f"❌ {url}: {e}")
