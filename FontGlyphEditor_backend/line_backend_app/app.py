from __future__ import annotations

import json
import shutil
import tempfile
import traceback
import os
import urllib.request
import urllib.error
from pathlib import Path
from urllib.parse import quote
from typing import List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import ValidationError

from font_edit import FontEditError, export_font
from schemas import ExportRequest
from utils import FONT_EXTENSIONS, IMAGE_EXTENSIONS, extract_zip_images, infer_character_from_filename, safe_filename

app = FastAPI(title="FontGlyphEditor Engine", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


LINE_CONFIG_PATH = Path(os.getenv("FONTGLYPH_LINE_CONFIG", Path(__file__).resolve().parent / "line_config.json"))


def _load_line_config() -> dict:
    if LINE_CONFIG_PATH.exists():
        try:
            return json.loads(LINE_CONFIG_PATH.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def _require_auth() -> bool:
    cfg = _load_line_config()
    env_value = os.getenv("FONTGLYPH_REQUIRE_AUTH")
    if env_value is not None:
        return env_value.lower() in ("1", "true", "yes", "on")
    return bool(cfg.get("require_auth", False))


def _master_verify_url() -> str:
    cfg = _load_line_config()
    return os.getenv("FONTGLYPH_MASTER_VERIFY_URL") or str(cfg.get("master_verify_url") or "")


def verify_bearer_token(authorization: Optional[str]) -> None:
    if not _require_auth():
        return
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization token")
    verify_url = _master_verify_url()
    if not verify_url:
        raise HTTPException(status_code=500, detail="Line backend auth is enabled, but master_verify_url is empty")
    req = urllib.request.Request(verify_url, headers={"Authorization": authorization}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status < 200 or resp.status >= 300:
                raise HTTPException(status_code=401, detail="Token verification failed")
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=exc.code, detail="Token verification failed")
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Master backend verify failed: {exc}")


@app.get("/health")
def health():
    return {"ok": True, "service": "FontGlyphEditor Engine", "line": _load_line_config()}


@app.post("/infer-images")
async def infer_images(files: List[UploadFile] = File(default=[]), authorization: Optional[str] = Header(default=None)):
    verify_bearer_token(authorization)
    inferred = []
    with tempfile.TemporaryDirectory(prefix="fge_infer_") as td:
        base = Path(td)
        for f in files:
            filename = safe_filename(f.filename or "image")
            path = base / filename
            path.write_bytes(await f.read())
            suffix = path.suffix.lower()
            if suffix == ".zip":
                extracted = extract_zip_images(path, base / "zip")
                for name in extracted.keys():
                    inferred.append({"filename": name, "character": infer_character_from_filename(name)})
            elif suffix in IMAGE_EXTENSIONS:
                inferred.append({"filename": filename, "character": infer_character_from_filename(filename)})
    return {"items": inferred}


@app.post("/export")
async def export_endpoint(
    font: UploadFile = File(...),
    request_json: str = Form(...),
    images: List[UploadFile] = File(default=[]),
    authorization: Optional[str] = Header(default=None),
):
    verify_bearer_token(authorization)
    try:
        request = ExportRequest.model_validate_json(request_json)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=json.loads(exc.json()))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid request_json: {exc}")

    with tempfile.TemporaryDirectory(prefix="fge_export_") as td:
        work = Path(td)
        font_name = safe_filename(font.filename or "font.ttf")
        if Path(font_name).suffix.lower() not in FONT_EXTENSIONS:
            raise HTTPException(status_code=400, detail="Please upload .ttf, .otf, or .ttc font file.")
        font_path = work / font_name
        font_path.write_bytes(await font.read())

        image_dir = work / "images"
        image_dir.mkdir(exist_ok=True)
        image_paths = {}
        for item in images:
            filename = safe_filename(item.filename or "image.png")
            path = image_dir / filename
            path.write_bytes(await item.read())
            suffix = path.suffix.lower()
            if suffix == ".zip":
                extracted = extract_zip_images(path, image_dir)
                image_paths.update(extracted)
            elif suffix in IMAGE_EXTENSIONS:
                image_paths[filename] = path

        raw_output_name = safe_filename(request.output_family_name or "FontGlyphEditor_Export")
        output_name = Path(raw_output_name).stem or "FontGlyphEditor_Export"
        output_path = work / f"{output_name}.ttf"
        try:
            result = export_font(font_path, output_path, request, image_paths)
        except FontEditError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:
            tb = traceback.format_exc()
            return JSONResponse(status_code=500, content={"detail": str(exc), "traceback": tb})

        final_path = output_path
        data = final_path.read_bytes()
        # HTTP headers must be Latin-1 encodable in Starlette.
        # Chinese font names such as "字体修符.ttf" will crash if placed directly
        # in Content-Disposition filename=. Use an ASCII fallback plus RFC 5987
        # filename*=UTF-8'' percent-encoded filename. Keep warnings ASCII too.
        download_name = final_path.name
        quoted_download_name = quote(download_name.encode("utf-8"))
        headers = {
            "X-FontGlyphEditor-Warnings": json.dumps(result.get("warnings", []), ensure_ascii=True),
            "Content-Disposition": f"attachment; filename=FontGlyphEditor_Export.ttf; filename*=UTF-8''{quoted_download_name}",
        }
        return Response(content=data, media_type="font/ttf", headers=headers)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=int(os.getenv("PORT", "8000")), reload=False)
