import subprocess, json
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
p=subprocess.run([exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","rules","--json"],stdout=subprocess.PIPE,timeout=30)
line=[l for l in p.stdout.splitlines() if l.startswith(b"{")][-1]
i=line.find(b'"name"')
print(line[i:i+50])
print(line[i:i+50].hex())
o=json.loads(line.decode("utf-8"))
name=o["rules"]["characters"][0]["name"]
print(repr(name), [hex(ord(c)) for c in name])
print(json.loads('{"name":"\\u5c0f\\u8bfa"}')["name"])
