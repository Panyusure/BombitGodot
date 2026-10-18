# -*- coding: utf-8 -*-
"""BombIt -> Godot 素材预处理：裁剪/缩放角色与敌人立绘，复制字体与配乐。"""
import os
from PIL import Image

SRC = r"E:\BombIt"
DST = r"E:\BombitGodot"

CHARS = {
    "xiaonuo": dict(crop=(200, 40, 729, 1295), height=1.55, anchor=(.5, .78)),
    "axiu": dict(crop=(199, 34, 870, 1249), height=1.58, anchor=(.5, .88)),
    "arui": dict(crop=(203, 87, 875, 1098), height=1.62, anchor=(.5, .97)),
    "xiaoyan": dict(crop=(160, 44, 943, 1191), height=1.58, anchor=(.5, .97)),
    "weilai": dict(crop=(276, 40, 780, 1079), height=1.62, anchor=(.5, .97)),
    "weilai-awakened": dict(crop=(5, 6, 1351, 1123), height=3.05, anchor=(.53, .97)),
    "xiaotian": dict(crop=(160, 60, 1049, 1027), height=1.56, anchor=(.5, .88)),
}
BACK = {
    "xiaonuo": dict(crop=(213, 51, 745, 1281), anchor=(.5, .78)),
    "axiu": dict(crop=(156, 37, 868, 1249), anchor=(.5, .84)),
    "arui": dict(crop=(212, 83, 811, 1083), anchor=(.5, .97)),
    "xiaoyan": dict(crop=(163, 25, 908, 1254), height=1.65, anchor=(.5, .92)),
    "xiaotian": dict(crop=(245, 41, 988, 1040), anchor=(.5, .88)),
    "weilai": dict(crop=(300, 18, 758, 1110), anchor=(.5, .97)),
    "weilai-awakened": dict(crop=(0, 0, 1358, 1123), anchor=(.5, .97)),
}
ENEMIES = {
    "gugu": dict(crop=(82, 95, 1148, 1060), mode="height", height=288),
    "claude": dict(crop=(62, 67, 1166, 1089), mode="height", height=288),
    "oupao": dict(crop=(91, 67, 1143, 1092), mode="height", height=288),
    "luludan": dict(crop=(189, 16, 922, 1192), mode="height", height=384),
    "luludan-rage-v2": dict(crop=(189, 16, 922, 1192), mode="height", height=384),
}

CHAR_H = 560   # 选角海报最大显示约 400 物理像素，保留约 1.4 倍余量\nENEMY_H = 288  # 敌情档案约 198 物理像素\nBOSS_H = 384


def save_plain(im, path):
    """保留原 crop 的透明留白：锚点与缩放比例才能和原作一致。"""
    im.save(path, optimize=True)
    return im.size


def process_char(cid, cfg, suffix, src_name):
    src = os.path.join(SRC, "assets", "characters", src_name)
    im = Image.open(src).convert("RGBA")
    x, y, w, h = cfg["crop"]
    im = im.crop((x, y, x + w, y + h))
    # 保留高清分辨率：菜单海报会放大到约 400 物理像素
    target_h = CHAR_H
    target_w = max(8, round(im.width * target_h / im.height))
    im = im.resize((target_w, target_h), Image.LANCZOS)
    out = os.path.join(DST, "assets", "characters", f"{cid}{suffix}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    size = save_plain(im, out)
    print(f"char {cid}{suffix}: crop=({x},{y},{w},{h}) -> {size}")


def process_enemy(name, spec):
    src = os.path.join(SRC, "assets", "enemies", f"{name}.png")
    if not os.path.exists(src):
        print("missing enemy", src)
        return
    im = Image.open(src).convert("RGBA")
    x, y, w, h = spec["crop"]
    im = im.crop((x, y, x + w, y + h))
    th = spec["height"]
    im = im.resize((max(1, round(im.width * th / im.height)), th), Image.LANCZOS)
    out = os.path.join(DST, "assets", "enemies", f"{name}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    size = save_plain(im, out)
    print(f"enemy {name}: {size}")


def main():
    for cid, cfg in CHARS.items():
        process_char(cid, cfg, "", f"{cid}-hd.png")
        back = dict(cfg)
        back.update(BACK[cid])
        process_char(cid, back, "-back", f"{cid}-back-hd.png")

    for name, spec in ENEMIES.items():
        process_enemy(name, spec)

    # 菜单壁纸：缩小到 1600 宽存 JPEG
    wall = Image.open(os.path.join(SRC, "assets", "ui", "menu-wallpaper.png")).convert("RGB")
    wall = wall.resize((2560, round(wall.height * 2560 / wall.width)), Image.LANCZOS)
    os.makedirs(os.path.join(DST, "assets", "ui"), exist_ok=True)
    wall.save(os.path.join(DST, "assets", "ui", "menu-wallpaper.jpg"), quality=90, optimize=True)
    print("wallpaper", wall.size)

    # 字体：Microsoft YaHei（UI 正文）、Consolas（等宽标签）、Impact（大号编号）
    os.makedirs(os.path.join(DST, "assets", "fonts"), exist_ok=True)
    for font_name in ["msyh.ttc", "msyhbd.ttc", "consola.ttf", "consolab.ttf", "impact.ttf"]:
        with open(os.path.join(r"C:\Windows\Fonts", font_name), "rb") as f:
            data = f.read()
        with open(os.path.join(DST, "assets", "fonts", font_name), "wb") as f:
            f.write(data)
        print("font", font_name, len(data))

    # 配乐
    os.makedirs(os.path.join(DST, "assets", "audio", "music"), exist_ok=True)
    for name in ["menu", "level-1", "level-2", "boss-1", "boss-2"]:
        with open(os.path.join(SRC, "assets", "audio", name + ".mp3"), "rb") as f:
            data = f.read()
        with open(os.path.join(DST, "assets", "audio", "music", name + ".mp3"), "wb") as f:
            f.write(data)
        print("music", name, round(len(data) / 1024), "KB")


if __name__ == "__main__":
    main()
