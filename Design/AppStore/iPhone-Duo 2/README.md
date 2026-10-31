# ShellRS — iPhone Duo App Store 截图

本套共 8 张成品：简体中文、English 各 4 页，顺序为终端、主机、远程文件、同步。应用采用浅色模式，终端保留应用实际使用的黑色背景。

## 交付文件

- `zh-Hans/`：4 张简体中文宣传图。
- `en/`：4 张英文宣传图。
- `overview.png`：中英文对照总览，仅供审阅，不作为单张上传。
- `raw/`：iPhone Duo 原生模拟器直接拍摄的 8 张应用界面。
- `source/`：原生字体排版代码和临时截图数据夹具。
- `manifest.json`：8 张成品的尺寸、色彩与 SHA-256 校验信息。

成品为 **2853 × 2007 px、sRGB、8-bit RGB PNG，无透明通道**。这是 iPhone Duo 内屏横向尺寸，依据 [Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)（2026-10-31 核对）。上传到对应语言的 iPhone Duo 内屏横向截图位置；本次不包含外屏尺寸。

## 设计

延续项目已有暖白设计：背景 `#F3F1EC`，主标题及品牌 `#1E2B32`，强调标题 `#007E73`，副标题 `#4D565C`。中文使用 PingFang SC，英文与 ShellRS 使用 Helvetica Neue。原始 App 图标直接取自项目资源；应用截图保持原始比例，仅等比缩放和圆角裁切。边框是简洁的正面示意，不是 Apple 官方硬件模板。

| 页码 | 中文 | English |
| --- | --- | --- |
| 01 | 终端在手 · 随时掌控 | Your terminal · Anywhere |
| 02 | 所有主机 · 井然有序 | Every host · Organized |
| 03 | 远程文件 · 轻松打理 | Remote files · Made simple |
| 04 | 全平台可用 · 安全同步 | Every platform · Secure sync |

## 数据来源

界面由当前 ShellRS 应用（提交 `e18750e`）在 iPhone Duo / iOS 27.1 模拟器渲染并直接拍摄，中文使用 `zh-Hans` / `CN`，英文使用 `en` / `US`，状态栏固定为 9:41。未重绘 UI、修改按钮或合成不存在的功能。

主机、域名、分组、文件及部署报告均为**虚构示例数据**。SSH/SFTP 连接只到本机隔离服务；`.example` 域名经测试 SOCKS 服务定向到回环地址，不访问实际生产服务器。终端健康状态和部署报告是预置展示内容，不代表真实生产环境的操作结果或性能测量。文件列表来自本机隔离的示例目录。同步页展示实际 WebDAV / S3 入口及端到端加密说明，未创建远端账户或声称已完成云同步。

## 重新排版

在仓库根目录运行（macOS，需要原生 PingFang SC 与 Helvetica Neue）：

```sh
xcrun swift Design/AppStore/iPhone-Duo/source/compose.swift
```

修改 `source/compose.swift` 中的文案、布局坐标与配色可重新导出同一组素材。排版使用 AppKit / Core Graphics，文字由真实字体直接栅格化，不使用图像模型重绘文字。

## 重新拍摄

1. 在临时虚拟环境安装 `source/requirements.txt`，运行 `source/server.py`，提供仅监听 `127.0.0.1:22222` 和 `127.0.0.1:22223` 的示例 SSH/SFTP 与 SOCKS 服务。
2. 临时将 `source/DuoScreenshotCaptureTests.swift` 复制到 `ShellRSTests/`；运行完毕后移除，不将截图夹具编入正式产品。
3. 在 iPhone Duo 模拟器打开内屏并置于横向，开启浅色模式。设置状态栏时间 9:41；拍摄命令使用 `simctl io ... screenshot --display=3 --mask=ignored`。
4. 中文测试运行参数：`TEST_RUNNER_SHELLRS_CAPTURE_DUO=1 TEST_RUNNER_SHELLRS_CAPTURE_LANGUAGE=zh-Hans`，以及 `xcodebuild ... -testLanguage zh-Hans -testRegion CN -only-testing:ShellRSTests/DuoScreenshotCaptureTests test`。英文将语言变量改为 `en`，测试参数改为 `-testLanguage en -testRegion US`。
5. 测试运行期间，在仓库根目录执行 `python3 Design/AppStore/iPhone-Duo/source/capture.py zh-Hans`（或 `en`）。脚本会等待夹具完成每页渲染，直接截图，再允许夹具切换下一页。重新安装 App 时会重新定位模拟器数据容器。
6. 完成后停止测试服务，移除临时测试文件，并执行重新排版命令。

模拟器 UDID 如有变化，需要同步更新 `source/capture.py` 中的 `device`。`source/server.py` 只用于本地截图夹具，不用于公开部署。
