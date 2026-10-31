# iPhone Duo 模拟器直出截图

2026-10-31 拍摄，简体中文与英文各 2 张：终端、SFTP 文件面板。
四张 PNG 均为 2853 × 2007 的内屏横向原始画面，直接使用 simctl screenshot 保存；未添加标题、背景或设备边框，未裁切、缩放、修图或转换色彩。

## 拍摄方式

使用已构建的 Duo 版本（提交 e18750e），正常启动 ShellRSApp；没有运行截图测试夹具，也没有向 TerminalSurface.feed 注入展示内容。为隔离正在开发中的版本，仅复制构建产物并将应用标识改为 com.shellrs.ios.directcapture 后重新签名，程序二进制未改动。主机通过 App 的正常新建、信任、密码认证流程连接。

App 连接本机 127.0.0.1:22224 的临时 SSH/SFTP 服务。远端实际为运行模拟器的 macOS，因而 uname 显示 Darwin / arm64。为避开自动化键盘与输入法问题，登录 shell 的 bashrc 实际执行 uname、date、stty size、ls、wc；屏幕上是这些命令的实时输出，并非预填报告。stty size 是登录脚本执行时的尺寸；之后开启文件面板会继续触发真实 PTY 调整，历史输出不会自动刷新。

SFTP 展示真实临时目录 /tmp/shellrs-direct-demo，README.md、notes.txt、config/app.json 是专门准备的示例文件，logs 是空目录。没有连接生产服务器，没有读取用户私有文件。

App 为系统浅色界面，终端保持产品当前实际的黑底。没有修改终端主题。状态栏保留拍摄时的系统时间。中文与英文的侧栏呈现状态不同，保留实际操作结果。

## 文件

- zh-Hans/01-terminal.png、zh-Hans/02-files.png
- en/01-terminal.png、en/02-files.png
- manifest.json：原始 PNG 的 SHA-256、尺寸和截屏命令
- source/local-ssh-server.py、source/bashrc：本机测试服务和实际命令；不含 SSH 主机私钥

截图命令：

```sh
xcrun simctl io 5D221A22-DAA0-4A07-859D-B67B8EED72CE screenshot --display=3 --mask=ignored output.png
```

source 文件是拍摄时服务的存档，用于解释结果来源。重新运行需安装 asyncssh 2.24.1，准备上述临时示例目录，将 bashrc 放至 /tmp/shellrs-direct-rc，并在 /tmp/shellrs-direct-hostkey 生成本机临时 ssh-ed25519 私钥。服务只绑定回环地址，不应用于公开部署。
