# FontGlyphEditor 部署教程

本文档使用示例域名说明部署流程：

- 总后端：`https://font-master.example.com`
- 线路一后端：`https://font-line1.example.com`
- 线路二后端：`https://font-line2.example.com`

部署时请全部替换成你自己的域名或服务器地址。

## 1. 环境准备

服务器建议：Linux / Ubuntu 22.04+，Python 3.10+。

安装基础依赖：

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx
```

## 2. 部署总后端 Master Backend

进入总后端目录：

```bash
cd FontGlyphEditor_backend/master_backend_app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

复制并修改环境变量示例：

```bash
cp .env.example .env
nano .env
```

至少修改：

```bash
SUPER_ADMIN_QQ=admin
SUPER_ADMIN_PASSWORD=change-this-password
```

`SUPER_ADMIN_PASSWORD` 必须改成强密码。第一次启动时，如果数据库里还没有超级管理员，程序会自动创建一个超级管理员账号。

启动测试：

```bash
export $(grep -v '^#' .env | xargs)
python -m uvicorn app:app --host 127.0.0.1 --port 9000
```

浏览器或命令行访问：

```bash
curl http://127.0.0.1:9000/health
```

返回 `{"ok": true}` 说明总后端已启动。

## 3. 配置线路后端地址

编辑总后端线路配置：

```bash
nano config/lines.json
```

示例：

```json
[
  {"id": "line1", "name": "线路一", "url": "https://font-line1.example.com", "enabled": true},
  {"id": "line2", "name": "线路二", "url": "https://font-line2.example.com", "enabled": true}
]
```

客户端登录总后端后，会通过 `/config/lines` 获取这些线路地址。

## 4. 部署线路后端 Line Backend

进入线路后端目录：

```bash
cd FontGlyphEditor_backend/line_backend_app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

复制并修改环境变量示例：

```bash
cp .env.example .env
nano .env
```

关键配置：

```bash
FONTGLYPH_REQUIRE_AUTH=true
FONTGLYPH_MASTER_VERIFY_URL=https://font-master.example.com/auth/verify
```

也可以直接编辑 `line_config.json`：

```json
{
  "line_id": "line1",
  "line_name": "线路一",
  "require_auth": true,
  "master_verify_url": "https://font-master.example.com/auth/verify"
}
```

启动测试：

```bash
export $(grep -v '^#' .env | xargs)
python -m uvicorn app:app --host 127.0.0.1 --port 8000
```

健康检查：

```bash
curl http://127.0.0.1:8000/health
```

## 5. Nginx 反向代理示例

总后端示例：

```nginx
server {
    listen 80;
    server_name font-master.example.com;

    client_max_body_size 200m;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

线路后端示例：

```nginx
server {
    listen 80;
    server_name font-line1.example.com;

    client_max_body_size 500m;
    proxy_read_timeout 7200s;
    proxy_send_timeout 7200s;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

配置 HTTPS 可使用 Certbot：

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d font-master.example.com
sudo certbot --nginx -d font-line1.example.com
```

## 6. systemd 后台运行示例

总后端服务示例：

```ini
[Unit]
Description=FontGlyphEditor Master Backend
After=network.target

[Service]
WorkingDirectory=/path/to/FontGlyphEditor_backend/master_backend_app
EnvironmentFile=/path/to/FontGlyphEditor_backend/master_backend_app/.env
ExecStart=/path/to/FontGlyphEditor_backend/master_backend_app/.venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 9000
Restart=always

[Install]
WantedBy=multi-user.target
```

线路后端服务只需要把 `WorkingDirectory`、`EnvironmentFile` 和端口改成线路后端对应路径与端口即可。


## 7. 部署 Web 端

本开源包已经补充 Web 客户端：

```text
FontGlyphEditor_web/
```

在默认完整目录结构下，Master 后端会自动托管 Web 端。启动 Master 后端后访问：

```text
http://127.0.0.1:9000/web/
```

如果使用域名和 HTTPS：

```text
https://font-master.example.com/web/
```

Web 端与 iOS 端共用同一套登录体系：

1. 使用 Master 后端的 `/auth/login` 登录。
2. 注册时使用 `/auth/register` 和卡密。
3. 登录后通过 `/config/lines` 获取线路。
4. 字体导出调用所选线路后端 `/export`。
5. 超级管理员可以在 Web 端添加用户、修改用户状态、生成卡密、查看卡密和导出 CSV。

如果你的目录结构变化，设置环境变量：

```bash
FONTGLYPH_WEB_DIR=/path/to/FontGlyphEditor_web
```

也可以把 `FontGlyphEditor_web/` 单独放到 Nginx、Caddy、GitHub Pages 或 Cloudflare Pages。单独部署时，在登录页的“总后端 Master 地址”填写：

```text
https://font-master.example.com
```

生产环境如果要收紧跨域来源，可以修改 Master 后端和 Line 后端的 CORS 配置。

## 8. 配置 iOS 客户端

打开：

```text
FontGlyphEditor_iOS/FontGlyphEditor/Services/AppConfig.swift
```

将：

```swift
static let masterBaseURL = URL(string: "https://font-master.example.com")!
```

改成你的总后端域名。

然后用 Xcode 打开：

```text
FontGlyphEditor_iOS/FontGlyphEditor.xcodeproj
```

建议同时修改：

- Bundle Identifier：从 `com.example.FontGlyphEditor` 改成你自己的包名。
- Team / Signing：选择你自己的 Apple Developer Team。
- App 名称：在 `Info.plist` 中修改 `CFBundleDisplayName`。

## 9. 登录与卡密流程

1. 启动总后端。
2. 使用 `SUPER_ADMIN_QQ` 和 `SUPER_ADMIN_PASSWORD` 登录客户端。
3. 在管理员页面生成卡密。
4. 普通用户使用账号、密码和卡密注册。
5. iOS 端或 Web 端从总后端获取线路列表，再调用线路后端处理字体。

## 10. 常见问题

### 修改了 `SUPER_ADMIN_PASSWORD` 但登录密码没变

超级管理员只会在数据库没有超级管理员时自动创建。数据库已经存在时，修改环境变量不会自动覆盖旧密码。

解决方式：

- 使用管理接口修改密码；或
- 测试环境删除数据库文件后重新启动；或
- 手动迁移/修改数据库。

### 真机访问本地服务失败

真机不能访问电脑里的 `127.0.0.1`。真机测试时需要把客户端地址改成电脑在同一局域网内的地址，或使用公网/内网穿透域名。

### 导出大字体失败

检查 Nginx 的 `client_max_body_size`、`proxy_read_timeout`，以及服务器内存、磁盘空间。
