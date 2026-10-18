import json, subprocess
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd=[exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","--mcp"]
def call(i,name,args):
    return {"jsonrpc":"2.0","id":i,"method":"tools/call","params":{"name":name,"arguments":args}}
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},{"jsonrpc":"2.0","method":"notifications/initialized"},
      call(2,"bombit_new",{"agent":"mcp","mode":"dig","seed":"mcpdemo"}),
      call(3,"bombit_act",{"session":"PENDING","move":"down","frames":12}),
      call(4,"bombit_state",{}),
      call(5,"bombit_finish",{"session":"PENDING"})]
# need session id from response; run first three, then read session, then finish in a second process? session id unknown before.
# Use a session name we choose.
msgs[2]["params"]["arguments"]["session"]="mcp-probe"
for m in msgs[3:5]:
    m["params"]["arguments"]["session"]="mcp-probe"
inp="\n".join(json.dumps(m) for m in msgs)+"\n"
p=subprocess.run(cmd,input=inp.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
for line in p.stdout.decode().splitlines():
    o=json.loads(line)
    if "result" in o and isinstance(o["result"],dict) and "content" in o["result"]:
        inner=json.loads(o["result"]["content"][0]["text"])
        print("id",o.get("id"),"ok",inner.get("ok"),"revision",inner.get("revision"),"session_tail",str(inner.get("session"))[-6:],"stop",inner.get("stopReason"),"replay",str(inner.get("replayFile"))[-40:])
    else:
        print("msg",o.get("id"),"method",o.get("method",""),"tools",len(o.get("result",{}).get("tools",[])))
print("stderr",p.stderr.decode()[:500])
