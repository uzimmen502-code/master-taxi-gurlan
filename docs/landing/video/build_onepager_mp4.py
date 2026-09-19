from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

OUT = Path(r"c:\projects\ava_gurlan\docs\landing\video")
FRAMES = OUT / "frames"
FRAMES.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080
BG = (11, 14, 20)
CARD = (19, 26, 34)
BORDER = (37, 43, 54)
MUTED = (148, 163, 184)
TEXT = (226, 232, 240)
WHITE = (255, 255, 255)
GREEN = (34, 197, 94)
PUB_BG = (30, 42, 30)
ACCENT = (250, 204, 21)
AVA_G = (20, 92, 43)


def font(size, bold=False):
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\tahoma.ttf",
    ]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_BRAND = font(72, True)
F_H1 = font(54, True)
F_H2 = font(40, True)
F_BODY = font(32)
F_SMALL = font(24)
F_TINY = font(20)


def new_slide():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 8), fill=GREEN)
    return img, d


def draw_brand(d, y=48):
    d.text((80, y), "AVA", font=F_BRAND, fill=GREEN)
    d.text((80, y + 78), "платформа сиз учун", font=F_SMALL, fill=MUTED)


def wrap(d, text, fnt, max_w):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if d.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_block(d, x, y, text, fnt, fill, max_w, gap=10):
    for line in wrap(d, text, fnt, max_w):
        d.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + gap
    return y


slides = []

img, d = new_slide()
draw_brand(d)
d.text((80, 280), "ЮК БИРЖАСИ", font=F_H2, fill=ACCENT)
d.text((80, 350), "Туман ичида", font=F_H1, fill=WHITE)
text_block(
    d,
    80,
    450,
    "Жойлашув + иш вақти бўйича юк. Онлайн тугмаси йўқ.",
    F_BODY,
    TEXT,
    1500,
)
d.text((80, 980), "One-pager · код асосида", font=F_TINY, fill=MUTED)
slides.append(img)

img, d = new_slide()
draw_brand(d)
d.text((80, 200), "Қандай бошланади", font=F_H1, fill=WHITE)
for i, s in enumerate(
    [
        "1. AVA → Юк биржаси",
        "2. Тасма: Туман ичида | Шаҳарлараро",
        "3. Қидирувчи учун GPS мажбурий",
    ]
):
    y = 320 + i * 115
    d.rounded_rectangle(
        (80, y, 1700, y + 90), radius=16, fill=CARD, outline=BORDER, width=2
    )
    d.text((110, y + 24), s, font=F_BODY, fill=TEXT)
slides.append(img)

img, d = new_slide()
draw_brand(d)
d.text((80, 200), "Эълон бериш", font=F_H1, fill=WHITE)
text_block(
    d,
    80,
    300,
    "«Юк ташиш учун эълон» → GPS + иш вақти + машина, рақам, кг, кузов, қамров.",
    F_BODY,
    TEXT,
    1600,
)
d.rounded_rectangle((80, 520, 920, 620), radius=18, fill=PUB_BG, outline=GREEN, width=3)
d.text((170, 548), "Юк ташиш учун эълон", font=F_BODY, fill=WHITE)
d.text((80, 680), "Фон #1E2A1E · чегара #22C55E · матн оқ", font=F_SMALL, fill=MUTED)
d.text(
    (80, 740),
    "TTL: биринчи эълон 60 кун, кейингилари 10 кун",
    font=F_BODY,
    fill=ACCENT,
)
slides.append(img)

img, d = new_slide()
draw_brand(d)
d.text((80, 200), "Қачон кўринади", font=F_H1, fill=WHITE)
rules = [
    ("GPS", "Жойлашув бор"),
    ("TTL", "Муддат ўтмаган"),
    ("Вақт", "Ҳозир иш вақти ичида"),
]
for i, (title, sub) in enumerate(rules):
    x = 80 + i * 560
    d.rounded_rectangle(
        (x, 360, x + 520, 620), radius=20, fill=CARD, outline=BORDER, width=2
    )
    d.text((x + 40, 420), title, font=F_H2, fill=GREEN)
    text_block(d, x + 40, 500, sub, F_BODY, TEXT, 440)
slides.append(img)

img, d = new_slide()
draw_brand(d)
d.text((80, 180), "Рўйхат", font=F_H1, fill=WHITE)
d.rounded_rectangle((80, 300, 520, 370), radius=40, fill=(48, 42, 18), outline=ACCENT, width=2)
d.text((170, 318), "Туман ичида", font=F_BODY, fill=ACCENT)
d.rounded_rectangle((560, 300, 1000, 370), radius=40, fill=CARD, outline=BORDER, width=2)
d.text((650, 318), "Шаҳарлараро", font=F_BODY, fill=MUTED)


def truck(y, title, meta, mine=False):
    d.rounded_rectangle((80, y, 1500, y + 130), radius=14, fill=CARD, outline=BORDER, width=2)
    stripe = ACCENT if mine else GREEN
    d.rectangle((80, y, 88, y + 130), fill=stripe)
    d.text((120, y + 28), title, font=F_BODY, fill=WHITE)
    d.text((120, y + 78), meta, font=F_SMALL, fill=MUTED)


truck(420, "Лабо · 01 A 123 BC", "2.4 км · иш вақти 08:00–20:00 · бўш", False)
truck(580, "Газель · 90 B 456 CD", "5.1 км · қамров 20 км · бўш  (меники)", True)
d.text(
    (80, 760),
    "Масофа бўйича саралаш · қўнғироқ · рейтинг юлдузи йўқ",
    font=F_BODY,
    fill=TEXT,
)
slides.append(img)

img, d = new_slide()
draw_brand(d)
d.text((80, 320), "Туман ичида юкни", font=F_H1, fill=WHITE)
d.text((80, 400), "AVA да бошланг", font=F_H1, fill=GREEN)
text_block(
    d,
    80,
    520,
    "Илова: Юк биржаси → Туман ичида. GPS ни ёқинг.",
    F_BODY,
    TEXT,
    1500,
)
d.rounded_rectangle((80, 700, 700, 820), radius=18, fill=AVA_G)
d.text((160, 735), "AVA ни очиш", font=F_H2, fill=WHITE)
d.text((80, 980), "© AVA · платформа сиз учун", font=F_TINY, fill=MUTED)
slides.append(img)

paths = []
for i, slide in enumerate(slides, 1):
    p = FRAMES / f"slide_{i:02d}.png"
    slide.save(p, "PNG")
    paths.append(p)
    print("wrote", p)

ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
mp4 = OUT / "ava-tuman-ichida-onepager.mp4"
hold = 3.2
n = len(paths)

# -loop 1 -t HOLD for each image, then concat
cmd = [ffmpeg, "-y"]
for p in paths:
    cmd += ["-loop", "1", "-t", str(hold), "-i", str(p)]

filters = "".join(f"[{i}:v]scale=1920:1080,setsar=1,fps=30[v{i}];" for i in range(n))
filters += "".join(f"[v{i}]" for i in range(n))
filters += f"concat=n={n}:v=1:a=0[outv]"

cmd += [
    "-filter_complex",
    filters,
    "-map",
    "[outv]",
    "-c:v",
    "libx264",
    "-pix_fmt",
    "yuv420p",
    "-movflags",
    "+faststart",
    str(mp4),
]

print("running ffmpeg…")
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode != 0:
    print(r.stderr[-1500:])
    raise SystemExit(r.returncode)
print("OK", mp4, mp4.stat().st_size)
