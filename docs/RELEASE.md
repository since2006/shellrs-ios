# 构建与发布（GitHub Actions）

两个工作流都跑在 GitHub 托管的 `xcode-27` runner 上（Apple 芯片，macOS 27，默认 Xcode 27.1，带 Rust）。

- `.github/workflows/ci.yml`：推到 `main` 和每个 PR 时编核心、编 App，在 iPhone 模拟器上跑测试。不要 secrets，fork 里也能跑。
- `.github/workflows/release.yml`：推 `v*` tag，或在 Actions 页手动运行时，编 Release、签名、上传到 App Store Connect，构建随后出现在 TestFlight。提交审核仍在 App Store Connect 里手动点。只在 `since2006/shellrs-ios` 里跑，fork 不会跑。

## 核心

`.github/actions/core` 是两个工作流共用的一步：

1. 读 `Packages/ShellRSCore/core-revision`；
2. 把 shell-rs（公开仓库）在这个提交检出到 `shell-rs/`；
3. 照它的 `rust-toolchain.toml` 装工具链和 iOS 目标；
4. 跑 `SHELLRS_DIR=shell-rs scripts/build-core.sh`。

- 编出的 xcframework 和 `ShellRSCore.swift` 按 core-revision 缓存，同一个核心只编一次。
- 编完后检查 `ShellRS/About/Licenses.json` 没变。核心的依赖变了，就要把新的清单一起提交。

更新核心：在 shell-rs 那边提交后，把提交号写进 `core-revision`，本机跑 `scripts/build-core.sh`，把 `Licenses.json` 和 `core-revision` 一起提交。

## 一次性设置

1. **App Store Connect API 密钥**：「用户和访问 › 集成 › App Store Connect API」，新建一个团队密钥，角色选 **Admin**。自动签名要在云端创建、取用分发证书，App Manager 角色不够。下载 `.p8` 文件，它只能下载一次。
2. **GitHub**：仓库的 Settings › Environments 新建 `app-store`，可以加 Required reviewers，每次上传前要人点一下批准。在这个 environment（或仓库）里加：

   | 名称 | 类型 | 内容 |
   | --- | --- | --- |
   | `ASC_KEY_ID` | Secret | 密钥 ID，例如 `ABC123DEFG` |
   | `ASC_ISSUER_ID` | Secret | Issuer ID（UUID，在密钥列表上方） |
   | `ASC_KEY_P8` | Secret | `.p8` 文件的全部内容，包括 `-----BEGIN PRIVATE KEY-----` 那两行 |
   | `DEVELOPMENT_TEAM` | Variable | Team ID（10 位） |
   | `ADMOB_APP_ID` | Secret | AdMob 的 App ID，`ca-app-pub-…~…` |
   | `ADMOB_NATIVE_AD_UNIT_ID` | Secret | 高级原生广告单元 ID，`ca-app-pub-…/…` |

   仓库里只有 Google 的测试 ID（见 [广告与去除广告](ADS.md#真实-id-不进仓库)），App Store 构建的真实 ID 只从这两个 Secret 来。ID 本身算不上秘密，发布的 App 里读得到；用 Secret 是因为仓库公开后谁都能看 Actions 的运行日志，Secret 在日志里显示成 `***`。没设、格式不对或还是测试 ID 时，工作流在构建前就失败。

3. App Store Connect 里已有 Bundle ID 为 `com.shellrs.ios` 的 App 记录。

## 发一个版本

1. 改 `Config/ShellRS.xcconfig` 的 `MARKETING_VERSION`（例如 `1.1`），提交并推到 `main`。
2. 打 tag 推上去：`git tag v1.1 && git push origin v1.1`。tag 必须是 `v` 加 `MARKETING_VERSION`，不一样时工作流直接失败。
3. 工作流做这几件事：
   - 检查两个 AdMob Secret 是这个 App 的真实 ID；
   - 构建号用 UTC 日期和时间（例如 `20261110.1537`），每次上传都更大，不用手改 `CURRENT_PROJECT_VERSION`；
   - `xcodebuild archive` 自动签名：`-allowProvisioningUpdates` 加 API 密钥；同时把真实的 AdMob ID 作为构建参数传进去，archive 后再核对 Info.plist；
   - `xcodebuild -exportArchive` 用 `Config/ExportOptions.plist`（`method = app-store-connect`、`destination = upload`），导出时直接上传；
   - dSYM 存为这次运行的 artifact。
4. 处理完成后（通常十几分钟），构建出现在 TestFlight。在 App Store Connect 的版本页选这个构建，填好更新说明，提交审核。

同一版本要再上传一次（例如修了问题），在 Actions 页手动运行 `release`，或删掉 tag 重推。

## 本机做同样的事

```sh
scripts/build-core.sh
xcodebuild archive -project ShellRS.xcodeproj -scheme ShellRS -configuration Release \
  -destination generic/platform=iOS -archivePath build/ShellRS.xcarchive \
  -skipPackagePluginValidation -allowProvisioningUpdates
```

再在 Xcode 的 Organizer 里 Distribute App。Team 来自 `Config/Local.xcconfig` 的 `DEVELOPMENT_TEAM`。真实的 AdMob ID 也要在 `Local.xcconfig` 里写好，只对 Release（`SHELLRS_ADMOB_APP_ID[config=Release] = …`，见 [广告与去除广告](ADS.md#真实-id-不进仓库)）；没写就是测试广告，上架后没有收入。
