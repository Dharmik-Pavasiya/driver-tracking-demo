"""Package captured UI screenshots into an explicitly edited walkthrough GIF."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

root = Path(__file__).resolve().parents[1]
captions = [
    ("01-ready", "1. Start/stop simulated GPS tracking"),
    ("02-offline-queued", "2. Offline: 34 points committed locally, zero uploads"),
    ("03-auto-synced", "3. Reconnected: all 34 points synchronized automatically"),
    ("04-upload-failed", "4. API returns 503: failed points stay queued for retry"),
    ("05-retry-recovered", "5. API restored: retries succeed; 40 unique points synchronized"),
]
font_path = Path("C:/Windows/Fonts/segoeui.ttf")
font = ImageFont.truetype(str(font_path), 25) if font_path.exists() else ImageFont.load_default()
frames = []
for name, caption in captions:
    screenshot = Image.open(root / "docs" / "frames" / f"{name}.jpg").convert("RGB")
    frame = Image.new("RGB", (1280, 1000), "#F4F6F5")
    draw = ImageDraw.Draw(frame)
    draw.rectangle((0, 0, 1280, 80), fill="#146B52")
    draw.text((24, 22), caption, font=font, fill="white")
    screenshot = ImageOps.contain(screenshot, (1280, 920))
    frame.paste(screenshot, ((1280 - screenshot.width) // 2, 80))
    frames.append(frame)
frames[0].save(root / "docs" / "demo.gif", save_all=True, append_images=frames[1:], duration=5000, loop=0)
print(f"Saved {root / 'docs' / 'demo.gif'} (5 captured frames, 25 seconds)")
