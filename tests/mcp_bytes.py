import json, subprocess
exe = r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd = [exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","--mcp"]
msgs=[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}},{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"bombit_rules","arguments":{}}}]
p=subprocess.run(cmd,input=("\n".join(json.dumps(m,ensure_ascii=False) for m in msgs)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
raw=p.stdout
print("first bytes",raw[:60])
print("has backslash u", b"\\u" in raw)
try:
    s=raw.decode("utf-8")
    print("utf8 ok", s[:120])
except Exception as e: print("utf8 fail",e)
try:
    s=raw.decode("gbk")
    print("gbk ok", s[:120])
except Exception as e: print("gbk fail",e)
