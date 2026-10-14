#!/usr/bin/env python3
"""把「棋盘格画成像素」的那张源图抠成真正的透明 PNG，并测量内容包围盒。

生成器不支持真 alpha，它把透明棋盘格直接画成了像素：
纯白 (253,253,253) 与浅灰 (227,225,225) 交替的 64px 方格。
所以抠图思路是「从画布边界做连通性 BFS」，而不是全局颜色阈值 ——
后者会连她白色的头发一起吃掉（发色 250,242,237 亮度也很高，且接近中性色）。
"""
import sys
from collections import deque

from PIL import Image, ImageFilter

SRC = ('/home/lele/桌面/app/sshterm/design/'
       'Keep_the_exact_same_character__2026-10-13T15-39-29.png')
OUT_MASTER = '/home/lele/桌面/app/sshterm/design/icon/master_transparent.png'
OUT_CHECK = '/home/lele/tmp/icon_keyed_checker.png'


def is_bg_like(r: int, g: int, b: int) -> bool:
    """棋盘格两色：接近中性 + 足够亮。"""
    if abs(r - g) > 14 or abs(g - b) > 14 or abs(r - b) > 14:
        return False
    return (r + g + b) / 3.0 > 198


def main() -> int:
    im = Image.open(SRC).convert('RGB')
    w, h = im.size
    px = im.load()

    # ---- 1. 从四条边界做 BFS，只走「背景色」像素，得到连通背景掩码
    bg = bytearray(w * h)
    q = deque()

    def push(x: int, y: int) -> None:
        i = y * w + x
        if not bg[i] and is_bg_like(*px[x, y]):
            bg[i] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        if x > 0:
            push(x - 1, y)
        if x < w - 1:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y < h - 1:
            push(x, y + 1)

    total_bg = sum(bg)
    print(f'背景占比 {total_bg / (w * h):.1%}')

    # ---- 2. 生成 alpha。边界抗锯齿像素（背景->深描边的过渡）亮度居中，
    #        直接判 0 会留下一圈浅灰晕，这里按亮度给个线性坡度。
    alpha = Image.new('L', (w, h), 255)
    ap = alpha.load()
    for y in range(h):
        base = y * w
        for x in range(w):
            if bg[base + x]:
                ap[x, y] = 0

    # 边缘 2px 带内按亮度重算 alpha
    for y in range(h):
        for x in range(w):
            if bg[y * w + x]:
                continue
            near_bg = False
            for dy in (-2, -1, 0, 1, 2):
                yy = y + dy
                if yy < 0 or yy >= h:
                    continue
                for dx in (-2, -1, 0, 1, 2):
                    xx = x + dx
                    if xx < 0 or xx >= w:
                        continue
                    if bg[yy * w + xx]:
                        near_bg = True
                        break
                if near_bg:
                    break
            if not near_bg:
                continue
            lum = sum(px[x, y]) / 3.0
            ramp = (218.0 - lum) / (218.0 - 96.0)
            ap[x, y] = max(0, min(255, int(round(ramp * 255))))

    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))

    out = im.convert('RGBA')
    out.putalpha(alpha)
    out.save(OUT_MASTER)
    print('written ->', OUT_MASTER)

    bbox = alpha.point(lambda v: 255 if v > 24 else 0).getbbox()
    print('内容包围盒', bbox, '宽高', bbox[2] - bbox[0], bbox[3] - bbox[1])

    # ---- 3. 棋盘格预览，肉眼确认抠图边缘有没有残边
    cell = 48
    chk = Image.new('RGB', (w, h), (255, 255, 255))
    cp = chk.load()
    for yy in range(h):
        for xx in range(w):
            if ((xx // cell) + (yy // cell)) % 2:
                cp[xx, yy] = (205, 205, 205)
    chk.paste(out, (0, 0), out)
    chk.save(OUT_CHECK)
    print('written ->', OUT_CHECK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
