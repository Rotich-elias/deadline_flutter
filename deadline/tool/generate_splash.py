#!/usr/bin/env python3
"""Generate the native splash artwork that matches lib/ui/loading_page.dart.

The loading page centres a block of widgets in the window and draws it at fixed
sizes (it opts out of the system font scale). This script reproduces that block
as a transparent PNG, so Android can show the branded screen from the very first
frame and the hand-off to Flutter is a straight continuation.

Offsets are in dp, measured from the *canvas centre*, which is where the block
sits in the window. They were read off a device frame of the running loading
page (Galaxy Note 9, 1080x2220 @ dpr 1.925), e.g. the title ink top at
y=1135px is (+13.0dp) below the window centre at y=1110px.

Run from the project root, then regenerate the Android drawables:

    python3 tool/generate_splash.py
    dart run flutter_native_splash:create
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = Path.home() / (
    ".pub-cache/hosted/pub.dev/shared_preferences-2.5.5/extension/devtools/build/"
    "assets/packages/devtools_app_shared/fonts/Roboto"
)

SCALE = 4  # authored at 4x dp; flutter_native_splash treats the source as xxxhdpi

# Colours from lib/theme.dart (dark palette) and the accent used on the page.
BG = (14, 19, 27)  # preview background only; the PNG keeps its alpha
SURFACE = (23, 31, 43)
LINE = (40, 51, 68)
TEXT = (233, 238, 245)
MUTED = (140, 154, 173)
ACCENT = (92, 141, 239)

# Canvas in dp. Wider and taller than the block so bucket rounding cannot clip
# it; the canvas centre is the window centre.
CANVAS_W = 260.0
CANVAS_H = 320.0

# --- block geometry, dp relative to the canvas centre -----------------------
TILE_SIZE = 92.0
TILE_RADIUS = 24.0
TILE_CENTER_Y = -86.6      # tile box centred here
LOGO_INSET = 18.0
GLOW_SIZE = 124.0

TITLE_TOP = 13.0           # ink top
TITLE_SIZE = 25.0
TITLE_TRACKING = -0.5

SUBTITLE_TOP = 51.4
SUBTITLE_SIZE = 13.5
SUBTITLE_TRACKING = 0.25   # Material 3 body letter spacing, also set in the widget

SPINNER_TOP = 100.0        # box top, stroke included
SPINNER_SIZE = 20.0
SPINNER_STROKE = 2.2

STATUS_TOP = 138.2
STATUS_SIZE = 12.5
STATUS_TRACKING = 0.25
STATUS_TEXT = "Getting things ready"


def px(value: float) -> float:
    return value * SCALE


def load_font(weight: str, size_dp: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / weight), int(round(px(size_dp))))


def draw_tracked(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    origin: tuple[float, float],
    fill: tuple[int, int, int],
    tracking_dp: float,
) -> None:
    """Draw left-to-right with letter spacing, like Flutter's letterSpacing."""
    x, y = origin
    tracking = px(tracking_dp)
    for char in text:
        draw.text((x, y), char, font=font, fill=fill)
        x += font.getlength(char) + tracking


def ink_bbox(
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    tracking_dp: float = 0.0,
) -> Image.Image:
    """Render a string on its own layer so the glyph bounds can be measured."""
    layer = Image.new("RGBA", (int(px(CANVAS_W)), int(px(CANVAS_H))), (0, 0, 0, 0))
    draw_tracked(ImageDraw.Draw(layer), text, font, (0, 0), (*fill, 255), tracking_dp)
    box = layer.getbbox()
    assert box is not None, f"no ink for {text!r}"
    return layer.crop(box)  # tight glyph bitmap


def paste_centred(canvas: Image.Image, glyphs: Image.Image, ink_top_dp: float) -> None:
    """Paste tight glyphs with their ink top at ink_top_dp, ink centred in x."""
    ink_top = px(CANVAS_H / 2 + ink_top_dp)
    left = (canvas.width - glyphs.width) / 2
    canvas.alpha_composite(glyphs, (int(round(left)), int(round(ink_top))))


def radial_glow(size_px: int, colour: tuple[int, int, int], max_alpha: float) -> Image.Image:
    mask = Image.radial_gradient("L").resize((size_px, size_px), Image.LANCZOS)
    # radial_gradient is black at the centre and white at the edge.
    alpha = mask.point(lambda v: int(max_alpha * 255 * (1 - v / 255)))
    glow = Image.new("RGBA", (size_px, size_px), (*colour, 0))
    glow.putalpha(alpha)
    return glow


def main() -> None:
    canvas = Image.new("RGBA", (int(px(CANVAS_W)), int(px(CANVAS_H))), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    centre_x = canvas.width / 2

    tile_size = px(TILE_SIZE)
    tile_centre_y = px(CANVAS_H / 2 + TILE_CENTER_Y)
    tile_top = tile_centre_y - tile_size / 2

    # Soft accent glow behind the logo tile.
    glow_px = int(px(GLOW_SIZE))
    canvas.alpha_composite(
        radial_glow(glow_px, ACCENT, 0.15),
        (
            int(round(centre_x - glow_px / 2)),
            int(round(tile_centre_y - glow_px / 2)),
        ),
    )

    # Rounded logo tile with a 1dp border, same as the LoadingPage widget.
    tile = Image.new("RGBA", (int(tile_size), int(tile_size)), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(
        (0, 0, tile.width - 1, tile.height - 1),
        radius=px(TILE_RADIUS),
        fill=(*SURFACE, 255),
        outline=(*LINE, 255),
        width=int(px(1)),
    )
    canvas.alpha_composite(tile, (int(round(centre_x - tile_size / 2)), int(round(tile_top))))

    # App icon inside the tile.
    icon = Image.open(ROOT / "assets/icon/icon.png").convert("RGBA")
    icon_size = int(px(TILE_SIZE - LOGO_INSET * 2))
    icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
    canvas.alpha_composite(
        icon,
        (
            int(round(centre_x - icon_size / 2)),
            int(round(tile_top + px(LOGO_INSET))),
        ),
    )

    paste_centred(
        canvas,
        ink_bbox("Deadlines&Notes", load_font("Roboto-Bold.ttf", TITLE_SIZE), TEXT, TITLE_TRACKING),
        TITLE_TOP,
    )
    paste_centred(
        canvas,
        ink_bbox("Sorting what is due next.", load_font("Roboto-Regular.ttf", SUBTITLE_SIZE), MUTED, SUBTITLE_TRACKING),
        SUBTITLE_TOP,
    )

    # Spinner: track ring plus the accent arc the page would show at rest.
    spinner_size = px(SPINNER_SIZE)
    stroke = px(SPINNER_STROKE)
    spinner_top = px(CANVAS_H / 2 + SPINNER_TOP)
    ring = (
        int(round(centre_x - spinner_size / 2)),
        int(round(spinner_top)),
        int(round(centre_x + spinner_size / 2)),
        int(round(spinner_top + spinner_size)),
    )
    draw.ellipse(ring, outline=(*LINE, 255), width=int(round(stroke)))
    inset = stroke / 2
    draw.arc(
        (ring[0] + inset, ring[1] + inset, ring[2] - inset, ring[3] - inset),
        start=-90,
        end=180,
        fill=(*ACCENT, 255),
        width=int(round(stroke)),
    )

    paste_centred(
        canvas,
        ink_bbox(STATUS_TEXT, load_font("Roboto-Regular.ttf", STATUS_SIZE), MUTED, STATUS_TRACKING),
        STATUS_TOP,
    )

    out = ROOT / "assets/splash/splash_brand.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"wrote {out} ({canvas.width}x{canvas.height} px, {CANVAS_W}x{CANVAS_H} dp)")

    # Flattened preview on the splash background colour, for eyeballing.
    preview = Image.new("RGBA", canvas.size, (*BG, 255))
    preview.alpha_composite(canvas)
    preview.convert("RGB").save(ROOT / "assets/splash/splash_brand_preview.png")


if __name__ == "__main__":
    main()
