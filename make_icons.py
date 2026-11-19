# -*- coding: utf-8 -*-
"""把 res 下的五张技能原画处理成 128x128 圆形图标，另把衍天珠原画处理成透明底物品图标；输出到 Resources/ 并重建两张预览图。"""
import math
import os
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(ROOT, "res")
OUT = os.path.join(ROOT, "Resources")

JOBS = [
    ("img_skill_yantian_ziyu.jpg", "wfg_skill_heal.png"),       # 自愈：水卷
    ("img_skill_yantian_jiexi.jpg", "wfg_skill_derive.png"),    # 解析：人影
    ("img_skill_yantian_chaunzao.png", "wfg_skill_create.png"), # 创造：拳套
    ("img_skill_yantian_benminfabao.png", "wfg_skill_benminfabao.png"), # 本命法宝：剑
    ("img_skill_yantian_ninglianyantianzhu.png", "wfg_skill_ningzhu.png"), # 凝练衍天珠
]
ITEM_JOBS = [
    ("img_item_yantian_yantianzhu.png", "Spr/Object/wfg_item_yantianzhu.png"), # 衍天珠物品图
]
SIZE = 128
SS = 4


def has_alpha(im):
    if im.mode not in ("RGBA", "LA"):
        return False
    return im.getchannel("A").getextrema()[0] < 250


def is_white(px):
    return px[0] >= 244 and px[1] >= 244 and px[2] >= 244


def detect_radius(im):
    """沿 360 条射线找「中心 -> 首个连续 3 像素纯白」的距离，取 10% 分位作为画作半径。"""
    w, h = im.size
    cx = cy = (w - 1) / 2.0
    pix = im.load()
    radii = []
    for deg in range(0, 360, 2):
        a = math.radians(deg)
        dx, dy = math.cos(a), math.sin(a)
        hit = None
        run = 0
        for r in range(4, int(min(w, h) / 2) + 1):
            x = int(round(cx + dx * r))
            y = int(round(cy + dy * r))
            if not (0 <= x < w and 0 <= y < h):
                break
            if is_white(pix[x, y]):
                run += 1
                if run >= 3:
                    hit = r - 2
                    break
            else:
                run = 0
        if hit:
            radii.append(hit)
    if not radii:
        return min(w, h) / 2.0 - 1
    radii.sort()
    return radii[max(0, int(len(radii) * 0.10))]


def circle_mask(size, radius, feather_px):
    big = size * SS
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    c = (big - 1) / 2.0
    r = radius * SS
    d.ellipse((c - r, c - r, c + r, c + r), fill=255)
    if feather_px:
        m = m.filter(ImageFilter.GaussianBlur(feather_px * SS))
    return m.resize((size, size), Image.LANCZOS)


def process_item(src, dst):
    """物品图标：按 alpha 裁边、补方、留透明边，不套技能图标的圆形遮罩。"""
    im = Image.open(os.path.join(RES, src)).convert("RGBA")
    alpha = im.getchannel("A")
    # alpha=1 的边角杂点不算内容，阈值 8 去掉
    bbox = alpha.point(lambda a: 255 if a >= 8 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((side - w) // 2, (side - h) // 2))
    # 留 4px 透明边，避免贴图边缘被裁
    pad = 4
    framed = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    framed.alpha_composite(canvas, (pad, pad))
    # 物品图标只占画布一半，四周留透明空白；避免在背包格子里显得过大。
    content_side = SIZE // 2
    content = framed.resize((content_side, content_side), Image.LANCZOS)
    framed = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    off = (SIZE - content_side) // 2
    framed.alpha_composite(content, (off, off))
    out = os.path.join(OUT, dst)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    framed.save(out, "PNG", optimize=True)
    print("%-30s -> %-22s item %6d B" % (src, dst, os.path.getsize(out)))


def main():
    os.makedirs(OUT, exist_ok=True)
    for src, dst in JOBS:
        im = Image.open(os.path.join(RES, src))
        keep_alpha = has_alpha(im)
        im = im.convert("RGBA")
        w, h = im.size
        side = min(w, h)
        im = im.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
        if keep_alpha:
            # 已带透明通道的原画：用满圆收口，不能从 RGB 猜半径。
            # 新图标内部有白色高光，detect_radius 会误判成 7px 小圆。
            radius = SIZE / 2.0 - 0.5
        else:
            r = detect_radius(im.convert("RGB"))
            radius = r * SIZE / float(side)
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
        mask = circle_mask(SIZE, max(radius - 0.6, 12.0), 0.9)
        if keep_alpha:
            im.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
        else:
            im.putalpha(mask)
        out = os.path.join(OUT, dst)
        im.save(out, "PNG", optimize=True)
        print("%-30s -> %-22s alpha=%-5s r=%5.1f %6d B" % (src, dst, keep_alpha, radius, os.path.getsize(out)))

    for src, dst in ITEM_JOBS:
        process_item(src, dst)

    # 关闭态：同图去色压暗
    off = Image.open(os.path.join(OUT, "wfg_skill_heal.png")).convert("RGBA")
    rgb = ImageEnhance.Color(off.convert("RGB")).enhance(0.0)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.72)
    out = rgb.convert("RGBA")
    out.putalpha(off.getchannel("A"))
    out.save(os.path.join(OUT, "wfg_skill_heal_off.png"), "PNG", optimize=True)
    print("%-30s -> %-22s %6d B" % ("(heal 去色)", "wfg_skill_heal_off.png", os.path.getsize(os.path.join(OUT, "wfg_skill_heal_off.png"))))

    for bg, name in (((24, 26, 32, 255), "preview_skill_icons.png"), ((216, 201, 164, 255), "preview_skill_icons_panel.png")):
        dsts = [
            "wfg_skill_heal.png",
            "wfg_skill_derive.png",
            "wfg_skill_create.png",
            "wfg_skill_benminfabao.png",
            "wfg_skill_ningzhu.png",
            "wfg_skill_heal_off.png",
        ]
        sheet = Image.new("RGBA", (SIZE * len(dsts) + 10 * (len(dsts) + 1), SIZE + 20), bg)
        for i, dst in enumerate(dsts):
            sheet.alpha_composite(Image.open(os.path.join(OUT, dst)), (10 + i * (SIZE + 10), 10))
        sheet.save(os.path.join(RES, name), "PNG")


main()
