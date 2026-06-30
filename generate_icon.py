#!/usr/bin/env python3
"""生成「阻只读书」macOS 圆角 App 图标 — 书本内含井字网格"""

import math, os
from PIL import Image, ImageDraw

SIZE = 1024
R = int(SIZE * 0.224)  # Apple squircle ~22.4%


def rounded_mask(s: int, r: int) -> Image.Image:
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([(0, 0), (s - 1, s - 1)], radius=r, fill=255)
    return m


def draw_book(draw, cx, cy, bw, bh):
    """金色翻开书本，书页上绘「井」字网"""
    left = cx - bw // 2
    right = cx + bw // 2
    spine_x = left + int(bw * 0.48)
    top = cy - bh // 2
    bottom = cy + bh // 2

    page = (248, 228, 170)   # 淡金书页
    ink = (180, 145, 70)     # 井字墨色
    spine_c = (195, 160, 90)
    shadow_c = (160, 130, 60)

    # ---- 左页 ----
    draw.polygon([
        (left,            top + int(bh * 0.04)),
        (spine_x,         top + int(bh * 0.10)),
        (spine_x,         bottom - int(bh * 0.10)),
        (left,            bottom - int(bh * 0.04)),
    ], fill=page)

    # ---- 右页 ----
    draw.polygon([
        (spine_x,         top + int(bh * 0.10)),
        (right,           top + int(bh * 0.04)),
        (right,           bottom - int(bh * 0.04)),
        (spine_x,         bottom - int(bh * 0.10)),
    ], fill=page)

    # ---- 书脊 ----
    spine_w = int(bw * 0.05)
    draw.rectangle([(spine_x - spine_w // 2, top + int(bh * 0.08)),
                    (spine_x + spine_w // 2, bottom - int(bh * 0.08))],
                   fill=spine_c)

    # ---- 井字网格 (画在书页中心区域) ----
    grid_left   = left   + int(bw * 0.13)
    grid_right  = right  - int(bw * 0.13)
    grid_top    = top    + int(bh * 0.22)
    grid_bottom = bottom - int(bh * 0.22)
    lw = int(SIZE * 0.012)  # 线宽

    # 两横
    for frac in (1/3, 2/3):
        y = grid_top + int((grid_bottom - grid_top) * frac)
        draw.rectangle([(grid_left, y - lw // 2), (grid_right, y + lw // 2)], fill=ink)

    # 两竖
    for frac in (1/3, 2/3):
        x = grid_left + int((grid_right - grid_left) * frac)
        draw.rectangle([(x - lw // 2, grid_top), (x + lw // 2, grid_bottom)], fill=ink)

    # 井心小方块稍深色
    mc_x = grid_left + int((grid_right - grid_left) * 0.5)
    mc_y = grid_top + int((grid_bottom - grid_top) * 0.5)
    inner = int(lw * 0.9)
    draw.rectangle([(mc_x - inner, mc_y - inner), (mc_x + inner, mc_y + inner)], fill=(140, 105, 45))

    # 声波纹
    wave_cy = top - int(bh * 0.22)
    for i, wr in enumerate([int(bw * 0.18), int(bw * 0.26), int(bw * 0.34)]):
        alpha = 180 - i * 55
        draw.arc([(cx - wr, wave_cy - wr // 3), (cx + wr, wave_cy + wr // 3)],
                 start=210, end=330, fill=(255, 215, 110, alpha), width=int(SIZE * 0.016))


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 深蓝渐变底
    for y in range(SIZE):
        t = y / SIZE
        r = int(12 + t * 18)
        g = int(32 + t * 28)
        b = int(75 + t * 55)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    # 顶部微光
    for y in range(SIZE // 3):
        t = y / (SIZE // 3)
        draw.line([(0, y), (SIZE, y)], fill=(255, 255, 255, int(35 * (1 - t))))

    # 画书 + 井
    bw = int(SIZE * 0.48)
    bh = int(SIZE * 0.52)
    draw_book(draw, SIZE // 2, SIZE // 2 + int(SIZE * 0.04), bw, bh)

    # 圆角遮罩
    m = rounded_mask(SIZE, R)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, (0, 0), m)

    # 输出各尺寸
    icon_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "M-ReaderApp", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    sizes = {
        "icon_16x16": 16, "icon_16x16@2x": 32, "icon_32x32": 32, "icon_32x32@2x": 64,
        "icon_128x128": 128, "icon_128x128@2x": 256, "icon_256x256": 256, "icon_256x256@2x": 512,
        "icon_512x512": 512, "icon_512x512@2x": 1024,
    }
    for name, sz in sizes.items():
        resized = out.resize((sz, sz), Image.LANCZOS)
        resized.save(os.path.join(icon_dir, f"{name}.png"), "PNG")

    # 主 1024 图
    out.save(os.path.join(icon_dir, "icon_1024x1024.png"), "PNG")
    print("Icon regenerated with 井 grid — done.")


if __name__ == "__main__":
    main()
