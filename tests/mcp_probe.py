import json, subprocess, sys
exe = r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd = [exe, "--headless", "--no-header", "--path", r"E:\BombitGodot", "--script", "res://scripts/cli/BombitCLI.gd", "--", "--mcp"]
msgs = [
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}},
 {"jsonrpc":"2.0","method":"notifications/initialized"},
 {"jsonrpc":"2.0","id":2,"method":"tools/list"},
 {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"bombit_rules","arguments":{}}},
]
inp = "\n".join(json.dumps(m,ensure_ascii=False) for m in msgs) + "\n"
p = subprocess.run(cmd, input=inp.encode("utf-8"), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
print("exit", p.returncode)
print("stderr", p.stderr.decode("utf-8","replace")[:500])
lines = [l for l in p.stdout.decode("utf-8","replace").splitlines() if l.strip()]
print("stdout lines", len(lines))
for line in lines:
    try:
        obj = json.loads(line)
        if "result" in obj and isinstance(obj["result"], dict) and "tools" in obj["result"]:
            print("tools", len(obj["result"]["tools"]), [t["name"] for t in obj["result"]["tools"]][:4])
        elif "result" in obj and isinstance(obj["result"], dict) and "content" in obj["result"]:
            print("tool result isError", obj["result"].get("isError"), obj["result"]["content"][0]["text"][:80])
        else:
            print("json", json.dumps(obj, ensure_ascii=False)[:180])
    except Exception as e:
        print("NON-JSON", repr(line[:200]), e)
