import json, subprocess
exe=r"E:\BombitGodot\dist\BombIt-Godot-v1.0-win64\BombitGodot.console.exe"
cmd=[exe,"--headless","--no-header","--","--mcp"]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},
      {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"bombit_list_replays","arguments":{}}}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
for l in p.stdout.splitlines():
 o=json.loads(l)
 if "content" in o.get("result",{}):
  inner=json.loads(o["result"]["content"][0]["text"]); print("count",len(inner["replays"])); [print(r["name"],r["actions"]) for r in inner["replays"]]
