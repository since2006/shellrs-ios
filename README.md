# ShellRS for iOS

ShellRS 的 iPhone / iPad 版：SSH 主机管理、终端和 SFTP 文件。连接、主机库、同步都在 Rust 核心里（[shell-rs](https://github.com/since2006/shell-rs) 的 `crates/shellrs-mobile`，经 UniFFI 生成 Swift 接口），和电脑上的 ShellRS 共用同一套逻辑和数据格式；终端模拟用 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)。

最低 iOS 17，Bundle ID `com.shellrs.ios`（钥匙串跟它绑定，发布后不能改）。

## 构建

要有 Xcode（16 以上）和 shell-rs 那边的 Rust 工具链，外加：

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

1. 把 shell-rs 检出在本仓库旁边（`../shell-rs`），或用 `SHELLRS_DIR` 指过去。
2. 编核心：`scripts/build-core.sh`。它跑 shell-rs 的 `scripts/build-ios.sh`，把 `ShellRSCore.xcframework` 和生成的 `ShellRSCore.swift` 拷进 `Packages/ShellRSCore`（这两样不进库）。检出的提交和 `Packages/ShellRSCore/core-revision` 不同、或 crates 有没提交的改动时会提醒。
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
- 连一个没人监听的本机端口，看断开的原因是「连接被拒绝」那一句。

`ServerTests` 连真的 SSH 服务器，只在给了服务器时跑：信任主机密钥、密码问答、命令输出出现在 SwiftTerm 的屏幕上、断开后 Enter 重连；密钥凭据登录（服务器要信任 `ShellRSTests/Support.swift` 里的测试密钥 `testKey`）；给了目标机时经 SSH 跳板连它，再给了 SOCKS5 代理时经代理连它；在终端的连接上开 SFTP：浏览、新建文件夹、上传、下载、同名时问、预览、重命名、删除，传到一半停止再继续，传到一半终端断开、重连后自己接着传，传回来逐字节相同。用 Docker 起一台跳板和一台只在 Docker 网络里的目标机，再经跳板开一个 SOCKS5 代理（密码 `shellrs-test`）：

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

## 目录

- `ShellRS/App`：入口、`AppModel`（核心、主机、打开的终端）、`AppKeychain`、标签页、表单里带标签的输入框。
- `ShellRS/Hosts`：`HostsModel`（主机、分组、凭据的快照和改动）、主机树（`HostTree`：分组在前、主机在后，搜索同电脑版）、主机列表、主机表单（认证、跳板、代理、分组）、分组表单、主机标记（`HostMark`：探测到系统后是它的图标和品牌色）。
- `ShellRS/Credentials`：凭据列表和表单（密码；私钥粘贴、从文件读、生成）。
- `ShellRS/Terminal`：`TerminalSession`（连接、问答、终端的事件）、`TerminalSurface`（SwiftTerm 的视图和委托，**只有这个文件 import SwiftTerm**：它的 `Terminal`、`TerminalOptions` 和核心的重名）、终端页、问答、打开的终端列表。
- `ShellRS/Files`：`FilesModel`（终端连接上的 SFTP 会话、传输队列、断开后接着传）、`TransferQueue`（照电脑版的队列）、目录浏览、传输队列页、已下载的文件。
- `ShellRS/Describe`：核心的错误和失败翻成文案（SFTP 的在 `DescribeSftp.swift`），删除前说的连带。
- `ShellRS/Assets.xcassets/OS`：系统图标，和电脑版是同一套 [Simple Icons](https://simpleicons.org)（CC0），按核心的 `HostOs.key` 命名。
- `ShellRS/Localizable.xcstrings`：全部文案。
- `Packages/ShellRSCore`：核心的 Swift 包（xcframework + 生成的接口）。

## 约定

- **核心不产出文案。** 失败是一串类型化的环节（`Failure.links`），`Describe` 逐节翻译、用「: 」连起来，措辞照电脑版的 `locales/*.yml`；`switch` 写全，核心加了变体这里就编不过，要补上文案。
- **文案**：中文是源语言，代码里直接写中文（`Text("主机")`、`String(localized:)`），英文在 `Localizable.xcstrings`；用词照 shell-rs 的 `CLAUDE.md` 用词表。插值先转成 `String`（`%@`）；数量用 `Int`（`%lld`），英文在 String Catalog 里分单复数。
- **秘密只进钥匙串**：密码、口令经核心写进 `AppKeychain`（`AfterFirstUnlockThisDeviceOnly`，不随备份去别的设备，靠 ShellRS 自己的同步走），数据库里没有秘密。
- **事件只拉不推**：每个核心对象一个 `Task` 循环 `nextEvent()` 到 `nil`，在主 actor 上更新模型。
- 核心的 `Group` 和 SwiftUI 的 `Group` 重名，视图里用别名 `HostGroup`。
- **标签各自记着打开时的主机**（同电脑版）：编辑、删除主机不碰已打开的终端；重新连接时按保存的主机再连。
- 断开的终端按 Enter 重连、按 Space 关闭（同电脑版），也有按钮。
- **SFTP 开在终端自己的连接上**（同电脑版右侧栏的「文件」，堡垒机上不用再登录一次）：终端断开它就断，终端重连后它自己开回来，传到一半的批次接着传，不再问是否续传（已经说过「继续」）。手机上的连接断了不会回来，所以不等引擎重试，终端一断就放下会话。
- **传输一次一批**，排队在 App 里（同电脑版）。下载放 `Documents/Downloads`（「文件」App 的「我的 iPhone › ShellRS」里看得到），点文件是下到缓存里用快速查看预览；上传先把选的文件拷进临时目录（选的文件到时可能已经拿不到），批次结束就删，启动时清掉上次留下的。
- 核心接口缺东西就改 shell-rs 的 `crates/shellrs-mobile`（单独提交、照那边的规矩测），再更新 `core-revision`、重跑 `scripts/build-core.sh`。
