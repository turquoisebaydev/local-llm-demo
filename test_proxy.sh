#!/bin/bash
cd /home/turq/dev/local-llm-demo/demo-2/framework
python3 nothink_proxy.py --listen 127.0.0.1:9101 --backend http://10.0.20.9:18080/v1 &
PROXY_PID=$!
sleep 1

curl -s http://127.0.0.1:9101/chat/completions -H "Content-Type: application/json" -d '{
  "model": "default",
  "messages": [{"role": "user", "content": "Say hello in 5 words."}],
  "max_tokens": 50
}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('Proxy test:', d['choices'][0]['message']['content'][:200])"

kill $PROXY_PID 2>/dev/null
wait $PROXY_PID 2>/dev/null
