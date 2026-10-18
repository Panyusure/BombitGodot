import json, subprocess, time
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd=[exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","--mcp"]
sid="mcp-probe-"+str(int(time.time()))
def call(i,name,args): return {"jsonrpc":"2.0","id":i,"method":"tools/call","params":{"name":name,"arguments":args}}
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},
      call(2,"bombit_new",{"agent":"mcp","mode":"dig","seed":"mcpdemo","session":sid}),
      call(3,"bombit_act",{"session":sid,"move":"down","frames":12}),
      call(4,"bombit_finish",{"session":sid})]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
for line in p.stdout.decode().splitlines():
    o=json.loads(line)
    if "result" in o and isinstance(o["result"],dict) and "content" in o["result"]:
        inner=json.loads(o["result"]["content"][0]["text"])
        print("id",o.get("id"),"ok",inner.get("ok"),"err",inner.get("error"),"archived",inner.get("archived"),"file",str(inner.get("replayFile"))[-50:])
print("stderr",p.stderr.decode()[:400])
