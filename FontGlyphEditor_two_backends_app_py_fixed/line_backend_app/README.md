# FontGlyphEditor 线路后端

每一条线路部署一份这个 `font_engine`。例如：

- 线路一：`https://line1.example.com`
- 线路二：`https://line2.example.com`

## 本地启动

```bash
cd FontGlyphEditor_two_backends_app_py_fixed/line_backend_app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn app:app --host 0.0.0.0 --port 8000
```

## 连接总后端做登录校验
编辑 `line_config.json`：

```json
{
  "line_id": "line1",
  "line_name": "线路一",
  "require_auth": true,
  "master_verify_url": "https://master.example.com/auth/verify"
}
```

也可以用环境变量：

```bash
export FONTGLYPH_REQUIRE_AUTH=true
export FONTGLYPH_MASTER_VERIFY_URL=https://master.example.com/auth/verify
python -m uvicorn app:app --host 0.0.0.0 --port 8000
```

上线时建议所有线路都设置 `require_auth=true`。


## 本次调整

- 启动入口已改为 `app.py`，不再使用 `main.py`。
- 线路后端本身没有账号密码登录接口，它只负责字体处理，并通过 `Authorization: Bearer <token>` 调用总后端 `/auth/verify` 校验登录状态。
