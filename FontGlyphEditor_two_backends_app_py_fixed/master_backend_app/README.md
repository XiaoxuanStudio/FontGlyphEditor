# FontGlyphEditor 总后端

职责：登录、注册、卡密、用户到期时间、线路配置，并可直接托管 Web 客户端。

## 本地启动

```bash
cd FontGlyphEditor_two_backends_app_py_fixed/master_backend_app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
export SUPER_ADMIN_QQ=super
export SUPER_ADMIN_PASSWORD=change-this-password
python -m uvicorn app:app --host 0.0.0.0 --port 9000
```

默认数据库：`fontglyph_admin.sqlite3`。

## 配置线路
编辑 `config/lines.json`：

```json
[
  {"id":"line1", "name":"线路一", "url":"https://font-line1.example.com", "enabled":true},
  {"id":"line2", "name":"线路二", "url":"https://font-line2.example.com", "enabled":true}
]
```

## 角色
- `super_admin`：可以改字体，也可以管理用户、生成卡密、导出卡密表。
- `admin`：普通付费用户，可以登录、注册、使用改字体功能。

## 重要
上线前必须修改：
- `SUPER_ADMIN_PASSWORD`
- HTTPS 域名
- 数据库备份策略
- 反向代理上传大小限制


## 本次修复

- 启动入口已改为 `app.py`，不再使用 `main.py`。
- `/auth/login` 同时兼容 `{"username":"...","password":"..."}` 和 `{"qq":"...","password":"..."}`。
- 当前数据库仍使用 `users.qq` 字段作为登录名存储字段，因此输入框里的“账号/QQ”都会去匹配这个字段。

## Web 端

在完整开源包目录结构下，Master 后端会自动托管 `FontGlyphEditor_web/`。启动后访问：

```text
http://127.0.0.1:9000/web/
```

如果你把 Web 端放在其他目录，请设置：

```bash
export FONTGLYPH_WEB_DIR=/path/to/FontGlyphEditor_web
```
