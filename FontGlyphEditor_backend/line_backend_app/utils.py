from __future__ import annotations

import hashlib
import os
import re
import zipfile
from pathlib import Path
from typing import Dict, Iterable, List, Tuple
from PIL import Image, ImageFilter

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
FONT_EXTENSIONS = {".ttf", ".otf", ".ttc"}


def safe_filename(name: str, default: str = "file") -> str:
    base = os.path.basename(name or default)
    base = re.sub(r"[^0-9A-Za-z_.\-\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]", "_", base)
    return base or default


def infer_character_from_filename(filename: str) -> str | None:
    stem = Path(filename).stem.strip()
    if not stem:
        return None
    if len(stem) == 1:
        return stem
    # Common names like U+96E8.png or uni96E8.png
    m = re.fullmatch(r"(?:U\+|u\+|uni)([0-9A-Fa-f]{4,6})", stem)
    if m:
        try:
            return chr(int(m.group(1), 16))
        except Exception:
            return None
    return None


def normalize_hex_color(value: str, fallback: str = "#000000") -> str:
    if not value:
        return fallback
    value = value.strip()
    if not value.startswith("#"):
        value = "#" + value
    if re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        return value.upper()
    return fallback


def file_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:16]


def extract_zip_images(zip_path: Path, out_dir: Path) -> Dict[str, Path]:
    result: Dict[str, Path] = {}
    with zipfile.ZipFile(zip_path, "r") as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            filename = safe_filename(Path(info.filename).name)
            if Path(filename).suffix.lower() not in IMAGE_EXTENSIONS:
                continue
            raw = zf.read(info.filename)
            digest = file_hash(raw)
            out_path = out_dir / f"{digest}_{filename}"
            out_path.write_bytes(raw)
            result[filename] = out_path
    return result


def prepare_image(src: Path, weight: float = 0.0, target_height: int | None = None) -> bytes:
    """Return optimized PNG bytes.

    target_height is important for sbix color glyphs: Apple renderers draw
    the embedded bitmap using its pixel dimensions, so a patch's size slider
    must physically resize the PNG before the image is written into the font.
    Weight >0 expands alpha; weight <0 erodes alpha after resizing.
    """
    img = Image.open(src).convert("RGBA")

    if target_height is not None:
        target_height = max(1, int(target_height))
        w, h = img.size
        if h > 0 and target_height != h:
            target_width = max(1, int(round(w * target_height / h)))
            img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)

    if weight != 0:
        r, g, b, a = img.split()
        radius = max(1, int(abs(weight)))
        if weight > 0:
            a = a.filter(ImageFilter.MaxFilter(radius * 2 + 1))
        else:
            a = a.filter(ImageFilter.MinFilter(radius * 2 + 1))
        img = Image.merge("RGBA", (r, g, b, a))
    from io import BytesIO
    buf = BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def image_size(src: Path) -> Tuple[int, int]:
    img = Image.open(src)
    return img.size
