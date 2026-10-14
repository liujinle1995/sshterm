#!/usr/bin/env python3
"""从透明母版生成 Android 图标资源。

产出：
  mipmap-*/ic_launcher.png             传统方形图标（API < 26 用，满版）
  mipmap-*/ic_launcher_foreground.png  自适应图标前景（角色缩放进安全圆）
  drawable/ic_launcher_background.xml  自适应图标背景（径向渐变）
  mipmap-anydpi-v26/ic_launcher.xml    自适应图标声明
  design/icon/preview_icon.png         裁切效果核对图
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = '/home/lele/桌面/app/sshterm'
ANDROID_RES = f'{ROOT}/android/app/src/main/res'
MASTER = f'{ROOT}/design/icon/master_transparent.png'
PREVIEW = f'{ROOT}/design/icon/preview_icon.png'

# 内容包围盒（由 key_icon.py 量出）
BBOX = (172, 89, 891, 890)

# 自适应图标：画布 108dp，遮罩圆直径 72dp（= 画布的 2/3），
# 前景内容压在这个圆内才不会被任何形状的遮罩切掉。留 7% 余量。
MASK_RATIO = 72.0 / 108.0
MASK_MARGIN = 0.93

# 传统图标：满版方形
LEGACY_FILL = 0.90

DENSITIES = [
    ('mdpi', 1.0),
    ('hdpi', 1.5),
    ('xhdpi', 2.0),
    ('xxhdpi', 3.0),
    ('xxxhdpi', 4.0),
]

# 与应用主题（teal 种子色 + 深色终端）呼应的径向渐变
BG_CENTER = (30, 74, 82)
BG_EDGE = (9, 18, 24)


def radial_bg(size: int) -> Image.Image:
    """中心偏上打亮的径向渐变，给角色一个"发光底座"。"""
    img = Image.new('RGB', (size, size))
    px = img.load()
    cx, cy = size / 2.0, size * 0.44
    max_d = (cx ** 2 + (size - cy) ** 2) ** 0.5
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / max_d
            d = min(1.0, d) ** 0.9
            px[x, y] = tuple(
                int(round(BG_CENTER[i] + (BG_EDGE[i] - BG_CENTER[i]) * d))
                for i in range(3)
            )
    return img


def fit(master: Image.Image, canvas: int, fill: float,
        use_diagonal: bool) -> Image.Image:
    """把内容按比例缩放后居中贴到 canvas 上。"""
    content = master.crop(BBOX)
    cw, ch = content.size

    if use_diagonal:
        # 内容的外接圆必须落进遮罩圆
        half_diag = (cw ** 2 + ch ** 2) ** 0.5 / 2.0
        radius = canvas * MASK_RATIO / 2.0 * MASK_MARGIN
        k = radius / half_diag
    else:
        k = canvas * fill / max(cw, ch)

    new_w, new_h = max(1, int(round(cw * k))), max(1, int(round(ch * k)))
    content = content.resize((new_w, new_h), Image.LANCZOS)

    out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    out.paste(content, ((canvas - new_w) // 2, (canvas - new_h) // 2), content)
    return out


def write_xml() -> None:
    drawable = f'{ANDROID_RES}/drawable'
    os.makedirs(drawable, exist_ok=True)
    c0 = '#%02X%02X%02X' % BG_CENTER
    c1 = '#%02X%02X%02X' % BG_EDGE
    with open(f'{drawable}/ic_launcher_background.xml', 'w', encoding='utf-8') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- 自适应图标背景：径向渐变，和外层 mipmap 里的传统图标保持一致 -->\n'
            '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:shape="rectangle">\n'
            '    <gradient\n'
            '        android:type="radial"\n'
            '        android:centerX="50%"\n'
            '        android:centerY="44%"\n'
            f'        android:gradientRadius="78%p"\n'
            f'        android:startColor="{c0}"\n'
            f'        android:endColor="{c1}" />\n'
            '</shape>\n'
        )

    anydpi = f'{ANDROID_RES}/mipmap-anydpi-v26'
    os.makedirs(anydpi, exist_ok=True)
    with open(f'{anydpi}/ic_launcher.xml', 'w', encoding='utf-8') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '</adaptive-icon>\n'
        )


def draw_text(draw, xy, text, size):
    """逐字符选字体：DroidSansFallbackFull 不含拉丁字母，
    整行都用它会让人名/数字变方块。"""
    from PIL import ImageFont
    latin = ImageFont.truetype(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', size)
    cjk = ImageFont.truetype(
        '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf', size)
    x, y = xy
    for ch in text:
        f = cjk if ord(ch) >= 0x2E80 else latin
        draw.text((x, y), ch, font=f, fill=(206, 214, 222))
        x += draw.textlength(ch, font=f)


def mask_icon(icon: Image.Image, shape: str, s: int) -> Image.Image:
    """按常见启动器遮罩形状裁一下，用来看真实观感。

    正确顺序是「先把 108dp 画布裁到中间 72dp 可见区，再套遮罩形状」。
    如果反过来（整张画布缩小后套一个铺满的圆），等于把可见区当成 25%，
    角色会显得莫名地小 —— 第一版就踩了这个坑。
    """
    total = icon.size[0]
    crop = int(round(total * MASK_RATIO))
    off = (total - crop) // 2
    canvas = icon.crop((off, off, off + crop, off + crop)).resize(
        (s, s), Image.LANCZOS).convert('RGBA')

    m = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(m)
    if shape == 'circle':
        d.ellipse((0, 0, s - 1, s - 1), fill=255)
    elif shape == 'teardrop':
        # 三个角全圆 + 右下角收成尖角
        d.ellipse((0, 0, s - 1, s - 1), fill=255)
        d.rectangle((s // 2, s // 2, s - 1, s - 1), fill=255)
    else:  # squircle / 圆角方
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.34), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(0.5))

    out = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    out.paste(canvas, (0, 0), m)
    return out


def main() -> int:
    readme = Image.open(MASTER).convert('RGBA')

    # 传统图标母版：渐变底 + 大号角色
    legacy_master = radial_bg(1024).convert('RGBA')
    legacy_master.alpha_composite(
        fit(readme, 1024, LEGACY_FILL, use_diagonal=False))

    # 自适应前景母版：透明底 + 缩进安全圆的角色
    fg_master = fit(readme, 1296, 0.0, use_diagonal=True)

    for name, scale in DENSITIES:
        d = f'{ANDROID_RES}/mipmap-{name}'
        os.makedirs(d, exist_ok=True)

        legacy_px = int(round(48 * scale))
        legacy_master.resize((legacy_px, legacy_px), Image.LANCZOS).convert(
            'RGB').save(f'{d}/ic_launcher.png', optimize=True)

        fg_px = int(round(108 * scale))
        fg_master.resize((fg_px, fg_px), Image.LANCZOS).save(
            f'{d}/ic_launcher_foreground.png', optimize=True)

        print(f'{name}: ic_launcher {legacy_px}px, foreground {fg_px}px')

    write_xml()

    # ---- 核对图：自适应图标在各种遮罩下的样子 + 小尺寸辨识度
    adaptive = radial_bg(1024).convert('RGBA')
    adaptive.alpha_composite(fit(readme, 1024, 0.0, use_diagonal=True))

    slot, pad, label_h = 300, 22, 30
    cols = 4
    sheet_h = slot + label_h + pad * 2 + 120
    sheet = Image.new('RGB', (pad + cols * (slot + pad), sheet_h), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)

    tiles = [
        ('方形图标  API<26', lambda s: legacy_master.resize((s, s), Image.LANCZOS)),
        ('自适应 · 圆形遮罩', lambda s: mask_icon(adaptive, 'circle', s)),
        ('自适应 · 圆角方', lambda s: mask_icon(adaptive, 'squircle', s)),
        ('自适应 · 水滴形', lambda s: mask_icon(adaptive, 'teardrop', s)),
    ]
    for i, (label, render) in enumerate(tiles):
        x = pad + i * (slot + pad)
        icon = render(slot)
        sheet.paste(icon.convert('RGB'), (x, pad), icon.convert('RGBA'))
        draw_text(draw, (x, pad + slot + 8), label, 16)

    # 底部：48 / 96 / 144px 三档，检查小尺寸下还认不认得出
    y0 = pad + slot + label_h + pad
    draw_text(draw, (pad, y0), '小尺寸辨识度（48 / 96 / 144 px）', 16)
    x = pad
    for px in (48, 96, 144):
        small = mask_icon(adaptive, 'circle', px)
        sheet.paste(small.convert('RGB'), (x, y0 + 26), small.convert('RGBA'))
        x += px + 26

    sheet.save(PREVIEW)
    print('written ->', PREVIEW)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
