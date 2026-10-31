# ShellRS App Store 最终版生成提示词

以下是根据最终交付版本整理的复用提示词。最终成品通过真实应用截图和原生字体排版合成，并非完全由图像模型生成。

## 所有素材共用

为 ShellRS 制作 App Store 宣传图。使用原始 App 图标以及对应语言、页面和设备方向的应用截图作为输入。应用图标取自项目 `ShellRS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`，不重新设计。截图需要重新拍摄；本目录不再保留图片或压缩包。

背景为完全均匀的暖白纯色 #F3F1EC，主标题和 ShellRS 品牌文字为深石墨色 #1E2B32，强调标题为墨绿色 #007E73，副标题为深灰色 #4D565C。背景不添加渐变、蓝光、光晕、纹理、地平线、阴影、代码图案或终端装饰。整体扁平、简洁，留白充足。

所有宣传文案使用真实字体在最终像素尺寸排字。中文标题使用 PingFangSC-Semibold、副标题使用 PingFangSC-Medium；英文及品牌文字使用 HelveticaNeue-Bold / HelveticaNeue-Medium。字形笔画内部必须使用统一纯色，仅边缘允许正常抗锯齿。不得使用模型重绘文字，不添加浮雕、高光、描边或立体效果。

设备正面平视，黑色细边框，无透视变形。不得虚构硬件型号或声称非官方绘制边框是 Apple 官方模板。应用截图保持原始纵横比，不拉伸、不重绘 UI，不虚构按钮或功能，不重复状态栏。可用虚构示例数据展示实际界面，但不得将预置终端输出和文件列表描述为真实服务器操作结果。系统深色模式下拍摄界面，SSH 终端保持实际的黑色背景。

每种语言单独出图，并使用对应语言的应用界面与日期格式。不得加入价格、评分、App Store 徽章、水印或额外宣传文字。导出为 sRGB、8-bit RGB PNG，无透明通道。检查尺寸、文字是否溢出、界面是否失真、强调标题颜色是否统一。

## iPhone 四页，中英文各一套

制作 1206 × 2622 px 竖版。左上放原始 App 图标和 ShellRS；下方两行大标题，第一行深石墨色，第二行墨绿色，再放一行副标题。画布下方放单台正面 iPhone，设备完整可见，统一边框、位置与比例。参考布局：图标左上坐标约 (110,120)，尺寸 142；品牌文字约 (284,151)；两行中文标题约 (104,314)、(104,520)，字号 202；副标题约 (110,735)，字号 49；设备约 (140,837)，尺寸 930 × 1720。英文根据文字长度调字号，保持相同留白。

| 页面 | 语言 | 第一行 | 第二行 | 副标题 |
| --- | --- | --- | --- | --- |
| 终端 | 简体中文 | 终端在手 | 随时掌控 | 随身 SSH 终端，连接你的服务器 |
| 主机 | 简体中文 | 所有主机 | 井然有序 | 分组管理，搜索直达，轻点连接 |
| 远程文件 | 简体中文 | 远程文件 | 轻松打理 | SFTP 浏览、上传与下载，一站完成 |
| 同步 | 简体中文 | 全平台可用 | 安全同步 | macOS · Windows · iOS · 安卓 |
| 终端 | English | Your terminal | Anywhere | Connect to your servers with SSH. |
| 主机 | English | Every host | Organized | Group, search, and connect in a tap. |
| 远程文件 | English | Remote files | Made simple | Browse, upload, and download with SFTP. |
| 同步 | English | Every platform | Secure sync | macOS · Windows · iOS · Android |

## iPad 四页，中英文各一套

制作 2752 × 2064 px 横版。展示实际 iPad 布局：终端页面含主机侧栏与多终端标签；主机页面展示分组和最近连接；远程文件页面同时展示主机、终端及 SFTP 三栏；同步页面展示工作台上的云同步设置面板。上方横向排品牌和宣传文字，下方大幅横向 iPad，保持 4:3 屏幕比例。

参考布局：图标约 (234,88)，尺寸 112；品牌约 (386,110)，字号 94；标题从 (1110,90) 开始，同一行并排，第一段深石墨色、第二段墨绿色，间距 44，中文最大字号 105、英文最大字号 96，按可用宽度缩小；副标题约 (1110,225)，字号 42。设备外框约 (234,300)，尺寸 2284 × 1724，圆角 94；截图区域约 (256,322)，尺寸 2240 × 1680，圆角 72。画面内容不拉伸。

| 页面 | 语言 | 第一段 | 强调段 | 副标题 |
| --- | --- | --- | --- | --- |
| 终端 | 简体中文 | 终端在手 | 随时掌控 | 多标签终端与硬件键盘，充分发挥大屏优势 |
| 主机 | 简体中文 | 所有主机 | 井然有序 | 分组管理，搜索直达，最近连接快速返回 |
| 远程文件 | 简体中文 | 远程文件 | 轻松打理 | 主机、终端与 SFTP 文件，同屏协作 |
| 同步 | 简体中文 | 全平台可用 | 安全同步 | macOS · Windows · Linux · iOS · 安卓 |
| 终端 | English | Your terminal | Anywhere | Terminal tabs and keyboard shortcuts, with room to work. |
| 主机 | English | Every host | Organized | Groups, search and recent connections, all in one place. |
| 远程文件 | English | Remote files | Made simple | Hosts, terminals and SFTP files, side by side. |
| 同步 | English | Every platform | Secure sync | macOS · Windows · Linux · iOS · Android |

## 创意素材，中英文各两张

产品页标题图使用 3840 × 1646 px，搜索结果图使用 3840 × 2560 px。左侧品牌与两行大标题，右侧单台正面 iPhone。标题图展示终端界面，搜索图展示主机管理界面。每种宽高比分别排版，关键内容保留安全边距。

标题图参考：品牌从 (610,260) 开始，图标尺寸 132；两行标题顶部约 575、850，最大字号 230；副标题顶部约 1215，字号 70；右侧设备约 (2300,70)，高度 1500。

搜索图参考：品牌从 (350,395) 开始，图标尺寸 184；两行标题顶部约 890、1245，最大字号 230；两行副标题顶部约 1685、1801，字号 66；右侧设备约 (2350,165)，高度 2220。英文按可用空间调整字号，保证完整可读。

| 用途 | 语言 | 第一行 | 第二行 | 副标题 |
| --- | --- | --- | --- | --- |
| 产品页标题 | 简体中文 | 终端在手 | 随时掌控 | SSH · 主机管理 · SFTP |
| 产品页标题 | English | Your terminal | Anywhere | SSH · Hosts · SFTP |
| 搜索结果 | 简体中文 | SSH · SFTP | 一手掌控 | 主机管理 · 远程文件 / 端到端加密同步 |
| 搜索结果 | English | SSH & SFTP | Within reach | Hosts, remote files and / end-to-end encrypted sync. |

表中的 `/` 表示副标题换行，不输出斜杠。实际上传前按 App Store Connect 当时的规格及预览裁剪结果再次核对。
