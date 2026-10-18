import json, subprocess
exe=r"E:\BombitGodot\build\windows\BombitGodot.console.exe"
cmd=[exe,"--headless","--no-header","--","--mcp"]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},
      {"jsonrpc":"2.0","id":2,"method":"tools/list"},
      {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"bombit_new","arguments":{"agent":"exported","mode":"dig","seed":"exp"}}}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
print("exit",p.returncode,"stdout lines",len(p.stdout.splitlines()))
for l in p.stdout.splitlines():
 o=json.loads(l)
 if "result" in o and "tools" in o["result"]: print("tools",len(o["result"]["tools"]))
 elif "result" in o and "content" in o["result"]:
  inner=json.loads(o["result"]["content"][0]["text"]); print("new",inner.get("ok"),str(inner.get("session"))[-12:])
 else: print("init",o.get("id"))
print("stderr tail",p.stderr.decode()[-200:])
