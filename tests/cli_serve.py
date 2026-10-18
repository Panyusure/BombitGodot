import json, subprocess
exe=r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
cmd=[exe,"--headless","--no-header","--path",r"E:\BombitGodot","--script","res://scripts/cli/BombitCLI.gd","--","serve"]
lines=[
 {"op":"new","agent":"jsonl","mode":"dig","seed":"jsonldemo","session":"jsonl-probe"},
 {"op":"state","session":"jsonl-probe"},
 {"op":"act","session":"jsonl-probe","move":"down","frames":2},
 {"op":"finish","session":"jsonl-probe"},
]
p=subprocess.run(cmd,input=("\n".join(json.dumps(x) for x in lines)+"\n").encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
print("exit",p.returncode,"lines",len(p.stdout.splitlines()))
for l in p.stdout.splitlines():
 o=json.loads(l); print(o.get("ok"),o.get("revision"),o.get("session"),o.get("archived"),str(o.get("error")))
print("stderr",p.stderr.decode()[:300])
