from __future__ import annotations

import base64
import copy
import json
import random
import time
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
from io import BytesIO

from PIL import Image, ImageDraw, ImageFont

from fontTools.misc.transform import Transform
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont, newTable
from fontTools.ttLib.tables.S_V_G_ import SVGDocument
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike as SbixStrike

from schemas import ColorMode, ExportRequest, TargetScope
from utils import image_size, normalize_hex_color, prepare_image


class FontEditError(RuntimeError):
    pass


class FontEditor:
    def __init__(self, font_path: Path):
        self.font_path = Path(font_path)
        self.font = self._load_font(self.font_path)
        self.warnings: List[str] = []
        self._pil_font_cache = {}
        self.glyph_order = self.font.getGlyphOrder()
        self.cmap = self._safe_best_cmap()
        if not self.cmap:
            raise FontEditError("无法读取这个字体的字符映射表 cmap。请确认导入的是有效的 TTF/OTF/TTC 字体；如果是特殊封装字体，请先用 FontForge/字体册另存为标准 TTF 后再导入。")
        self.upm = int(self.font["head"].unitsPerEm) if "head" in self.font else 1000
        self.ascent = int(getattr(self.font.get("hhea"), "ascent", int(self.upm * 0.8)))
        self.descent = int(getattr(self.font.get("hhea"), "descent", -int(self.upm * 0.2)))

    @staticmethod
    def _load_font(path: Path) -> TTFont:
        suffix = path.suffix.lower()
        if suffix == ".ttc":
            collection = TTCollection(str(path))
            if not collection.fonts:
                raise FontEditError("TTC collection is empty")
            return collection.fonts[0]
        return TTFont(str(path), recalcBBoxes=True, recalcTimestamp=False)

    def _safe_best_cmap(self) -> Dict[int, str]:
        """Return a Unicode cmap even when fontTools loads cmap as DefaultTable.

        A few third-party or repacked Chinese fonts make TTFont.getBestCmap()
        fail with "DefaultTable object has no attribute getBestCmap".  The iOS
        app still needs a codepoint -> glyphName map for glyph replacement, so
        we fall back to reading and parsing the raw cmap table bytes.
        """
        # Normal path for standard fonts.
        try:
            cmap = self.font.getBestCmap()
            if cmap:
                return dict(cmap)
        except Exception as exc:
            self.warnings.append(f"fontTools getBestCmap failed, using raw cmap parser: {exc}")

        # If fontTools did decompile cmap, read subtables manually.
        try:
            cmap_table = self.font["cmap"]
            tables = getattr(cmap_table, "tables", None)
            if tables:
                merged: Dict[int, str] = {}
                preferred = sorted(
                    tables,
                    key=lambda t: (
                        0 if getattr(t, "isUnicode", lambda: False)() else 1,
                        0 if getattr(t, "format", 0) in (12, 4) else 1,
                    ),
                )
                for sub in preferred:
                    try:
                        submap = getattr(sub, "cmap", None)
                        if submap:
                            merged.update(submap)
                    except Exception:
                        pass
                if merged:
                    return merged
        except Exception:
            pass

        raw = self._raw_cmap_data()
        if raw:
            parsed = self._parse_raw_cmap(raw)
            if parsed:
                self.warnings.append("字体 cmap 表由兼容解析器读取。")
                return parsed
        return {}

    def _raw_cmap_data(self) -> Optional[bytes]:
        # DefaultTable keeps raw bytes in .data after a failed decompile in many cases.
        try:
            table = self.font["cmap"]
            data = getattr(table, "data", None)
            if data:
                return bytes(data)
        except Exception:
            pass
        # Fall back to reading from SFNT table directory.
        try:
            reader = getattr(self.font, "reader", None)
            if not reader or "cmap" not in reader.tables:
                return None
            entry = reader.tables["cmap"]
            file_obj = reader.file
            here = file_obj.tell()
            try:
                file_obj.seek(entry.offset)
                return file_obj.read(entry.length)
            finally:
                try:
                    file_obj.seek(here)
                except Exception:
                    pass
        except Exception as exc:
            self.warnings.append(f"Could not read raw cmap table: {exc}")
            return None

    def _parse_raw_cmap(self, data: bytes) -> Dict[int, str]:
        import struct

        glyph_order = self.glyph_order

        def gid_to_name(gid: int) -> Optional[str]:
            if 0 <= gid < len(glyph_order):
                return glyph_order[gid]
            return None

        def u16(pos: int) -> int:
            return struct.unpack_from(">H", data, pos)[0]

        def i16(pos: int) -> int:
            return struct.unpack_from(">h", data, pos)[0]

        def u32(pos: int) -> int:
            return struct.unpack_from(">I", data, pos)[0]

        result: Dict[int, str] = {}
        try:
            if len(data) < 4:
                return {}
            num_tables = u16(2)
            records = []
            for i in range(num_tables):
                rec = 4 + i * 8
                if rec + 8 > len(data):
                    break
                platform_id = u16(rec)
                encoding_id = u16(rec + 2)
                offset = u32(rec + 4)
                if offset < len(data):
                    fmt = u16(offset)
                    # Prefer Unicode subtables, especially format 12 then 4.
                    is_unicode = platform_id in (0, 3) and encoding_id in (0, 1, 3, 4, 10)
                    priority = 0 if is_unicode and fmt == 12 else 1 if is_unicode and fmt == 4 else 2 if is_unicode else 3
                    records.append((priority, fmt, offset))
            for _, fmt, off in sorted(records):
                submap: Dict[int, str] = {}
                if fmt == 0 and off + 262 <= len(data):
                    for cp in range(256):
                        gid = data[off + 6 + cp]
                        name = gid_to_name(gid)
                        if gid and name:
                            submap[cp] = name
                elif fmt == 4 and off + 16 <= len(data):
                    length = u16(off + 2)
                    end = min(len(data), off + length)
                    seg_count = u16(off + 6) // 2
                    end_codes = off + 14
                    start_codes = end_codes + 2 * seg_count + 2
                    id_deltas = start_codes + 2 * seg_count
                    id_range_offsets = id_deltas + 2 * seg_count
                    if id_range_offsets + 2 * seg_count <= end:
                        for i in range(seg_count):
                            end_code = u16(end_codes + 2 * i)
                            start_code = u16(start_codes + 2 * i)
                            delta = i16(id_deltas + 2 * i)
                            range_offset = u16(id_range_offsets + 2 * i)
                            if start_code == 0xFFFF and end_code == 0xFFFF:
                                continue
                            # Avoid pathological fonts that declare a huge Unicode range.
                            if end_code < start_code or end_code - start_code > 8192:
                                continue
                            for cp in range(start_code, end_code + 1):
                                if range_offset == 0:
                                    gid = (cp + delta) & 0xFFFF
                                else:
                                    glyph_index_pos = id_range_offsets + 2 * i + range_offset + 2 * (cp - start_code)
                                    if glyph_index_pos + 2 > end:
                                        continue
                                    gid = u16(glyph_index_pos)
                                    if gid:
                                        gid = (gid + delta) & 0xFFFF
                                name = gid_to_name(gid)
                                if gid and name:
                                    submap[cp] = name
                elif fmt == 6 and off + 10 <= len(data):
                    length = u16(off + 2)
                    end = min(len(data), off + length)
                    first = u16(off + 6)
                    count = u16(off + 8)
                    arr = off + 10
                    for idx in range(count):
                        pos = arr + idx * 2
                        if pos + 2 > end:
                            break
                        gid = u16(pos)
                        name = gid_to_name(gid)
                        if gid and name:
                            submap[first + idx] = name
                elif fmt in (12, 13) and off + 16 <= len(data):
                    length = u32(off + 4)
                    end = min(len(data), off + length)
                    n_groups = u32(off + 12)
                    pos = off + 16
                    for _ in range(n_groups):
                        if pos + 12 > end:
                            break
                        start_cp = u32(pos)
                        end_cp = u32(pos + 4)
                        start_gid = u32(pos + 8)
                        pos += 12
                        if end_cp < start_cp or end_cp - start_cp > 8192:
                            continue
                        for cp in range(start_cp, end_cp + 1):
                            gid = start_gid if fmt == 13 else start_gid + (cp - start_cp)
                            name = gid_to_name(gid)
                            if gid and name:
                                submap[cp] = name
                if submap:
                    result.update(submap)
                    # A Unicode format 12/4 subtable is usually enough; keep merging
                    # other Unicode subtables but do not let symbol maps override basics.
            return result
        except Exception as exc:
            self.warnings.append(f"Raw cmap parser failed: {exc}")
            return {}


    def save(self, output_path: Path) -> Dict[str, object]:
        self._sanitize_name_table_for_save()
        self.font.save(str(output_path), reorderTables=False)
        return {
            "output": str(output_path),
            "warnings": self.warnings,
            "glyph_count": len(self.glyph_order),
        }

    def _sanitize_name_table_for_save(self) -> None:
        """Remove or rewrite name records that cannot be encoded by fontTools.

        Some Chinese fonts contain Macintosh/unknown name records whose Python
        encoding is reported as ``charmap`` or ``ascii`` while the actual string
        contains Chinese characters. fontTools can load these fonts, but it may
        fail during ``font.save()`` with errors such as::

            NameRecord sorting failed to encode: 'charmap' codec can't encode ...

        The exported font only needs a clean name table, so we keep a minimal set
        of Windows Unicode records and drop legacy Macintosh records. This makes
        saving deterministic and also avoids iOS treating the output as the same
        font as the original one.
        """
        if "name" not in self.font:
            return
        name_table = self.font["name"]
        safe_names = []
        dropped = 0
        for rec in list(getattr(name_table, "names", [])):
            try:
                # Only keep Windows Unicode name records. Platform 1 Macintosh
                # records are the common source of charmap/MacRoman failures.
                if getattr(rec, "platformID", None) != 3:
                    dropped += 1
                    continue
                if getattr(rec, "platEncID", None) not in (1, 10):
                    dropped += 1
                    continue
                rec.toBytes()
                safe_names.append(rec)
            except Exception:
                dropped += 1
        name_table.names = safe_names
        if dropped:
            self.warnings.append(f"Cleaned {dropped} incompatible legacy name records before saving.")

    def glyph_name_for_char(self, ch: str) -> Optional[str]:
        if not ch:
            return None
        cp = ord(ch[0])
        return self.cmap.get(cp)

    def glyph_id_for_name(self, name: str) -> int:
        try:
            return self.glyph_order.index(name)
        except ValueError:
            return 0

    def target_glyphs(self, scope: TargetScope, selected_chars: str) -> List[str]:
        if scope == TargetScope.all:
            names = []
            for cp, name in self.cmap.items():
                if name in self.glyph_order and name != ".notdef":
                    names.append(name)
            return sorted(set(names), key=lambda n: self.glyph_order.index(n))
        names = []
        for ch in selected_chars:
            name = self.glyph_name_for_char(ch)
            if name:
                names.append(name)
            else:
                self.warnings.append(f"Character {ch!r} has no cmap mapping and was skipped.")
        return sorted(set(names), key=lambda n: self.glyph_order.index(n))

    def update_names(self, family_name: str) -> None:
        family_name = (family_name or "FontGlyphEditor Export").strip()[:64]
        now = time.strftime("%Y%m%d%H%M%S")
        subfamily = "Regular"
        full_name = f"{family_name} {subfamily}"
        # PostScript names must be ASCII-ish. Do not use str.isalnum(), because
        # it treats Chinese characters as alphanumeric.
        ascii_family = "".join(c if ("A" <= c <= "Z" or "a" <= c <= "z" or "0" <= c <= "9") else "-" for c in family_name)
        ascii_family = "-".join(part for part in ascii_family.split("-") if part) or "FontGlyphEditor"
        ps_name = f"{ascii_family}-{subfamily}-{now}"[:63]

        name_map = {
            1: family_name,
            2: subfamily,
            3: f"{family_name};{subfamily};{now}",
            4: full_name,
            5: f"Version 1.000; FontGlyphEditor export {now}",
            6: ps_name,
        }
        name_table = self.font["name"]

        # Drop old name records first. Many third-party Chinese fonts include
        # legacy Macintosh records that cannot be re-encoded by fontTools.
        name_table.names = []

        # Add only Windows Unicode records. These are accepted by iOS and avoid
        # MacRoman/charmap save failures. Use English and Simplified Chinese
        # language IDs so Chinese family names still show correctly.
        for name_id, value in name_map.items():
            for platform_id, plat_enc_id, lang_id in [(3, 1, 0x409), (3, 1, 0x804), (3, 10, 0x409)]:
                try:
                    name_table.setName(value, name_id, platform_id, plat_enc_id, lang_id)
                except Exception as exc:
                    self.warnings.append(f"Could not set nameID {name_id}: {exc}")

    def apply_global_adjustment(self, req: ExportRequest) -> None:
        adj = req.adjustment
        glyphs = self.target_glyphs(adj.scope, adj.selected_chars)
        if adj.scale != 1.0 or adj.baseline_shift != 0:
            self._transform_tt_glyphs(glyphs, adj.scale, adj.baseline_shift)
        if adj.tracking != 0 or adj.scale != 1.0:
            self._adjust_advance_widths(glyphs, scale=adj.scale, tracking=adj.tracking)
        if adj.line_height != 1.0:
            self._adjust_line_height(adj.line_height)
        if adj.weight != 0:
            # True outline emboldening requires a specialized offset-curve algorithm.
            # The app uses this value for patch alpha dilation and future outline expansion.
            self.warnings.append("Outline weight for original glyphs is recorded but not destructively expanded in this build.")

    def _transform_tt_glyphs(self, names: List[str], scale: float, baseline_shift: int) -> None:
        if "glyf" not in self.font:
            self.warnings.append("This font has no glyf table; global outline transform was skipped.")
            return
        glyf = self.font["glyf"]
        glyph_set = self.font.getGlyphSet()
        matrix = Transform(scale, 0, 0, scale, 0, baseline_shift)
        changed = 0
        for name in names:
            try:
                original = glyph_set[name]
                pen = TTGlyphPen(glyph_set)
                transform_pen = TransformPen(pen, matrix)
                original.draw(transform_pen)
                glyf[name] = pen.glyph()
                changed += 1
            except Exception as exc:
                self.warnings.append(f"Could not transform glyph {name}: {exc}")
        if changed:
            try:
                glyf.recalcBounds(self.font)
            except Exception:
                pass

    def _adjust_advance_widths(self, names: List[str], scale: float = 1.0, tracking: int = 0) -> None:
        if "hmtx" not in self.font:
            return
        hmtx = self.font["hmtx"].metrics
        for name in names:
            if name not in hmtx:
                continue
            aw, lsb = hmtx[name]
            hmtx[name] = (max(1, int(round(aw * scale + tracking))), lsb)

    def _adjust_line_height(self, multiplier: float) -> None:
        multiplier = max(0.5, min(3.0, multiplier))
        extra = int(round(self.upm * (multiplier - 1.0)))
        if "hhea" in self.font:
            hhea = self.font["hhea"]
            hhea.lineGap = max(0, int(getattr(hhea, "lineGap", 0)) + extra)
        if "OS/2" in self.font:
            os2 = self.font["OS/2"]
            if hasattr(os2, "sTypoLineGap"):
                os2.sTypoLineGap = max(0, int(os2.sTypoLineGap) + extra)
            if hasattr(os2, "usWinAscent"):
                os2.usWinAscent = int(round(os2.usWinAscent * multiplier))
            if hasattr(os2, "usWinDescent"):
                os2.usWinDescent = int(round(os2.usWinDescent * multiplier))

    def apply_color_settings(self, req: ExportRequest) -> None:
        """Apply color to original outline glyphs.

        Earlier builds only added SVG-in-OpenType color documents. Many iOS
        text renderers ignore the SVG table for normal text and fall back to the
        original black glyf/CFF outline, so exported fonts still looked black.
        This build also writes an Apple-friendly sbix bitmap strike for each
        colored character. sbix is a bitmap color-glyph table supported by Apple
        platforms, so the exported font is much more likely to show the chosen
        colors after installation or when registered with CoreText.
        """
        color = req.color
        if color.mode == ColorMode.none:
            return

        targets = self._target_color_codepoints(color.scope, color.selected_chars, req.preview_text)
        if not targets:
            return

        rnd = random.Random(color.random_seed)
        palette = [normalize_hex_color(c) for c in color.palette_hex if normalize_hex_color(c)]
        if not palette:
            palette = ["#E8836B", "#F2B705", "#3DA5D9", "#73B66B", "#8D6AD3", "#2B2B2B"]

        docs = self._existing_svg_docs()
        sbix_table = self.font.get("sbix") or newTable("sbix")
        if not hasattr(sbix_table, "strikes"):
            sbix_table.strikes = {}
        sbix_table.version = 1
        sbix_table.flags = 1
        ppem = 160
        strike = sbix_table.strikes.get(ppem) or SbixStrike(ppem=ppem, resolution=72)

        rendered = 0
        for idx, (cp, name) in enumerate(targets):
            if color.mode == ColorMode.solid:
                fill = normalize_hex_color(color.solid_hex)
            elif color.mode == ColorMode.random:
                fill = "#%06X" % rnd.randint(0, 0xFFFFFF)
            else:
                fill = rnd.choice(palette)

            gid = self.glyph_id_for_name(name)

            # Keep SVG documents for apps that support SVG-in-OpenType.
            doc = self._glyph_outline_svg(name, fill)
            if doc:
                docs.append(SVGDocument(doc, gid, gid, False))

            # Add sbix bitmap color glyph for Apple renderers.
            try:
                png_bytes, off_x, off_y = self._render_colored_char_png(chr(cp), fill, ppem=ppem)
                if png_bytes:
                    strike.glyphs[name] = SbixGlyph(
                        glyphName=name,
                        gid=gid,
                        originOffsetX=int(off_x),
                        originOffsetY=int(off_y),
                        graphicType="png ",
                        imageData=png_bytes,
                    )
                    rendered += 1
                    if rendered % 250 == 0:
                        print(f"[FontGlyphEditor] colored sbix glyphs: {rendered}/{len(targets)}", flush=True)
            except Exception as exc:
                self.warnings.append(f"Could not rasterize colored glyph U+{cp:04X}: {exc}")

        if rendered:
            sbix_table.strikes[ppem] = strike
            self.font["sbix"] = sbix_table
            self.warnings.append(f"Wrote {rendered} colored sbix glyphs at {ppem} ppem.")
        self._set_svg_docs(docs)

    def _target_color_codepoints(self, scope: TargetScope, selected_chars: str, preview_text: str = "") -> List[Tuple[int, str]]:
        """Return unique (unicode codepoint, glyphName) pairs for color output.

        Important product rule: when the UI says "全部字符", it must really
        mean every Unicode character that exists in the font's cmap, not just
        preview text. This can be slow for Chinese fonts because generating an
        Apple sbix color bitmap for thousands of glyphs is real work, but it is
        the correct behavior for the all scope.
        """
        pairs: List[Tuple[int, str]] = []
        seen = set()
        source: List[Tuple[int, str]] = []
        if scope == TargetScope.all:
            for cp, name in sorted(self.cmap.items(), key=lambda item: item[0]):
                source.append((int(cp), name))
            self.warnings.append(
                f"Color scope all selected {len(source)} cmap characters. Export can be slow and the font file can become large."
            )
        else:
            for ch in selected_chars:
                if not ch:
                    continue
                cp = ord(ch[0])
                name = self.cmap.get(cp)
                if name:
                    source.append((cp, name))
                else:
                    self.warnings.append(f"Character {ch!r} has no cmap mapping and was skipped for color.")
        for cp, name in source:
            if name == ".notdef" or name not in self.glyph_order:
                continue
            if name in seen:
                continue
            seen.add(name)
            pairs.append((cp, name))
        return pairs

    def _render_colored_char_png(self, ch: str, fill: str, ppem: int = 160) -> Tuple[bytes, int, int]:
        """Rasterize one character in the source font to a transparent PNG.

        The PNG is used as an sbix color glyph.  The returned offsets are
        baseline-relative lower-left offsets in pixels, matching sbix's origin
        model closely enough for iOS/CoreText preview and installation use.
        """
        font = self._pil_font(ppem)
        color = self._rgba_from_hex(fill)
        pad = max(4, ppem // 20)
        # left-baseline anchor gives bbox coordinates relative to the glyph
        # origin. y values are positive downward in Pillow's coordinate system.
        try:
            bbox = font.getbbox(ch, anchor="ls")
        except TypeError:
            bbox = font.getbbox(ch)
        if not bbox:
            raise FontEditError(f"Pillow could not compute bbox for {ch!r}")
        x0, y0, x1, y1 = [int(round(v)) for v in bbox]
        width = max(1, x1 - x0 + pad * 2)
        height = max(1, y1 - y0 + pad * 2)
        img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        try:
            draw.text((pad - x0, pad - y0), ch, font=font, fill=color, anchor="ls")
        except TypeError:
            draw.text((pad - x0, pad - y0), ch, font=font, fill=color)
        buf = BytesIO()
        img.save(buf, format="PNG")
        # Lower-left bitmap origin relative to glyph origin.
        origin_x = x0 - pad
        origin_y = -y1 - pad
        return buf.getvalue(), origin_x, origin_y

    def _pil_font(self, ppem: int):
        key = int(ppem)
        if key not in self._pil_font_cache:
            try:
                self._pil_font_cache[key] = ImageFont.truetype(str(self.font_path), key)
            except Exception as exc:
                raise FontEditError(f"Pillow cannot open this font for color rasterization: {exc}")
        return self._pil_font_cache[key]

    @staticmethod
    def _rgba_from_hex(value: str) -> Tuple[int, int, int, int]:
        value = normalize_hex_color(value, "#000000").lstrip("#")
        return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)

    def _glyph_outline_svg(self, glyph_name: str, fill: str) -> Optional[str]:
        try:
            glyph_set = self.font.getGlyphSet()
            glyph = glyph_set[glyph_name]
            pen = SVGPathPen(glyph_set)
            glyph.draw(pen)
            path_data = pen.getCommands()
            if not path_data:
                return None
            adv = int(glyph.width) if hasattr(glyph, "width") else self.upm
            view_y = self.descent
            view_h = self.ascent - self.descent
            return (
                f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {view_y} {adv} {view_h}">'
                f'<path d="{path_data}" fill="{fill}"/>'
                '</svg>'
            )
        except Exception as exc:
            self.warnings.append(f"Could not generate color SVG for {glyph_name}: {exc}")
            return None

    def apply_glyph_patches(self, req: ExportRequest, image_paths: Dict[str, Path]) -> None:
        if not req.patches:
            return
        svg_docs = self._existing_svg_docs()
        sbix_table = self.font.get("sbix") or newTable("sbix")
        if not hasattr(sbix_table, "strikes"):
            sbix_table.strikes = {}
        sbix_table.version = 1
        sbix_table.flags = 1
        touched_strikes = set()

        for patch in req.patches:
            ch = patch.character[0]
            gname = self.glyph_name_for_char(ch)
            if not gname:
                self.warnings.append(f"Patch character {ch!r} does not exist in cmap and was skipped.")
                continue
            img_path = image_paths.get(patch.image_filename)
            if not img_path or not img_path.exists():
                self.warnings.append(f"Image {patch.image_filename!r} was not uploaded and was skipped.")
                continue
            gid = self.glyph_id_for_name(gname)

            # The size slider must affect the actual embedded bitmap, not just
            # the glyph advance.  sbix is bitmap-based; if we keep embedding the
            # original PNG unchanged, iOS will draw it at the same visual size no
            # matter how patch.scale changes.
            ppem = int(getattr(patch, "png_ppem", 160) or 160)
            ppem = min(1024, max(16, ppem))
            bitmap_height = min(4096, max(8, int(round(ppem * float(patch.scale)))))
            png_bytes = prepare_image(img_path, weight=patch.weight, target_height=bitmap_height)

            aw = self._glyph_advance(gname)
            aw = max(1, int(round(aw * patch.scale + patch.tracking)))
            self._set_advance(gname, aw)

            strike = sbix_table.strikes.get(ppem) or SbixStrike(ppem=ppem, resolution=72)

            # sbix: good fallback path for Apple platforms.
            strike.glyphs[gname] = SbixGlyph(
                glyphName=gname,
                gid=gid,
                originOffsetX=int(patch.offset_x),
                originOffsetY=int(patch.offset_y),
                graphicType="png ",
                imageData=png_bytes,
            )
            sbix_table.strikes[ppem] = strike
            touched_strikes.add(ppem)

            # SVG-in-OpenType: useful for browsers/design tools and preserves vector-table semantics.
            svg_docs.append(SVGDocument(self._image_svg(img_path, png_bytes, aw, patch), gid, gid, False))

        if touched_strikes:
            self.font["sbix"] = sbix_table
            self.warnings.append(
                "Patched sbix bitmap glyph sizes for strikes: " + ", ".join(map(str, sorted(touched_strikes)))
            )
        self._set_svg_docs(svg_docs)

    def _glyph_advance(self, gname: str) -> int:
        if "hmtx" in self.font and gname in self.font["hmtx"].metrics:
            return int(self.font["hmtx"].metrics[gname][0])
        return self.upm

    def _set_advance(self, gname: str, aw: int) -> None:
        if "hmtx" in self.font and gname in self.font["hmtx"].metrics:
            _, lsb = self.font["hmtx"].metrics[gname]
            self.font["hmtx"].metrics[gname] = (aw, lsb)

    def _image_svg(self, img_path: Path, png_bytes: bytes, advance_width: int, patch) -> str:
        w_px, h_px = image_size(img_path)
        h_units = int(round(self.upm * patch.scale))
        w_units = max(1, int(round(h_units * (w_px / max(1, h_px)))))
        x = int(round((advance_width - w_units) / 2 + patch.offset_x))
        # Place image around baseline: SVG image y goes downward; viewBox uses font y coordinates.
        y = int(round(self.descent + (self.ascent - self.descent - h_units) / 2 - patch.offset_y))
        data = base64.b64encode(png_bytes).decode("ascii")
        view_y = self.descent
        view_h = self.ascent - self.descent
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {view_y} {advance_width} {view_h}">'
            f'<image x="{x}" y="{y}" width="{w_units}" height="{h_units}" '
            f'href="data:image/png;base64,{data}"/>'
            '</svg>'
        )

    def _existing_svg_docs(self) -> List[SVGDocument]:
        if "SVG " not in self.font:
            return []
        try:
            docs = []
            for d in getattr(self.font["SVG "], "docList", []):
                if isinstance(d, SVGDocument):
                    docs.append(copy.deepcopy(d))
                elif isinstance(d, (list, tuple)):
                    docs.append(SVGDocument(*d))
            return docs
        except Exception:
            return []

    def _set_svg_docs(self, docs: List[SVGDocument]) -> None:
        if not docs:
            return
        table = newTable("SVG ")
        # If repeated glyphs appear, later docs are preferred by most readers only if table order is stable.
        # Keep docs sorted by gid for deterministic output.
        table.docList = sorted(docs, key=lambda d: (d.startGlyphID, d.endGlyphID))
        table.compressed = False
        self.font["SVG "] = table


def export_font(font_path: Path, output_path: Path, request: ExportRequest, image_paths: Dict[str, Path]) -> Dict[str, object]:
    editor = FontEditor(font_path)
    editor.update_names(request.output_family_name)
    editor.apply_global_adjustment(request)
    editor.apply_color_settings(request)
    editor.apply_glyph_patches(request, image_paths)
    return editor.save(output_path)
