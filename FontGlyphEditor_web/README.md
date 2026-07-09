# FontGlyphEditor Web 端

这是 FontGlyphEditor 的 Web 客户端，功能与 iOS 端对齐：

- 登录 / 注册 / 卡密注册
- 自动读取 Master 后端线路配置
- 选择线路并测试字体引擎
- 导入 TTF / OTF / TTC 字体
- 全局调整：大小、粗细、字距、基线、行距
- 颜色处理：不改色、统一色、完全随机、指定色随机
- 修符：上传 PNG / JPEG / WEBP / ZIP，填写替换字符，支持 ZIP 自动识别
- 调用线路后端导出字体并下载 TTF
- 超级管理员功能：添加用户、修改用户状态/角色/到期时间/密码、生成卡密、查看卡密、导出 CSV

## 推荐访问方式

启动 Master 后端后，直接访问：

```text
http://127.0.0.1:9000/web/
```

如果已经配置 HTTPS 域名：

```text
https://font-master.example.com/web/
```

Master 后端会尝试自动托管本目录。如果你的目录结构不同，可以设置环境变量：

```bash
FONTGLYPH_WEB_DIR=/path/to/FontGlyphEditor_web
```

## 静态文件单独部署

也可以把本目录上传到任意静态站点服务，例如 Nginx、Caddy、GitHub Pages、Cloudflare Pages。

单独部署时，登录页里的“总后端 Master 地址”填你的 Master 后端地址即可，例如：

```text
https://font-master.example.com
```

注意：Master 后端和 Line 后端已经默认开启 CORS，生产环境如需收紧来源，请自行修改后端 CORS 配置。
