# 广告与去除广告

iOS 版 ShellRS 的全部功能免费：SSH、SFTP、云同步都不再受限。开发靠 AdMob 高级原生广告支持；一个非消耗型内购「去除广告」可以把广告去掉。代码开源（MIT），想要没有广告的版本可以自己 fork 构建，见下文「不要广告的构建」。

## 广告放在哪

每处一条原生广告，单独占一节，不混在主机或终端的行里。广告下方有「去除广告」，点了打开设置里的广告一节。

| 位置 | 视图 | 条件 |
| --- | --- | --- |
| 窄窗口「主机」页 | `HostList`：「最近连接」之后、「全部主机」之前；没有最近连接时在最上面 | 不在搜索或排序，有主机 |
| 窄窗口「终端」页 | `SessionsView`：终端行之后；没有终端时在「没有打开的终端」下方 | 总是 |
| 宽窗口开始页 | `StartView`：最近连接和提示之后 | 没有终端在前面时 |

宽窗口的侧栏不放广告：它只有 260pt 宽，而且一直在终端旁边。终端、文件、表单和设置里也都不放。

布局在 `ShellRS/Ads/NativeAdCard.swift`，用代码搭 `NativeAdView`：
- 左边是 `MediaView`，120×120，满足 SDK 的最小尺寸；
- 右边依次是「广告」标记和广告主、标题、正文、行动按钮；
- AdChoices 标记放在右上角的 `AdChoicesView` 里，留在内边距以内，列表行的圆角不会裁掉它；
- 行动按钮是 `UILabel`、不接收点击，点击由 SDK 处理。

用测试广告时，SDK 会弹出「AdMob native ad validator」，结果是 No implementation issues found。

## 什么时候加载

`AdsModel`（`ShellRS/Ads/AdsModel.swift`）：

1. 等 StoreKit 回答（`PurchaseModel.adRemoval` 不再是 `.unknown`）。买过「去除广告」的设备从此什么都不做：不弹同意书，不初始化 SDK，不向 Google 发任何请求。
2. 没买的设备先走 Google UMP：每次启动都调 `requestConsentInfoUpdate`，法律要求时（欧洲经济区、英国、瑞士等）再用 `loadAndPresentIfRequired` 弹出同意书。`canRequestAds` 为真时才调 `MobileAds.shared.start`。
3. 广告位出现时加载这一位置的广告。加载过的广告保留 1 小时（Google 要求不显示超过一小时的广告），过了再加载。失败后这个位置 60 秒内不再试，过期的广告也不再显示。
4. 回到前台时，如果启动时没能拿到同意（例如离线），再试一次。
5. 购买后马上清掉所有广告；退款后广告回来。

不弹 App Tracking Transparency，不读取广告标识符（IDFA），Info.plist 里没有 `NSUserTrackingUsageDescription`。设置里的「广告隐私选项」只在 UMP 报告 `privacyOptionsRequirementStatus == .required` 时出现，用来改同意书的选择。

## 配置

`Config/ShellRS.xcconfig`：

| 设置 | 仓库里的值 | 去处 |
| --- | --- | --- |
| `SHELLRS_ADMOB_APP_ID` | Google 的示例 App：`ca-app-pub-3940256099942544~1458002511` | Info.plist `GADApplicationIdentifier` |
| `SHELLRS_NATIVE_AD_UNIT_ID` | Google 的原生广告测试单元：`ca-app-pub-3940256099942544/3986624511` | Info.plist `ShellRSNativeAdUnitID` |
| `SHELLRS_REMOVE_ADS_PRODUCT_ID` | `com.shellrs.ios.lifetime` | Info.plist `ShellRSRemoveAdsProductID` |

### 真实 ID 不进仓库

仓库里 Debug 和 Release 都是 Google 的测试 ID，真实的 App ID 和广告单元不提交。

**为什么**：ID 本身不是秘密，发布的 App 里就读得到。风险在无效流量：别人 clone 下来编的 Release 版如果带着真实单元，他们自己用、调试、点到的广告都算在这个 AdMob 账户上，量大了会被限制投放甚至停用账户。Google 也不许开发者点自己的正式广告（[测试广告](https://support.google.com/admob/answer/9388275)）。仓库里只放测试 ID 之后，从仓库编出来的任何构建都碰不到这个账户。

**真实 ID 从哪来**：
- App Store 构建：`release.yml` 从 GitHub Secret `ADMOB_APP_ID`、`ADMOB_NATIVE_AD_UNIT_ID` 读，作为构建参数传给 `xcodebuild archive`，命令行的值盖过 xcconfig 和 `Local.xcconfig`。用 Secret 是为了公开的运行日志里显示 `***`，不出现 ID。
  - 构建前检查：没设、格式不对，或还是 Google 的测试 ID（发布商 `3940256099942544`），就直接失败，不会上传一个只有测试广告的版本。
  - 构建后检查：archive 里 Info.plist 的两个值确实是 Secret 里的。
- 本机的 Release 构建（例如自己 archive）：写进不进库的 `Config/Local.xcconfig`，只对 Release：

  ```
  SHELLRS_ADMOB_APP_ID[config=Release] = ca-app-pub-…~…
  SHELLRS_NATIVE_AD_UNIT_ID[config=Release] = ca-app-pub-…/…
  ```

  Debug 仍是测试广告，开发时随便点。本机跑 Release 版时看到的是真实广告，不要点。
- `AdsModelTests.debugBuildsAskForGoogleTestAdsOnly` 检查测试宿主（Debug）里的两个 ID 都是 Google 测试发布商的：有人把真实 ID 写进 `ShellRS.xcconfig`，或在 `Local.xcconfig` 里不加 `[config=Release]`，测试就会失败。
- `Config/Info.plist` 里的 `SKAdNetworkItems` 照 Google 的 [3p-skadnetworks](https://developers.google.com/admob/ios/3p-skadnetworks) 列表原样抄（更新于 2026-01-30，共 50 项）。Google 更新列表时照抄替换。
- SDK 用 Swift Package：Google Mobile Ads 13.12.0、User Messaging Platform 3.1.0，都固定版本（同 SwiftTerm 的写法）。
- `ShellRS/PrivacyInfo.xcprivacy` 是 App 自己的隐私清单：不跟踪，以及用到的 required-reason API（UserDefaults、文件时间戳、核心数据库检查磁盘）。Google 的两个框架自带清单。

### 测试时的开关

- 在 XCTest 宿主里（`XCTestConfigurationFilePath`）或设了 `SHELLRS_DISABLE_ADS=1`（截图用）时，`AdsConfiguration.bundled` 为空，没有广告。
- Debug 构建设 `SHELLRS_UMP_DEBUG_EEA=1`：UMP 按欧洲经济区处理，可以看到同意书和「广告隐私选项」。要先在 AdMob 里建好 GDPR 消息，见下文清单。

## 不要广告的构建

两种做法，任选一种，都不用改代码：

1. 在 `Config/Local.xcconfig` 里写一行 `SHELLRS_NATIVE_AD_UNIT_ID =`（留空）。没有广告位，不弹同意书，不初始化 SDK，设置里也没有广告一节。SDK 仍会链接进 App。
2. 在 Xcode 的 Package Dependencies 里移除 `swift-package-manager-google-mobile-ads` 和 `swift-package-manager-google-user-messaging-platform`。用到 SDK 的只有 `GoogleAdsService.swift` 和 `NativeAdCard.swift`，都包在 `#if canImport(...)` 里，没有 SDK 时 `AdsModel` 没有服务，照样编译运行。这时可以顺手删掉 Info.plist 里的 `GADApplicationIdentifier` 和 `SKAdNetworkItems`。

发布自己的 fork 时，请换掉 Bundle ID、App 名称和图标。要放自己的广告，就像上面「真实 ID 从哪来」那样填自己的 App ID 和广告单元。

## 去除广告（内购）

`ShellRS/Purchases/`：

- `PurchaseStore.swift`：StoreKit 2 适配层。只认 `SHELLRS_REMOVE_ADS_PRODUCT_ID` 这个非消耗型商品，并且要求交易来自本 App 的 Bundle ID。
- `PurchaseModel.swift`：提供 `adRemoval`（`.unknown` / `.notPurchased` / `.purchased`）、价格、购买和恢复。
  - 交易更新在第一次查询前订阅，验证通过才 finish。
  - 查询期间到了购买或更新，就不用查询的旧快照。
  - 退款的更新比滞后的权益快照新，不会被快照复活。
  - 未验证的权益不去广告，也不抹掉已验证的。
- 不再有试用、钥匙串缓存和时间高水位：现在只关系到广告，StoreKit 离线时也给本机验证过的权益。
- 设置里的广告一节：「去除广告 · 价格」、已去除时的状态、「恢复购买」、「广告隐私选项」，以及购买结果的提示。

本地测试用 `ShellRS Purchases` scheme，它带 `ShellRSTests/Purchases.storekit`：一个「去除广告」商品，测试价 $2.99，不是线上售价。

```sh
TEST_RUNNER_SHELLRS_TEST_STOREKIT=1 xcodebuild -project ShellRS.xcodeproj -scheme 'ShellRS Purchases' \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  -skipPackagePluginValidation -only-testing:ShellRSTests/StoreKitPurchaseTests test
```

## 上线前清单

**AdMob**
- [ ] 在「隐私权和消息」里建 GDPR（欧洲法规）消息，按需再建美国州法规消息；不建 IDFA 说明消息（不弹 ATT）。
- [ ] 开发者网站 shellrs.com 根目录放 `app-ads.txt`：`google.com, pub-<发布商 ID>, DIRECT, f08c47fec0942fa0`。发布商 ID 在 AdMob 的「设置 › 账号信息」里，也就是 App ID 里 `ca-app-pub-` 和 `~` 之间的数字。网址要和 App Store 里填的营销或支持网址同一个域名。
- [ ] 在 GitHub 设好 `ADMOB_APP_ID`、`ADMOB_NATIVE_AD_UNIT_ID` 两个 Secret，见 [构建与发布](RELEASE.md)。
- [ ] 上架后在 AdMob 里把应用关联到 App Store 的条目。
- [ ] 在「屏蔽控制」里按 App 的年龄分级设最高广告内容分级。

**App Store Connect**
- [ ] `com.shellrs.ios.lifetime` 改名「去除广告 / Remove Ads」，更新描述、价格和审核截图。截图拍设置里的广告一节。
- [ ] `com.shellrs.ios.trial30`：未批准就删除；已批准的删不掉，下架（Remove from Sale）。
- [ ] App 隐私问卷按 Google 的[数据披露说明](https://developers.google.com/admob/ios/privacy/data-disclosure)补上 AdMob 收集的数据。不用于跟踪：不读 IDFA。
- [ ] 描述写明：免费使用，含广告，可内购一次性去除；代码开源的地址。
- [ ] 审核备注：广告的位置；内购在「设置 › 去除广告」。

**真机（TestFlight）**
- [ ] TestFlight 构建看到的是真实广告（没有「Test mode」字样），不要点。
- [ ] 去除广告后广告立即消失；重启后不再请求广告。
- [ ] 恢复购买；在另一台设备恢复；沙盒退款后广告回来。
- [ ] 在欧洲的设备或 VPN 下看到同意书和「广告隐私选项」。
