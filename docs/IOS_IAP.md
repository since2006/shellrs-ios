# iOS 30 天试用与永久解锁

实现范围仅在本仓库的 iOS/iPadOS App。没有修改 Rust 核心或桌面端；按本次用户要求不新增配置导出。

## 商品与配置

Bundle ID 为 `com.shellrs.ios`，部署目标 iOS 17.0。用户已确认两个真实 Product ID：

| 商品 | 类型 | Product ID |
| --- | --- | --- |
| 30 天试用 | Non-Consumable，价格 0 | `com.shellrs.ios.trial30` |
| 永久解锁 | Non-Consumable，一次性付费 | `com.shellrs.ios.lifetime` |

`Config/ShellRS.xcconfig` 定义 `SHELLRS_TRIAL_PRODUCT_ID`、`SHELLRS_LIFETIME_PRODUCT_ID`，经 `Config/Info.plist` 的 `ShellRSTrialProductID` / `ShellRSLifetimeProductID` 注入，`PurchaseConfiguration.bundled` 读取。`Config/Local.xcconfig` 可以覆盖用于开发的 ID。空 ID、重复 ID 或未展开的构建变量不会启动购买。价格和币种始终来自 StoreKit `displayPrice`；试用商品不是零价时禁止领取。

Apple 对这种限时试用的说明见 [App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)。App Store Connect 内的实际商品价格、可销售状态、协议和审核结果尚未由本次开发会话验证。

## 文件与接入

- `ShellRS/Purchases/PurchaseStore.swift`：StoreKit 2 适配层、可注入协议、商品查询、购买结果、当前权益及交易历史、交易更新和 finish。
- `ShellRS/Purchases/PurchaseModel.swift`：可注入时钟和缓存、授权状态、统一门禁、前台刷新、倒计时、购买及恢复反馈、钥匙串缓存。
- `ShellRS/Purchases/PurchaseView.swift`：首次领取、到期购买、提前买断、恢复和状态页面。
- `ShellRS/App/AppModel.swift`、`AppPresentation.swift`、`RootView.swift`、`SettingsView.swift`：注入授权模型、单一弹窗宿主、启动监听、前台刷新和设置入口。
- `ShellRS/Terminal/TerminalSession.swift`、`ShellRS/Files/FilesModel.swift`：新建 SSH 和首次打开 SFTP 的门禁。
- `ShellRS/Localizable.xcstrings`：完整中文源文案和英文翻译；项目原先只有中英文。
- `ShellRSTests/PurchaseModelTests.swift`：Mock 商店、Mock 时钟、内存缓存和业务/门禁测试。
- `ShellRSTests/StoreKitPurchaseTests.swift`、`Purchases.storekit`：本地真实 StoreKit 验证交易的集成测试。
- `ShellRS.xcodeproj/xcshareddata/xcschemes/ShellRS Purchases.xcscheme`：专用本地内购 Scheme，常规 `ShellRS` Scheme 不启用模拟价格。
- 原有 AppModel、TerminalSession、Server 和呈现连续性测试显式注入测试授权，生产代码没有解锁开关。

## 授权与连接策略

唯一业务判断为 `PurchaseModel.canStartNewConnection`；只有实际发起新连接时调用 `authorizeConnection()`，被拒绝时请求购买页。启动、回到前台、刷新授权或试用到期只更新状态，不自动弹出购买页；设置中的主动访问入口保留。

- `AppModel.connect` 拦截主机列表、最近连接等 UI 发起的新终端，不创建空标签。
- 按用户最新要求，已有终端的按钮重连和断开后 Enter 重连不再检查授权，沿用原有实现。
- `TerminalSession.openFiles` 的 opener 仅在首次成功建立 SFTP 之前检查；该工作区成功打开过 SFTP 后，终端重连后的文件恢复不再检查。
- SFTP 通道掉线重试沿用原有 Rust 引擎，不增加 iOS 重试调度或重连门禁。
- 仓库未发现其他快捷方式、深度链接或后台自动恢复 SSH 的入口。

有效永久权益优先；否则试用以已验证交易 `originalPurchaseDate + 30 × 24 小时` 判断。读取 `Transaction.all` 中最早的已验证试用日期，确保试用被撤销后重新领取也不重置起点。未验证交易不授予新权益；取消和待批准有独立反馈。交易更新在初次查询前订阅，已验证并持久化后才 finish；持久化失败保留未完成交易供 StoreKit 重投。

退款/撤销更新清除对应权益；稳定交易 ID 和签名时间避免重复、乱序更新，以及暂时落后的查询快照复活已退款授权。完整空权益快照会移除原有有效权益，支持账户切换；部分验证失败不会清空此前已验证权益。恢复购买只在用户操作时调用 `AppStore.sync()`。

到期不会调用已有 SSH/SFTP 会话的 disconnect/end。已有终端可以持续重连；已经成功打开的 SFTP 可以自动恢复，这是用户选择的简化规则。关闭该工作区后，新建终端仍需授权。查看、编辑、删除主机、凭据管理、同步、设置和官网入口仍可使用。用户明确取消了配置导出需求。

## 离线与时间

优先使用 StoreKit 本机已验证的权益；另将最近已验证交易元数据、商品配置和时间高水位保存在独立 service 的设备专用钥匙串中，不使用首次启动时间或 UserDefaults 解锁标记。缓存不能跨商品配置使用，读取失败/损坏不产生授权。永久用户在查询或网络故障时继续使用已验证授权；从未验证过购买的设备显示待验证状态。

试用判断使用系统时间、高水位和进程单调时钟推进，回拨时钟不会倒退有效时间或冻结运行中试用；试用有效期内每分钟，以及交易变化、前台刷新和到期时持久化高水位。永久授权不依赖试用计时。离线无法立即得知退款；在联网刷新或交易更新后处理。没有引入远端可信时间服务，持续离线、设备重启及人为时钟操纵不能获得服务器级防篡改保证；进程未运行期间且系统时间回拨时无法精确还原真实经过时长。

## 本地构建与测试

本机使用 Xcode 27.1 和已生成的 ShellRSCore xcframework。完整测试命令：

```sh
TEST_RUNNER_SHELLRS_TEST_STOREKIT=1 xcodebuild \
  -project ShellRS.xcodeproj -scheme 'ShellRS Purchases' \
  -destination 'platform=iOS Simulator,id=5D221A22-DAA0-4A07-859D-B67B8EED72CE' \
  -derivedDataPath build/IAPDerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -skipPackagePluginValidation ARCHS=arm64 test
```

验证记录（2026-10-31）：

| 环境 | 范围 | 结果 |
| --- | --- | --- |
| iPhone Duo / iOS 27.1 | 全量，包括本地 StoreKit 交易 | 85 项测试通过，`TEST SUCCEEDED` |
| iPhone 15 Pro / iOS 17.4 | `-only-testing:ShellRSTests/PurchaseModelTests -only-testing:ShellRSTests/StoreKitPurchaseTests` | 16 项测试通过，`TEST SUCCEEDED` |
| iPhone Duo / iOS 27.1 | 弹窗时机调整后的 PurchaseModelTests、StoreKitPurchaseTests、AppModelTests | 28 项测试通过，`TEST SUCCEEDED` |

复查清理后通过全量和最低系统测试；后续弹窗时机调整另通过上表 28 项针对性测试。清理包括合并重复缓存配置类型、移除重复首次提示标记和时钟锚点、统一到期状态处理及计算；没有试用权益时不再扫描全部交易历史，已有商品数据时不重复加载，非试用状态不再每分钟写入钥匙串。配置导出及额外重连调度无残留。

另已通过 `git diff --check`、Info.plist 校验、StoreKit JSON 校验及新增字面量的英文翻译完整性检查。构建日志只有原有终端焦点代码的未使用返回值警告，无新增代码编译错误。桌面端不在本项目构建目标内，未运行桌面构建，也未修改任何共享 Rust/桌面源文件。

最低系统回归使用同一命令，将 destination 换为 `platform=iOS Simulator,id=25AC1150-79CA-48A7-A274-E9699C9C576F`（iPhone 15 Pro / iOS 17.4）。常规 `ShellRS` Scheme 未设置 `SHELLRS_TEST_STOREKIT=1` 时跳过本地 StoreKit 集成测试；普通单元测试仍运行。未提供 `SHELLRS_TEST_SSH`，真实 SSH 服务器测试按原有条件跳过。需要真实服务器的 SFTP 断线续传仍须按 README 设置服务器后验证。

本地 `.storekit` 内的 $9.99 **仅为测试价格**，不是生产售价，不随常规 App 构建打包。测试涵盖领取、29 天、恰好 30 天、提前/到期后买断、取消/待批准/验证失败、离线和缓存损坏、恢复日期、退款和乱序快照、新建连接限制、既有终端重连放行及中英文界面接入。本地测试不证明跨 Apple 账户/跨设备的生产恢复行为。

## 发布前需在 App Store Connect / Sandbox / TestFlight 验证

- [ ] App 下载价格为免费，App ID 启用内购；协议、税务与银行资料有效。
- [ ] 两个已确认 ID 位于 `com.shellrs.ios` 对应的同一 App 中，均为非消耗型。
- [ ] `30-day Trial` / `30 天试用` 为零价并可在目标地区领取；核实当前账户能配置该商品，审核名称、说明和截图符合 Apple 规则。
- [ ] 永久解锁已设置实际售价、地区、商品状态与本地化，App 显示当前本地化价格。
- [ ] 真机领取成功后立即可以 SSH/SFTP；以 Sandbox 测试方式核实固定 30 天业务截止，旧连接及其重连保留，新建终端和首次打开 SFTP 被拦截。
- [ ] 同账户卸载重装、换 iPhone、在 iPad 恢复时保留原始试用起点；永久购买跨同一 App 的设备恢复。
- [ ] 真机恢复无记录、离线失败、取消、Ask to Buy 待批准、App 外批准、中断后恢复和重复交易。
- [ ] 退款/撤销后新连接被限制，离线缓存用户联网后及时更新；试用撤销后重新领取不重置起点。
- [ ] 已购买用户离线 SSH/SFTP 正常；App 回前台、试用到期和系统时间回拨符合预期。
- [ ] 确认不会自动订阅或续费，说明中保留桌面端免费政策；发布使用常规 `ShellRS` Scheme，不启用本地测试配置。
