"""Renders the PlateLog icon set into assets/icon/.

Run with any Python that has Pillow + numpy:
    python tool/make_icon.py
then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
TEAL_HI, TEAL_LO = "#11858F", "#074E55"   # around the app seed #0B6E77
COPPER_HI, COPPER_LO = "#F0C892", "#C98E4F"
WHITE = "#F7F4EE"
SS = 4  # supersampling

hexc = lambda h: np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32)

# Mark geometry in unit coords (x0, x1, height), centred on the bar at y=0.5.
# A barbell sleeve: small outer plate -> big inner plate -> collar -> bar.
PLATES = [(0.11, 0.25, 0.40), (0.285, 0.455, 0.60), (0.49, 0.69, 0.82)]
COLLAR = (0.72, 0.78, 0.26)
BAR = (0.06, 0.93, 0.08)


def gradient(n, top, bottom):
    t = np.linspace(0, 1, n, dtype=np.float32)[:, None, None]
    a = hexc(top) + (hexc(bottom) - hexc(top)) * t
    return Image.fromarray(np.repeat(a, n, axis=1).astype(np.uint8), "RGB").convert("RGBA")


def draw_mark(img, box, shadow=True):
    """Draws the mark into `box` (x, y, size) of `img` (already supersampled)."""
    bx, by, bs = box
    n = img.size[0]
    X = lambda u: bx + u * bs
    Y = lambda v: by + v * bs

    def rect(d, x0, x1, h, r):
        d.rounded_rectangle([X(x0), Y(0.5 - h / 2), X(x1), Y(0.5 + h / 2)], radius=r * bs, fill=255)

    white = Image.new("L", (n, n), 0)
    copper = Image.new("L", (n, n), 0)
    dw, dc = ImageDraw.Draw(white), ImageDraw.Draw(copper)
    rect(dw, BAR[0], BAR[1], BAR[2], BAR[2] / 2)
    rect(dw, *COLLAR, 0.015)
    for x0, x1, h in PLATES[:-1]:
        rect(dw, x0, x1, h, 0.035)
    rect(dc, *PLATES[-1], 0.04)

    if shadow:
        sh = Image.new("L", (n, n), 0)
        sh.paste(255, mask=white)
        sh.paste(255, mask=copper)
        sh = sh.filter(ImageFilter.GaussianBlur(bs * 0.03))
        off = int(bs * 0.025)
        layer = Image.new("RGBA", (n, n), (0, 20, 24, 0))
        layer.putalpha(sh.point(lambda a: a * 0.45))
        img.alpha_composite(layer, (0, off))

    img.paste(Image.new("RGBA", (n, n), WHITE), mask=white)
    img.paste(gradient(n, COPPER_HI, COPPER_LO), mask=copper)
    return img


def save(img, name, size):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 1024 * SS

    # Full icon (iOS, legacy Android, Play Store 512): gradient + mark.
    full = gradient(n, TEAL_HI, TEAL_LO)
    draw_mark(full, (n * 0.17, n * 0.17, n * 0.66))
    save(full, "app_icon.png", 1024)
    save(full, "play_store_512.png", 512)

    # Adaptive foreground: mark inside the 66% safe zone, transparent.
    fg = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw_mark(fg, (n * 0.20, n * 0.20, n * 0.60))
    save(fg, "app_icon_foreground.png", 1024)

    # Monochrome (Android 13 themed icons): plain silhouette.
    mono = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw_mark(mono, (n * 0.20, n * 0.20, n * 0.60), shadow=False)
    a = mono.getchannel("A")
    mono = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    mono.putalpha(a)
    save(mono, "app_icon_monochrome.png", 1024)

    # Splash logo: mark only (Android 12 splash crops to a circle, keep it small).
    sp = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw_mark(sp, (n * 0.2, n * 0.2, n * 0.6), shadow=False)
    save(sp, "splash_logo.png", 1024)


if __name__ == "__main__":
    main()
