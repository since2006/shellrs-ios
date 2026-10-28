# ShellRS for iOS

ShellRS 的 iPhone / iPad 版：SSH 主机管理、终端、SFTP 文件和云同步。连接、主机库、同步都在 Rust 核心里（[shell-rs](https://github.com/since2006/shell-rs) 的 `crates/shellrs-mobile`，经 UniFFI 生成 Swift 接口），和电脑上的 ShellRS 共用同一套逻辑和数据格式；终端模拟用 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)。

最低 iOS 17，Bundle ID `com.shellrs.ios`（钥匙串跟它绑定，发布后不能改）。

## 构建

要有 Xcode（16 以上）和 shell-rs 那边的 Rust 工具链，外加：

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

1. 把 shell-rs 检出在本仓库旁边（`../shell-rs`），或用 `SHELLRS_DIR` 指过去。
2. 编核心：`scripts/build-core.sh`。它跑 shell-rs 的 `scripts/build-ios.sh`，把 `ShellRSCore.xcframework` 和生成的 `ShellRSCore.swift` 拷进 `Packages/ShellRSCore`（这两样不进库）。检出的提交和 `Packages/ShellRSCore/core-revision` 不同、或 crates 有没提交的改动时会提醒。最后跑 `scripts/licenses.py` 重写「开源许可」的清单 `ShellRS/About/Licenses.json`（进库；SwiftTerm 的许可证从它的检出里读，还没构建过 App 时沿用清单里版本相同的那条）。
3. 打开 `ShellRS.xcodeproj`。第一次构建 Xcode 会问是否信任 SwiftTerm 的构建插件 `SwiftTermBuildInfoPlugin`（只生成版本信息），选「Trust & Enable」。
4. 真机运行要签名：新建 `Config/Local.xcconfig`（不进库），写一行 `DEVELOPMENT_TEAM = 你的 Team ID`。

模拟器只编了 Apple 芯片的（`aarch64-apple-ios-sim`）。

命令行：

```sh
xcodebuild -project ShellRS.xcodeproj -scheme ShellRS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -skipPackagePluginValidation test
```

模拟器换成本机装了的（`xcrun simctl list devices available`）；不写 `OS=` 时 xcodebuild 找最新 SDK 的运行时，没装就报找不到设备。

## 测试

`ShellRSTests` 用 Swift Testing，宿主是 App 本身：

- 钥匙串（`AppKeychain`）在模拟器的钥匙串里用测试自己的 service 存取删；
- 主机库、凭据和终端会话用真的 `Core`，数据在临时文件夹、钥匙串在内存（`MemoryKeychain`）：密码、代理密码、口令只进钥匙串，数据文件夹里找不到；分组、排序、复制、删除时说的连带；
- 主机树（`HostTree`）是纯函数，照电脑版的规则建树、搜索；
- 传输队列（`TransferQueue`）照电脑版的规则：一次一批、停止的批次占着队头、移出和清除；SFTP 的失败链在「无法上传：…」这种自己说原因的一节停下（同电脑版）；没连上时文件页说原因，要传的在队列里等下一次会话；
- 连一个没人监听的本机端口，看断开的原因是「连接被拒绝」那一句；关掉的终端检查连接时直接说不在；
- 同步（`SyncModel`）用两个 `Core` 经临时文件夹同步（核心的文件夹存储，测试里不上网）：创建、加入、密码不对；一边改了停一会儿自己同步出去，另一边回到前台时拿到；别处改了同步密码时等用户输入，期间改动和回到前台都不同步；被别的设备移出后重新加入；关闭后数据留着、不再同步；
- 开源许可的清单（`Licenses.json`）里有 SwiftTerm、russh、tokio、UniFFI 和 Simple Icons，没有 shell-rs 自己的 crate，每一项都有许可证和全文；
- 窗口（`AppModel`）：宽窗口关掉当前标签选右边的、没有就选左边的，窄窗口回到列表；标签菜单关左侧 / 右侧 / 其他 / 全部；⌘1–9 和上一个 / 下一个；快捷键在两种布局下各去哪，终端盖着或设置开着时不动；终端字号夹在范围里、打开的终端跟着变、存了读得回来（测试用自己的 `UserDefaults`）；文件只在宽窗口有终端时开在旁边；拖进来的文件拷一份、作为一批上传，批次结束副本删掉。

`ServerTests` 连真的 SSH 服务器，只在给了服务器时跑：信任主机密钥、密码问答、命令输出出现在 SwiftTerm 的屏幕上、检查连接（量出延迟，断开后说不在）、断开后 Enter 重连；密钥凭据登录（服务器要信任 `ShellRSTests/Support.swift` 里的测试密钥 `testKey`）；给了目标机时经 SSH 跳板连它，再给了 SOCKS5 代理时经代理连它；在终端的连接上开 SFTP：浏览、新建文件夹、上传、下载、同名时问、预览、重命名、删除，传到一半停止再继续，传到一半终端断开、重连后自己接着传，传回来逐字节相同。用 Docker 起一台跳板和一台只在 Docker 网络里的目标机，再经跳板开一个 SOCKS5 代理（密码 `shellrs-test`）：

```sh
docker network create shellrs-test
SETUP='apk add --no-cache openssh >/dev/null && ssh-keygen -A >/dev/null &&
  echo root:shellrs-test | chpasswd &&
  sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/; s/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/" /etc/ssh/sshd_config &&
  mkdir -p /root/.ssh &&
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFt1RMfeVGPOwxKiOBQ5XPK+s20chu7Z2S1c7Pj3B8F1 shellrs-test" > /root/.ssh/authorized_keys &&
  exec /usr/sbin/sshd -D -e'
docker run -d --rm --name shellrs-ios-sshd --network shellrs-test -p 127.0.0.1:2222:22 alpine:3 sh -c "$SETUP"
docker run -d --rm --name shellrs-ios-target --network shellrs-test --network-alias target alpine:3 sh -c "$SETUP"
ssh -f -N -D 127.0.0.1:1080 -p 2222 root@127.0.0.1

TEST_RUNNER_SHELLRS_TEST_SSH=127.0.0.1:2222 \
TEST_RUNNER_SHELLRS_TEST_SSH_PASSWORD=shellrs-test \
TEST_RUNNER_SHELLRS_TEST_SSH_TARGET=target:22 \
TEST_RUNNER_SHELLRS_TEST_SOCKS=127.0.0.1:1080 \
xcodebuild … test
```

（`xcodebuild` 把 `TEST_RUNNER_` 开头的变量去掉前缀交给测试；用户名用 `SHELLRS_TEST_SSH_USER`，默认 root；目标机和代理不给就跳过那两个测试。代理在跳板上解析 `target`。）

## iPad

窗口够宽（iPad 上 `horizontalSizeClass == .regular`）时照电脑版的主窗口：左边侧栏是主机树（底部切到凭据，旁边是设置齿轮，可收起），右边是终端标签条和当前终端，没有标签时是开始页（最近连接）；「文件」开在右边（`.inspector`，挂在整个分栏外面，挂在详情里它的工具栏会和终端的并在一起），跟着当前标签走，开在那个终端的连接上。分屏一半、侧拉、台前调度里拖窄时换成 iPhone 的标签页，打开的终端都还在；iPhone 一直是标签页，大屏 iPhone 横屏也不换。两种布局共用 `AppModel` 的状态，只换外壳（`WideRoot` / `CompactRoot`）。

- **只开一个窗口**（`Config/Info.plist` 写明，不自动生成场景清单）：一个终端只有一个 SwiftTerm 视图，两个窗口会抢。
- **确认框**：宽窗口里用居中的 alert，窄窗口用底部的动作表（`View.confirmation`）；`confirmationDialog` 在 iPad 上是弹出框，挂在整个列表上就指着列表正中，和要删的那一行对不上。
- **拖文件进来上传**：从别的 App 拖到文件列表上，落下时先拷一份（来源 App 随后就收回），同一次拖进来的是一批。
- **文件列表只在「选择」时给选择绑定**：iPad 上的 `List(selection:)` 不进编辑模式也能选，点文件夹就成了选中这一行，进不去（iPhone 要进编辑模式才选，所以没这个问题）。
- **硬件键盘**：切标签、打开终端后，接着键盘才把焦点给终端，直接就能打字；没接不抢，免得弹出软键盘。
- **终端字号**在设置里，10–28、默认 13（同电脑版），存在本机、不同步。

快捷键的名字和按键照电脑版，按住 ⌘ 看得到；SwiftTerm 不处理带 ⌘ 的键，终端里也能用，⌘C、⌘V 是系统「编辑」菜单的，到终端自己的拷贝、粘贴：

| 快捷键 | 动作 |
|---|---|
| ⌘N / ⌘⇧N | 新建主机 / 新建分组 |
| ⌘K | 聚焦搜索 |
| ⌘, | 打开设置 |
| ⌘B | 显示或隐藏侧栏（宽窗口） |
| ⌘⌥B | 显示或隐藏右侧栏，即文件（宽窗口，有终端时） |
| ⌘W | 关闭标签 |
| ⌘} / ⌘{ | 下一个 / 上一个标签 |
| ⌘1…⌘8 | 切换到标签 1…8；开了 9 个以上时 ⌘9 是最后一个 |
| ⌘= / ⌘- / ⌘0 | 放大字号 / 缩小字号 / 默认字号 |

新建、搜索、设置在窄窗口的终端盖着时、宽窗口的设置开着时不响应，免得在看不见的地方弹窗。电脑版的 ⌘T 是新建本地终端，iOS 没有本地终端，不占这个键。

## 目录

- `ShellRS/App`：入口、`AppModel`（核心、主机、同步、打开的终端、窗口的状态和快捷键做的事）、`AppKeychain`、`RootView`（按窗口宽窄选布局；前后台切换时告诉同步，回到前台时检查终端的连接）、宽窗口的分栏（`WideRoot`、`Sidebar`）、快捷键（`AppCommands`）、确认框（`Confirmation`）、设置页（云同步、终端字号、关于）、表单里带标签的输入框。
- `ShellRS/Hosts`：`HostsModel`（主机、分组、凭据的快照和改动）、主机树（`HostTree`：分组在前、主机在后，搜索同电脑版）、主机列表、主机表单（认证、跳板、代理、分组）、分组表单、主机标记（`HostMark`：探测到系统后是它的图标和品牌色）。
- `ShellRS/Credentials`：凭据列表和表单（密码；私钥粘贴、从文件读、生成）。
- `ShellRS/Terminal`：`TerminalSession`（连接、问答、终端的事件）、`TerminalSurface`（SwiftTerm 的视图和委托，**只有这个文件 import SwiftTerm**：它的 `Terminal`、`TerminalOptions` 和核心的重名）、窄窗口的终端页（`TerminalScreen`）、宽窗口的标签条和终端（`TerminalWorkspace`、`TerminalTabs`）、开始页、问答、打开的终端列表。
- `ShellRS/Files`：`FilesModel`（终端连接上的 SFTP 会话、传输队列、断开后接着传）、`TransferQueue`（照电脑版的队列）、目录浏览（拖进来上传）、传输队列页、已下载的文件。
- `ShellRS/Sync`：`SyncModel`（什么时候同步、等用户处理的事、建立和加入等操作）、云同步页、WebDAV / S3 的登录表单、同步密码（创建、加入、更换）。
- `ShellRS/Describe`：核心的错误和失败翻成文案（SFTP 的在 `DescribeSftp.swift`，同步的在 `DescribeSync.swift`），删除前说的连带。
- `ShellRS/About`：「开源许可」页和它的清单 `Licenses.json`（`scripts/licenses.py` 生成，不手改）。
- `ShellRS/Assets.xcassets/AppIcon.appiconset`：App 图标。`Design/AppIcon.svg` 由电脑版的定稿 `assets/logo/shellrs.svg` 改来：底板放大铺满画布、去掉圆角（iOS 自己切圆角），图案相对底板的大小和位置不变。改了 SVG 就重新出图：`qlmanage -t -s 1024 -o /tmp Design/AppIcon.svg`，再 `magick /tmp/AppIcon.svg.png -alpha off -define png:color-type=2 ShellRS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`（App Store 不收带透明通道的图标）。
- `ShellRS/Assets.xcassets/OS`：系统图标，和电脑版是同一套 [Simple Icons](https://simpleicons.org)（CC0），按核心的 `HostOs.key` 命名。
- `ShellRS/Localizable.xcstrings`：全部文案。
- `Packages/ShellRSCore`：核心的 Swift 包（xcframework + 生成的接口）。
- `scripts`：`build-core.sh`（编核心）、`licenses.py`（开源许可的清单）、`license-texts`（crate 没带许可证文件时用的标准全文）。

## 约定

- **核心不产出文案。** 失败是一串类型化的环节（`Failure.links`），`Describe` 逐节翻译、用「: 」连起来，措辞照电脑版的 `locales/*.yml`；`switch` 写全，核心加了变体这里就编不过，要补上文案。
- **文案**：中文是源语言，代码里直接写中文（`Text("主机")`、`String(localized:)`），英文在 `Localizable.xcstrings`；用词照 shell-rs 的 `CLAUDE.md` 用词表。插值先转成 `String`（`%@`）；数量用 `Int`（`%lld`），英文在 String Catalog 里分单复数。三目运算挑两个字面量交给 `Text`、`Button`、`navigationTitle` 时走的是 `String` 的重载、不翻译，每个分支要写成 `String(localized:)`。
- **秘密只进钥匙串**：密码、口令经核心写进 `AppKeychain`（`AfterFirstUnlockThisDeviceOnly`，不随备份去别的设备，靠 ShellRS 自己的同步走），数据库里没有秘密。
- **事件只拉不推**：每个核心对象一个 `Task` 循环 `nextEvent()` 到 `nil`，在主 actor 上更新模型。
- 核心的 `Group` 和 SwiftUI 的 `Group` 重名，视图里用别名 `HostGroup`。
- **标签各自记着打开时的主机**（同电脑版）：编辑、删除主机不碰已打开的终端；重新连接时按保存的主机再连。
- 断开的终端按 Enter 重连、按 Space 关闭（同电脑版），也有按钮。
- **回到前台时检查每个终端的连接**（`checkAlive`）：在后台时被系统关掉的，马上显示断开条；5 秒没回应的不主动断开（可能只是慢，断了会结束服务器上正在跑的程序），只是不显示延迟，等核心的心跳放弃（约一分半）再显示断开条。
- **SFTP 开在终端自己的连接上**（同电脑版右侧栏的「文件」，堡垒机上不用再登录一次）：终端断开它就断，终端重连后它自己开回来，传到一半的批次接着传，不再问是否续传（已经说过「继续」）。手机上的连接断了不会回来，所以不等引擎重试，终端一断就放下会话。
- **传输一次一批**，排队在 App 里（同电脑版）。下载放 `Documents/Downloads`（「文件」App 的「我的 iPhone › ShellRS」里看得到），点文件是下到缓存里用快速查看预览；上传先把选的文件拷进临时目录（选的文件到时可能已经拿不到；拖进来的在落下时拷），批次结束就删，启动时清掉上次留下的。
- **什么时候同步**（照核心 README，同电脑版）：启动和回到前台（一分钟内只一次）、改了要同步的东西后停 5 秒（`status().hasChanges` 为真才排）、进后台前有改动就借系统给的后台时间同步一轮；不定时轮询。出错只写在云同步页；要用户处理的（别处改了同步密码、被重置、被移出、一次删很多、登录被拒）弹一次提示、设置标签上有标记，处理完之前不自动同步。位置只有 WebDAV 和 S3，WebDAV 密码、S3 Secret Key 和同步密钥只进钥匙串（账户名同电脑版）。
- **开源许可**：清单只列 iOS 上真链接进 App 的（shellrs-mobile 的普通依赖，不含过程宏和 shell-rs 自己的 crate，加上 SwiftTerm 和 Simple Icons）；可以选许可证的（`MIT OR Apache-2.0`）列选用的那个，MIT 优先；同时适用几个的全列。升级依赖后重跑 `scripts/build-core.sh`，`Licenses.json` 跟着改动一起提交。
- 核心接口缺东西就改 shell-rs 的 `crates/shellrs-mobile`（单独提交、照那边的规矩测），再更新 `core-revision`、重跑 `scripts/build-core.sh`。
