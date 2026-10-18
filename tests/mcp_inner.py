import json, subprocess
exe = r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd=[exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","--mcp"]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"bombit_rules","arguments":{}}}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,timeout=30)
for line in p.stdout.decode().splitlines():
    o=json.loads(line)
    if "result" in o and "content" in o["result"]:
        text=o["result"]["content"][0]["text"]
        print("text repr",repr(text[:120]))
        inner=json.loads(text)
        print("name",inner["rules"]["characters"][0]["name"],repr(inner["rules"]["characters"][0]["name"]))
