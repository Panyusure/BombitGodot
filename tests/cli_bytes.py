import subprocess, json
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
p=subprocess.run([exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","rules","--json"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
raw=p.stdout
print("raw has nonascii", any(b>127 for b in raw), "first nonascii", next((i for i,b in enumerate(raw) if b>127), -1))
print(raw[:200])
line=[l for l in raw.splitlines() if l.startswith(b"{")][-1]
print("line prefix",line[:80])
try:
 o=json.loads(line.decode("utf-8")); print("utf8 name",repr(o["rules"]["characters"][0]["name"]))
except Exception as e:
 print("utf8 fail",e)
 o=json.loads(line.decode("gbk")); print("gbk name",repr(o["rules"]["characters"][0]["name"]))
