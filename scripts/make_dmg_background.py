#!/usr/bin/env python3
import sys
import os
from PIL import Image, ImageDraw, ImageFont

def generate_background(scale, out_path):
    # Viewport is 660 x 436. Canvas extends to 1400 x 800 so stretching never exposes white.
    w_view = 660 * scale
    h_view = 436 * scale
    canvas_w = 1400 * scale
    canvas_h = 800 * scale

    bg_color = (12, 13, 16) # #0c0d10 dark theme
    im = Image.new('RGB', (canvas_w, canvas_h), color=bg_color)
    draw = ImageDraw.Draw(im)

    # Top border line across entire canvas
    draw.line([(0, 60 * scale), (canvas_w, 60 * scale)], fill=(26, 28, 35), width=1 * scale)

    mono_font = None
    mono_bold = None
    title_font = None
    try:
        mono_font = ImageFont.truetype('/System/Library/Fonts/SFNSMono.ttf', 11 * scale)
        mono_bold = ImageFont.truetype('/System/Library/Fonts/SFNSMono.ttf', 12 * scale)
        title_font = ImageFont.truetype('/System/Library/Fonts/SFNSMono.ttf', 15 * scale)
    except:
        try:
            mono_font = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 11 * scale)
            mono_bold = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 12 * scale)
            title_font = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 15 * scale)
        except:
            mono_font = ImageFont.load_default()
            mono_bold = ImageFont.load_default()
            title_font = ImageFont.load_default()

    # Title header within 660 viewport
    draw.text((36 * scale, 22 * scale), "desKTop // v1.0.0", fill=(240, 240, 245), font=title_font)
    
    sub = "NATIVE MACOS COMPANION"
    sub_bbox = draw.textbbox((0, 0), sub, font=mono_font)
    draw.text((w_view - (sub_bbox[2] - sub_bbox[0]) - 36 * scale, 25 * scale), sub, fill=(110, 115, 128), font=mono_font)

    # Center is at x=330 between desKTop.app (x=160) and Applications (x=500)
    mid_x = 330 * scale
    arrow_color = (43, 114, 255) # Tezos Blue #2B72FF
    y_mid = 195 * scale
    x_start = 275 * scale
    x_end = 375 * scale
    line_w = 3 * scale

    draw.line([(x_start, y_mid), (x_end, y_mid)], fill=arrow_color, width=line_w)
    # Arrowhead
    head_len = 10 * scale
    head_h = 7 * scale
    draw.polygon([
        (x_end, y_mid - head_h),
        (x_end + head_len, y_mid),
        (x_end, y_mid + head_h)
    ], fill=arrow_color)

    # Label below arrow
    label = "DRAG TO INSTALL"
    bbox = draw.textbbox((0, 0), label, font=mono_bold)
    tw = bbox[2] - bbox[0]
    draw.text((mid_x - int(tw / 2), y_mid + 18 * scale), label, fill=(160, 165, 178), font=mono_bold)

    # Bottom line
    y_bot = 390 * scale
    draw.line([(0, y_bot), (canvas_w, y_bot)], fill=(26, 28, 35), width=1 * scale)
    
    # Bottom attribution
    foot_l = "<< a FAFOlab joint >>"
    foot_r = "zero keys · zero telemetry · public domain"
    draw.text((36 * scale, y_bot + 12 * scale), foot_l, fill=(110, 115, 128), font=mono_font)
    
    f_bbox = draw.textbbox((0, 0), foot_r, font=mono_font)
    f_w = f_bbox[2] - f_bbox[0]
    draw.text((w_view - f_w - 36 * scale, y_bot + 12 * scale), foot_r, fill=(90, 95, 105), font=mono_font)

    im.save(out_path)

if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else '/tmp'
    generate_background(1, os.path.join(out_dir, 'bg.png'))
    generate_background(2, os.path.join(out_dir, 'bg@2x.png'))
    print("DMG backgrounds generated.")
