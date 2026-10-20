# -*- coding: utf-8 -*-
"""把 高清海报/ 里的六张超大展示海报处理成游戏内可直接使用的贴图。

做三件事（可重复执行，结果稳定）：
  1. 裁掉素材自带的黑边 / 透明留白（不同素材的留白倍数不一样，不裁会让海报缩很小）；
  2. 等比缩到 POSTER_MAX_W 以内（菜单里最大也就铺满 720x696，再大只是浪费显存）；
  3. 存成 WebP 到 assets/characters/poster/<角色id>.webp，交给 Godot 导入。

用法：python tools_prepare_posters.py
"""

from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

# 素材文件名 -> Cfg.CHAR_IDS 里的角色 id。
# 海报上是这些精灵的进化形态名（奥奇传说五王），对应关系见 Cfg.CHARS 的 intro：
#   诺亚 = 小诺(时间之王的幼体) / 修尔 = 阿修(是非) / 阿瑞斯 = 阿瑞(生命)
#   龙炎 = 小炎(力量) / 帝释天 = 小天(智慧) / 未来(五女仆合体通灵师)
POSTERS = {
    "诺亚.png": "xiaonuo",
    "阿修.jpg": "axiu",
    "阿瑞.jpg": "arui",
    "小炎.png": "xiaoyan",
    "小天.png": "xiaotian",
    "未来.png": "weilai",
}

POSTER_MAX_W = 2800
POSTER_MAX_H = 2000
WEBP_QUALITY = 88

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(HERE, "高清海报")
OUT_DIR = os.path.join(HERE, "assets", "characters", "poster")


def _black_mask(a: np.ndarray) -> np.ndarray:
    """接近纯黑的像素（素材压片时留的黑边，JPEG 有噪点，因此给容差）。"""
    return (a.mean(axis=-1) < 14.0) & (a.std(axis=-1) < 9.0)


def trim_box(im: Image.Image) -> tuple[int, int, int, int]:
    """返回内容外接矩形。先按透明通道裁，再按四边纯黑行/列裁。"""
    left, top, right, bottom = 0, 0, im.width, im.height
    if im.mode in ("RGBA", "LA", "P"):
        alpha = np.asarray(im.convert("RGBA"))[..., 3]
        ys, xs = np.where(alpha > 8)
        if len(xs):
            left, top = int(xs.min()), int(ys.min())
            right, bottom = int(xs.max()) + 1, int(ys.max()) + 1

    rgb = np.asarray(im.convert("RGB").crop((left, top, right, bottom)), dtype=np.float32)
    black = _black_mask(rgb)
    h, w = black.shape
    while top < bottom - 8 and black[0, :].mean() > 0.985:
        black = black[1:, :]
        top += 1
    while bottom - 1 > top + 8 and black[-1, :].mean() > 0.985:
        black = black[:-1, :]
        bottom -= 1
    while left < right - 8 and black[:, 0].mean() > 0.985:
        black = black[:, 1:]
        left += 1
    while right - 1 > left + 8 and black[:, -1].mean() > 0.985:
        black = black[:, :-1]
        right -= 1
    return (left, top, right, bottom)


def main() -> int:
    if not os.path.isdir(SRC_DIR):
        print(f"找不到素材目录：{SRC_DIR}")
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    missing = [name for name in POSTERS if not os.path.isfile(os.path.join(SRC_DIR, name))]
    if missing:
        print("缺少海报：" + "、".join(missing))
        return 1

    for name, cid in POSTERS.items():
        src = Image.open(os.path.join(SRC_DIR, name))
        box = trim_box(src)
        art = src.crop(box).convert("RGB")
        w, h = art.size
        scale = min(POSTER_MAX_W / w, POSTER_MAX_H / h, 1.0)
        if scale < 1.0:
            art = art.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
        dst = os.path.join(OUT_DIR, cid + ".webp")
        art.save(dst, format="WEBP", quality=WEBP_QUALITY, method=6)
        print(
            "%-8s %-10s %s -> %s  %.2fMB"
            % (cid, name, src.size, art.size, os.path.getsize(dst) / (1024 * 1024))
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
