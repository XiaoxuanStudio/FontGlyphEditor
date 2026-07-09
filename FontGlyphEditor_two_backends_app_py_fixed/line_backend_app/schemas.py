from __future__ import annotations

from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field


class TargetScope(str, Enum):
    all = "all"
    selected = "selected"


class ColorMode(str, Enum):
    none = "none"
    solid = "solid"
    random = "random"
    palette_random = "palette_random"


class GlobalAdjustment(BaseModel):
    scope: TargetScope = TargetScope.all
    selected_chars: str = ""
    scale: float = Field(default=1.0, ge=0.2, le=3.0)
    weight: float = Field(default=0.0, ge=-20.0, le=20.0)
    tracking: int = Field(default=0, ge=-1000, le=3000)
    baseline_shift: int = Field(default=0, ge=-3000, le=3000)
    line_height: float = Field(default=1.0, ge=0.5, le=3.0)


class ColorSettings(BaseModel):
    scope: TargetScope = TargetScope.all
    selected_chars: str = ""
    mode: ColorMode = ColorMode.none
    solid_hex: str = "#000000"
    palette_hex: List[str] = Field(default_factory=list)
    random_seed: int = 42


class GlyphPatch(BaseModel):
    character: str = Field(min_length=1, max_length=8)
    image_filename: str
    scale: float = Field(default=1.0, ge=0.1, le=5.0)
    tracking: int = Field(default=0, ge=-1000, le=3000)
    offset_x: int = Field(default=0, ge=-5000, le=5000)
    offset_y: int = Field(default=0, ge=-5000, le=5000)
    weight: float = Field(default=0.0, ge=-20.0, le=20.0)
    png_ppem: int = Field(default=160, ge=16, le=1024)


class ExportRequest(BaseModel):
    output_family_name: str = "FontGlyphEditor Export"
    preview_text: str = "信の雨70字体预览\n1234567890\nABCDEFGHIJK"
    adjustment: GlobalAdjustment = Field(default_factory=GlobalAdjustment)
    color: ColorSettings = Field(default_factory=ColorSettings)
    patches: List[GlyphPatch] = Field(default_factory=list)
