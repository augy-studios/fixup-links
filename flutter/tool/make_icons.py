"""Makes the desktop apps' icons from the site's logo (main-site/UFX-512.png):

  windows/runner/resources/app_icon.ico         the app, 16 to 256 px
  macos/Runner/Assets.xcassets/AppIcon.appiconset   the app, macOS's rounded square
  assets/desktop/icon.png                       the app on Linux (512 px) and in the welcome window
  assets/desktop/tray.ico, tray.png             the tray icon: the logo's round badge, no backdrop
  assets/desktop/tray_template.png              macOS's menu bar: the badge's silhouette, black on
                                                clear, which macOS tints to fit the bar

    python tool/make_icons.py        (from flutter/)
"""
import os

from PIL import Image, ImageDraw, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
logo = Image.open(os.path.join(root, '..', 'main-site', 'UFX-512.png')).convert('RGBA')
logo_width = logo.width


def rounded(image, radius):
    """Returns a copy of the image with its corners rounded off (clear outside the corners)."""
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    result = Image.new('RGBA', image.size, (0, 0, 0, 0))
    result.paste(image, (0, 0), mask)
    return result


# The round badge: the yellow circle and what's on it (the sparkles fall outside and go).
def badge(size):
    big = logo.resize((1024, 1024), Image.LANCZOS)
    center_x = 512 * 0.977
    center_y = 512 * 1.08
    radius = 512 * 0.66
    mask = Image.new('L', big.size, 0)
    ImageDraw.Draw(mask).ellipse(
        (center_x - radius, center_y - radius, center_x + radius, center_y + radius), fill=255)
    cut = Image.new('RGBA', big.size, (0, 0, 0, 0))
    cut.paste(big, (0, 0), mask)
    box = (int(center_x - radius), int(center_y - radius), int(center_x + radius), int(center_y + radius))
    return cut.crop(box).resize((size, size), Image.LANCZOS)


os.makedirs(os.path.join(root, 'assets', 'desktop'), exist_ok=True)

# Windows: the app's icon, the full square logo with softened corners.
app = rounded(logo, 96)
app.save(os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# macOS: the rounded square on a transparent margin, as macOS app icons are drawn (824 of 1024).
mac_dir = os.path.join(root, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
inner = rounded(logo.resize((824, 824), Image.LANCZOS), 185)
shadow = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((100, 112, 924, 936), radius=185, fill=(0, 0, 0, 70))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(12)))
canvas.paste(inner, (100, 100), inner)
for icon_size in (16, 32, 64, 128, 256, 512, 1024):
    canvas.resize((icon_size, icon_size), Image.LANCZOS).save(os.path.join(mac_dir, f'app_icon_{icon_size}.png'))

# Linux, and the welcome window.
rounded(logo, 96).save(os.path.join(root, 'assets', 'desktop', 'icon.png'))

# The tray: the badge alone reads at 16 px where the whole square doesn't.
tray_badge = badge(256)
tray_badge.save(os.path.join(root, 'assets', 'desktop', 'tray.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])
tray_badge.resize((64, 64), Image.LANCZOS).save(os.path.join(root, 'assets', 'desktop', 'tray.png'))

# macOS's menu bar: a template image, black where the badge is, with the hand and wrench cut out
# so it's still the logo at 22 px.
menu_bar_badge = badge(88)
badge_pixels = menu_bar_badge.load()
template = Image.new('RGBA', menu_bar_badge.size, (0, 0, 0, 0))
template_pixels = template.load()
for row in range(menu_bar_badge.height):
    for column in range(menu_bar_badge.width):
        red, green, blue, alpha = badge_pixels[column, row]
        if alpha < 40:
            continue
        light = (red + green + blue) / 3
        # The wrench (dark grey) and the outline stay; the yellow and the hand go clear.
        if light < 110:
            template_pixels[column, row] = (0, 0, 0, 255)
        elif red > 200 and green > 150 and blue < 120:
            template_pixels[column, row] = (0, 0, 0, 120)
template.resize((44, 44), Image.LANCZOS).save(os.path.join(root, 'assets', 'desktop', 'tray_template.png'))
print('icons written')
