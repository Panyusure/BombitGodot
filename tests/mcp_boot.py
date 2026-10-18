import json, subprocess
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd=[exe,"--headless","--no-header","--path",r"E:\BombitGodot","--","--mcp"]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},
      {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"bombit_new","arguments":{"agent":"mcp","mode":"dig","seed":"boot"}}},
      {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"bombit_rules","arguments":{}}}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
print("exit",p.returncode,"out lines",len(p.stdout.splitlines()))
for l in p.stdout.splitlines():
 o=json.loads(l)
 if "result" in o and "content" in o["result"]:
  inner=json.loads(o["result"]["content"][0]["text"]); print("tool",o["id"],inner.get("ok"),str(inner.get("session"))[-10:])
 else: print("msg",o.get("id"),len(o.get("result",{}).get("tools",[])))
print("stderr",p.stderr.decode()[:300])
