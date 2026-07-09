# FontGlyphEditor 开源版

FontGlyphEditor 是一个字体字形编辑工具的开源实现，包含：

- iOS 客户端：`FontGlyphEditor_iOS/`
- Web 客户端：`FontGlyphEditor_web/`
- 总后端 Master Backend：`FontGlyphEditor_backend/master_backend_app/`
- 字体处理线路后端 Line Backend：`FontGlyphEditor_backend/line_backend_app/`

## 项目说明

本仓库为整理后的开源版本，代码已移除个人域名、局域网 IP、数据库、缓存、测试素材、Xcode 用户数据、macOS 临时文件等不适合公开的内容。

本仓库不包含第三方商业字体文件、私有配置、真实域名、真实 IP 或数据库内容。部署后请由使用者自行上传或提供合法字体文件。

若相关权利人认为项目中存在不当使用、过度相似或其他权益问题，欢迎联系原作者沟通处理。

## 功能概览

- 登录、注册、卡密注册
- 线路获取与线路选择
- 字体导入、预览、参数调整与导出
- 字符局部调整
- 颜色处理
- 图片修符
- Web 管理端：用户管理、卡密生成、卡密查看、CSV 导出

## 授权说明

本项目允许学习、修改、二次开发、二次创作、商用集成和再发布。

任何基于本项目的二改、二创、Fork、改名发布、商用集成或再分发，必须保留原作者署名：**小轩**。

推荐标注：

> 本项目基于小轩原创的 FontGlyphEditor 项目二次开发。

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
