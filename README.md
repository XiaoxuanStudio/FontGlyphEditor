# FontGlyphEditor 开源版

FontGlyphEditor 是一个字体编辑工具项目，包含：

- iOS 客户端：`FontGlyphEditor_login_fixed/`
- Web 客户端：`FontGlyphEditor_web/`
- 总后端 Master Backend：`FontGlyphEditor_two_backends_app_py_fixed/master_backend_app/`
- 字体处理线路后端 Line Backend：`FontGlyphEditor_two_backends_app_py_fixed/line_backend_app/`

## 开源前隐私处理

本开源包已经做过脱敏处理：

- 已将真实域名替换为 `font-master.example.com`、`font-line1.example.com`、`font-line2.example.com` 等示例域名。
- 已将局域网地址替换为示例配置。
- 已移除 SQLite 数据库、Python 缓存、macOS `.DS_Store`、Xcode 用户数据等不适合开源的文件。
- 已移除随包测试字体文件。部署后请由使用者自行上传/提供合法字体文件。

## 授权说明

本项目允许商用、允许二次开发、允许二次创作、允许再发布。

但任何基于本项目的二改、二创、Fork、改名发布、商用集成或再分发，必须标注原作者：小轩。

推荐标注：

> 本项目基于小轩开源项目二次开发。

详见 `LICENSE` 与 `NOTICE.md`。

## 快速部署

部署教程见 `DEPLOYMENT.md`。启动 Master 后端后，默认可以访问：

```text
http://127.0.0.1:9000/web/
```

Web 端和 iOS 端共用同一套登录、注册、卡密、线路与管理员接口。

## 安全提醒

正式上线前请务必修改：

- `SUPER_ADMIN_PASSWORD`
- `AppConfig.swift` 中的总后端域名
- Web 登录页中的总后端地址，或静态部署时的默认访问域名
- `master_backend_app/config/lines.json` 中的线路后端域名
- `line_backend_app/line_config.json` 或环境变量中的总后端校验地址
- Nginx / 反向代理上传大小限制
- 数据库备份策略
