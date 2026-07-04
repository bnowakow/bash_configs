#!/usr/bin/env python3
"""
Convert one very tall PNG into a multi-page A4 PDF.

The image is scaled to fit the printable width of A4, then sliced vertically
into as many pages as needed.

Requires:
    cd utilities && make install-requirements
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ModuleNotFoundError as error:
    raise SystemExit(
        "Missing dependency: Pillow. Install it with: cd utilities && make install-requirements"
    ) from error


A4_WIDTH_MM = 210.0
A4_HEIGHT_MM = 297.0
MM_PER_INCH = 25.4
DEFAULT_DPI = 300
FOOTER_HEIGHT_MM = 8.0
FOOTER_FONT_SIZE_PT = 10


def mm_to_px(mm: float, dpi: int) -> int:
    return round(mm / MM_PER_INCH * dpi)


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return parsed


def load_footer_font(dpi: int) -> ImageFont.ImageFont:
    font_size_px = max(12, round(FOOTER_FONT_SIZE_PT / 72 * dpi))
    try:
        return ImageFont.load_default(size=font_size_px)
    except TypeError:
        return ImageFont.load_default()


def draw_footer(
    page: Image.Image,
    page_number: int,
    page_count: int,
    dpi: int,
    margin_px: int,
    footer_height_px: int,
) -> None:
    draw = ImageDraw.Draw(page)
    font = load_footer_font(dpi)
    text = f"Page {page_number} of {page_count}"
    text_box = draw.textbbox((0, 0), text, font=font)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    x = (page.width - text_width) // 2
    y = page.height - margin_px - ((footer_height_px + text_height) // 2)
    draw.text((x, y), text, fill="black", font=font)


def build_pages(
    image: Image.Image,
    dpi: int,
    margin_mm: float,
    overlap_mm: float,
    background: str,
) -> list[Image.Image]:
    page_width_px = mm_to_px(A4_WIDTH_MM, dpi)
    page_height_px = mm_to_px(A4_HEIGHT_MM, dpi)
    margin_px = mm_to_px(margin_mm, dpi)
    overlap_px = mm_to_px(overlap_mm, dpi)
    footer_height_px = mm_to_px(FOOTER_HEIGHT_MM, dpi)

    printable_width_px = page_width_px - (2 * margin_px)
    printable_height_px = page_height_px - (2 * margin_px) - footer_height_px

    if printable_width_px <= 0 or printable_height_px <= 0:
        raise ValueError("Margins are too large for A4 paper")

    if overlap_px >= printable_height_px:
        raise ValueError("Overlap must be smaller than the printable page height")

    source = image.convert("RGB")
    scaled_height_px = math.ceil(source.height * printable_width_px / source.width)
    scaled = source.resize((printable_width_px, scaled_height_px), Image.Resampling.LANCZOS)

    pages: list[Image.Image] = []
    stride_px = printable_height_px - overlap_px

    top = 0
    while top < scaled.height:
        bottom = min(top + printable_height_px, scaled.height)
        slice_image = scaled.crop((0, top, printable_width_px, bottom))

        page = Image.new("RGB", (page_width_px, page_height_px), background)
        page.paste(slice_image, (margin_px, margin_px))
        pages.append(page)

        if bottom == scaled.height:
            break
        top += stride_px

    page_count = len(pages)
    for page_number, page in enumerate(pages, start=1):
        draw_footer(page, page_number, page_count, dpi, margin_px, footer_height_px)

    return pages


def convert_png_to_pdf(
    input_path: Path,
    output_path: Path,
    dpi: int,
    margin_mm: float,
    overlap_mm: float,
    background: str,
) -> int:
    with Image.open(input_path) as image:
        pages = build_pages(image, dpi, margin_mm, overlap_mm, background)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    first_page, *remaining_pages = pages
    first_page.save(
        output_path,
        "PDF",
        resolution=dpi,
        save_all=True,
        append_images=remaining_pages,
    )

    return len(pages)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Split a very tall PNG into a multi-page A4 PDF.",
    )
    parser.add_argument("input_png", type=Path, help="Path to the source PNG")
    parser.add_argument("output_pdf", type=Path, help="Path for the generated PDF")
    parser.add_argument(
        "--dpi",
        type=int,
        default=DEFAULT_DPI,
        help=f"PDF/image DPI. Default: {DEFAULT_DPI}",
    )
    parser.add_argument(
        "--margin-mm",
        type=positive_float,
        default=0.0,
        help="Page margin in millimeters. Default: 0",
    )
    parser.add_argument(
        "--overlap-mm",
        type=positive_float,
        default=0.0,
        help="Vertical overlap between pages in millimeters. Default: 0",
    )
    parser.add_argument(
        "--background",
        default="white",
        help="Page background color understood by Pillow. Default: white",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_png = args.input_png.expanduser()
    output_pdf = args.output_pdf.expanduser()

    if args.dpi <= 0:
        raise SystemExit("--dpi must be greater than zero")
    if not input_png.exists():
        raise SystemExit(f"Input file does not exist: {input_png}")

    page_count = convert_png_to_pdf(
        input_path=input_png,
        output_path=output_pdf,
        dpi=args.dpi,
        margin_mm=args.margin_mm,
        overlap_mm=args.overlap_mm,
        background=args.background,
    )

    print(f"Wrote {page_count} A4 page(s) to {output_pdf}")


if __name__ == "__main__":
    main()
