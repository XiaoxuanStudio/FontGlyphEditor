from __future__ import annotations

import csv
import hashlib
import hmac
import io
import json
import os
import secrets
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional, List

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.getenv("FONTGLYPH_MASTER_DB", BASE_DIR / "fontglyph_admin.sqlite3"))
LINES_CONFIG = Path(os.getenv("FONTGLYPH_LINES_CONFIG", BASE_DIR / "config" / "lines.json"))
TOKEN_DAYS = int(os.getenv("FONTGLYPH_TOKEN_DAYS", "30"))
WEB_DIR = Path(os.getenv("FONTGLYPH_WEB_DIR", BASE_DIR.parent.parent / "FontGlyphEditor_web"))


@asynccontextmanager
async def lifespan(app):
    # 程序启动执行
    init_db()
    yield
    # 程序关闭执行（无逻辑留空）


app = FastAPI(title="FontGlyphEditor Master Backend", version="2.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if WEB_DIR.exists():
    app.mount("/web", StaticFiles(directory=str(WEB_DIR), html=True), name="web")


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.astimezone(timezone.utc).isoformat() if dt else None


def parse_iso(text: Optional[str]) -> Optional[datetime]:
    if not text:
        return None
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def hash_password(password: str, salt: Optional[str] = None) -> tuple[str, str]:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 200_000)
    return salt, digest.hex()


def verify_password(password: str, salt: str, password_hash: str) -> bool:
    _, digest = hash_password(password, salt)
    return hmac.compare_digest(digest, password_hash)


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                qq TEXT NOT NULL UNIQUE,
                password_salt TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL CHECK(role IN ('super_admin','admin')),
                expires_at TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            );
            CREATE TABLE IF NOT EXISTS card_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                card_key TEXT NOT NULL UNIQUE,
                duration_days INTEGER NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                is_used INTEGER NOT NULL DEFAULT 0,
                used_by_user_id INTEGER,
                used_at TEXT,
                created_by_user_id INTEGER,
                created_at TEXT NOT NULL,
                FOREIGN KEY(used_by_user_id) REFERENCES users(id),
                FOREIGN KEY(created_by_user_id) REFERENCES users(id)
            );
            """
        )
        super_qq = os.getenv("SUPER_ADMIN_QQ", "admin")
        super_password = os.getenv("SUPER_ADMIN_PASSWORD", "change-this-password")
        existing = conn.execute("SELECT id FROM users WHERE role='super_admin' LIMIT 1").fetchone()
        if not existing:
            salt, pwd = hash_password(super_password)
            conn.execute(
                "INSERT INTO users (qq,password_salt,password_hash,role,expires_at,is_active,created_at) VALUES (?,?,?,?,?,?,?)",
                (super_qq, salt, pwd, "super_admin", None, 1, iso(now_utc())),
            )


class UserOut(BaseModel):
    id: int
    qq: str
    role: str
    expires_at: Optional[str] = None
    is_active: bool
    created_at: str


class AuthOut(BaseModel):
    token: str
    user: UserOut


class LoginIn(BaseModel):
    # 兼容两种前端入参：
    # 1) {"username":"账号或QQ", "password":"..."}
    # 2) {"qq":"账号或QQ", "password":"..."}
    # 数据库当前仍使用 users.qq 字段存储登录名。
    username: Optional[str] = None
    qq: Optional[str] = None
    password: str

    def login_name(self) -> str:
        value = (self.username or self.qq or "").strip()
        if not value:
            raise HTTPException(status_code=422, detail="请输入账号或QQ")
        return value


class RegisterIn(BaseModel):
    qq: str
    password: str = Field(min_length=6)
    password_confirm: str
    card_key: str


class CreateUserIn(BaseModel):
    qq: str
    password: str = Field(min_length=6)
    role: str = "admin"
    expires_at: Optional[str] = None
    is_active: bool = True


class UpdateUserIn(BaseModel):
    password: Optional[str] = None
    expires_at: Optional[str] = None
    is_active: Optional[bool] = None
    role: Optional[str] = None


class GenerateCardsIn(BaseModel):
    count: int = Field(default=1, ge=1, le=500)
    duration_days: int = Field(default=30, ge=1, le=3650)
    note: str = ""


class CardOut(BaseModel):
    id: int
    card_key: str
    duration_days: int
    note: str
    is_used: bool
    used_by_user_id: Optional[int]
    used_at: Optional[str]
    created_at: str


class LineOut(BaseModel):
    id: str
    name: str
    url: str
    enabled: bool = True


def row_to_card(row: sqlite3.Row) -> CardOut:
    data = dict(row)
    data["is_used"] = bool(data.get("is_used"))
    return CardOut(**data)


def row_to_user(row: sqlite3.Row) -> UserOut:
    return UserOut(
        id=row["id"], qq=row["qq"], role=row["role"], expires_at=row["expires_at"],
        is_active=bool(row["is_active"]), created_at=row["created_at"]
    )


def make_session(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    expires = now_utc() + timedelta(days=TOKEN_DAYS)
    conn.execute(
        "INSERT INTO sessions (token,user_id,expires_at,created_at) VALUES (?,?,?,?)",
        (token, user_id, iso(expires), iso(now_utc())),
    )
    return token


def get_current_user(authorization: Optional[str] = Header(default=None)) -> sqlite3.Row:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing token")
    token = authorization.split(" ", 1)[1].strip()
    with db() as conn:
        row = conn.execute(
            """
            SELECT u.* FROM sessions s JOIN users u ON s.user_id=u.id
            WHERE s.token=? AND s.expires_at>?
            """,
            (token, iso(now_utc())),
        ).fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Invalid token")
    if not bool(row["is_active"]):
        raise HTTPException(status_code=403, detail="User disabled")
    exp = parse_iso(row["expires_at"])
    if row["role"] != "super_admin" and exp and exp < now_utc():
        raise HTTPException(status_code=403, detail="User expired")
    return row


def require_super(user: sqlite3.Row = Depends(get_current_user)) -> sqlite3.Row:
    if user["role"] != "super_admin":
        raise HTTPException(status_code=403, detail="Super admin only")
    return user


@app.get("/")
def root():
    if WEB_DIR.exists():
        return RedirectResponse(url="/web/")
    return {"ok": True, "service": "FontGlyphEditor Master", "web": "Set FONTGLYPH_WEB_DIR to enable /web"}


@app.get("/health")
def health():
    return {"ok": True, "service": "FontGlyphEditor Master", "web_enabled": WEB_DIR.exists()}


@app.post("/auth/login", response_model=AuthOut)
def login(payload: LoginIn):
    with db() as conn:
        row = conn.execute("SELECT * FROM users WHERE qq=?", (payload.login_name(),)).fetchone()
        if not row or not verify_password(payload.password, row["password_salt"], row["password_hash"]):
            raise HTTPException(status_code=401, detail="账号或密码错误")
        if not bool(row["is_active"]):
            raise HTTPException(status_code=403, detail="账号已停用")
        exp = parse_iso(row["expires_at"])
        if row["role"] != "super_admin" and exp and exp < now_utc():
            raise HTTPException(status_code=403, detail="账号已到期")
        token = make_session(conn, row["id"])
        return AuthOut(token=token, user=row_to_user(row))


@app.post("/auth/register", response_model=AuthOut)
def register(payload: RegisterIn):
    if payload.password != payload.password_confirm:
        raise HTTPException(status_code=400, detail="两次密码不一致")
    qq = payload.qq.strip()
    with db() as conn:
        card = conn.execute("SELECT * FROM card_keys WHERE card_key=?", (payload.card_key.strip(),)).fetchone()
        if not card or bool(card["is_used"]):
            raise HTTPException(status_code=400, detail="卡密无效或已使用")
        if conn.execute("SELECT id FROM users WHERE qq=?", (qq,)).fetchone():
            raise HTTPException(status_code=400, detail="账号已存在")
        salt, pwd = hash_password(payload.password)
        exp = now_utc() + timedelta(days=int(card["duration_days"]))
        cur = conn.execute(
            "INSERT INTO users (qq,password_salt,password_hash,role,expires_at,is_active,created_at) VALUES (?,?,?,?,?,?,?)",
            (qq, salt, pwd, "admin", iso(exp), 1, iso(now_utc())),
        )
        user_id = cur.lastrowid
        conn.execute(
            "UPDATE card_keys SET is_used=1, used_by_user_id=?, used_at=? WHERE id=?",
            (user_id, iso(now_utc()), card["id"]),
        )
        row = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        token = make_session(conn, user_id)
        return AuthOut(token=token, user=row_to_user(row))


@app.get("/auth/me", response_model=UserOut)
def me(user: sqlite3.Row = Depends(get_current_user)):
    return row_to_user(user)


@app.get("/auth/verify")
def verify(user: sqlite3.Row = Depends(get_current_user)):
    return {"ok": True, "user": row_to_user(user).model_dump()}


@app.get("/config/lines", response_model=List[LineOut])
def lines(_: sqlite3.Row = Depends(get_current_user)):
    if not LINES_CONFIG.exists():
        return []
    raw = json.loads(LINES_CONFIG.read_text(encoding="utf-8"))
    return [LineOut(**item) for item in raw if item.get("enabled", True)]


@app.get("/admin/users", response_model=List[UserOut])
def admin_users(_: sqlite3.Row = Depends(require_super)):
    with db() as conn:
        rows = conn.execute("SELECT * FROM users ORDER BY id DESC").fetchall()
        return [row_to_user(r) for r in rows]


@app.post("/admin/users", response_model=UserOut)
def admin_create_user(payload: CreateUserIn, super_user: sqlite3.Row = Depends(require_super)):
    if payload.role not in ("admin", "super_admin"):
        raise HTTPException(status_code=400, detail="Invalid role")
    salt, pwd = hash_password(payload.password)
    with db() as conn:
        try:
            cur = conn.execute(
                "INSERT INTO users (qq,password_salt,password_hash,role,expires_at,is_active,created_at) VALUES (?,?,?,?,?,?,?)",
                (payload.qq.strip(), salt, pwd, payload.role, payload.expires_at, int(payload.is_active), iso(now_utc())),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=400, detail="账号已存在")
        row = conn.execute("SELECT * FROM users WHERE id=?", (cur.lastrowid,)).fetchone()
        return row_to_user(row)


@app.patch("/admin/users/{user_id}", response_model=UserOut)
def admin_update_user(user_id: int, payload: UpdateUserIn, _: sqlite3.Row = Depends(require_super)):
    fields = []
    values = []
    if payload.password:
        salt, pwd = hash_password(payload.password)
        fields.extend(["password_salt=?", "password_hash=?"])
        values.extend([salt, pwd])
    if payload.expires_at is not None:
        fields.append("expires_at=?")
        values.append(payload.expires_at)
    if payload.is_active is not None:
        fields.append("is_active=?")
        values.append(int(payload.is_active))
    if payload.role is not None:
        if payload.role not in ("admin", "super_admin"):
            raise HTTPException(status_code=400, detail="Invalid role")
        fields.append("role=?")
        values.append(payload.role)
    if not fields:
        raise HTTPException(status_code=400, detail="没有可更新内容")
    values.append(user_id)
    with db() as conn:
        conn.execute(f"UPDATE users SET {', '.join(fields)} WHERE id=?", values)
        row = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="用户不存在")
        return row_to_user(row)


@app.post("/admin/cards/generate", response_model=List[CardOut])
def generate_cards(payload: GenerateCardsIn, super_user: sqlite3.Row = Depends(require_super)):
    cards = []
    with db() as conn:
        for _ in range(payload.count):
            key = "FGE-" + secrets.token_urlsafe(18).replace("-", "").replace("_", "")[:24].upper()
            cur = conn.execute(
                "INSERT INTO card_keys (card_key,duration_days,note,is_used,created_by_user_id,created_at) VALUES (?,?,?,?,?,?)",
                (key, payload.duration_days, payload.note, 0, super_user["id"], iso(now_utc())),
            )
            row = conn.execute("SELECT * FROM card_keys WHERE id=?", (cur.lastrowid,)).fetchone()
            cards.append(row_to_card(row))
    return cards


@app.get("/admin/cards", response_model=List[CardOut])
def list_cards(_: sqlite3.Row = Depends(require_super)):
    with db() as conn:
        rows = conn.execute("SELECT * FROM card_keys ORDER BY id DESC LIMIT 1000").fetchall()
        return [row_to_card(r) for r in rows]


@app.get("/admin/cards/export.csv")
def export_cards(_: sqlite3.Row = Depends(require_super)):
    with db() as conn:
        rows = conn.execute("SELECT * FROM card_keys ORDER BY id DESC").fetchall()
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["card_key", "duration_days", "note", "is_used", "used_by_user_id", "used_at", "created_at"])
    for r in rows:
        writer.writerow([r["card_key"], r["duration_days"], r["note"], r["is_used"], r["used_by_user_id"], r["used_at"], r["created_at"]])
    return Response(content=out.getvalue().encode("utf-8-sig"), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=cards.csv"})

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "9000"))
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=False)
