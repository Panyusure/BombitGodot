import json, subprocess
bat=r"E:\BombitGodot\dist\BombIt-Godot-v1.0-win64\bombit-mcp.bat"
cmd=["cmd","/c",bat]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},{"jsonrpc":"2.0","id":2,"method":"ping"}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
print("exit",p.returncode,"lines",len(p.stdout.splitlines()))
for l in p.stdout.splitlines():
 try: print(json.loads(l).get("id"), "ok")
 except: print("nonjson",l[:80])
print("stderr",p.stderr.decode()[:120])
