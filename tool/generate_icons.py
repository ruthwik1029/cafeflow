"""Reproduce CafeFlow's original geometric launcher mark (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (1024, 1024), '#FF4B2F')
draw = ImageDraw.Draw(image)
ink = '#20242A'
# The complete cup fits inside Android/Web maskable safe zones.
draw.rounded_rectangle((580, 340, 770, 590), radius=82, outline=ink, width=52)
draw.rounded_rectangle((280, 335, 640, 665), radius=75, fill=ink)
draw.rectangle((280, 335, 640, 435), fill=ink)
draw.rounded_rectangle((255, 710, 710, 748), radius=18, fill=ink)
for x in (345, 455, 565):
    draw.rounded_rectangle((x, 220, x + 28, 285), radius=14, fill=ink)

targets = {'web/favicon.png': 48, 'web/icons/Icon-192.png': 192,
           'web/icons/Icon-512.png': 512, 'web/icons/Icon-maskable-192.png': 192,
           'web/icons/Icon-maskable-512.png': 512}
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    targets[f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'] = size
for target, size in targets.items():
    image.resize((size, size), Image.Resampling.LANCZOS).save(ROOT / target)
image.save(ROOT / 'windows/runner/resources/app_icon.ico',
           sizes=[(16,16), (24,24), (32,32), (48,48), (64,64), (128,128), (256,256)])
print(f'Generated {len(targets) + 1} platform icons.')
