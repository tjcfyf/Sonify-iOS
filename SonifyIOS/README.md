# Sonify for iOS · M0 骨架

这是 [XiaoZhi0729/Sonify](https://github.com/XiaoZhi0729/Sonify)（Android，Jetpack Compose + Media3，147k 行）的 iOS 移植起点。
完整的技术评估、模块映射、iOS 15 红线与分期计划在同目录的 **`../Sonify-iOS移植方案.md`**。

> **状态：M0（骨架）**。可编译性未在本机验证（生成环境是 Linux，无 Xcode / Swift 工具链），首次打开如有报错，按提示修即可，结构是对的。

---

## 1. 怎么跑起来

前置：macOS + Xcode 15 或 16、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
cd SonifyIOS
xcodegen generate          # 生成 Sonify.xcodeproj
open Sonify.xcodeproj
```

然后：

1. Target **Sonify** → Signing & Capabilities → Team 选你的 Apple ID；Bundle Identifier 改成你自己的（如 `com.yourname.sonify`），否则会和别人冲突。
2. 真机 iPhone 12（iOS 15）直接 Run；免费账号签名 7 天过期，之后用 AltStore / Sideloadly 重签。
3. 导入音乐：资料库页右上角 `+`，或把音频文件通过「文件」App / 访达共享拷进 `Sonify/Documents`（Info.plist 已开 `UIFileSharingEnabled`）。

跑单测：`Cmd+U`（target `SonifyTests`，验证 LRC/KRC 解析语义）。

---

## 2. 已实现（M0）

| 能力 | 文件 | 说明 |
|---|---|---|
| iOS 15 液态玻璃 | `Design/GlassStyle.swift` | `UIVisualEffectView` + `UIViewPropertyAnimator.fractionComplete` 调强度；双层描边 + 连续圆角 |
| 主题 / 11 种强调色 | `Design/Theme.swift` | 改一处全 App 生效 |
| 播放内核 | `Playback/PlayerEngine.swift` | 队列、上一首/下一首、seek、倍速（含慢放保音调）、睡眠定时（最后 20 秒淡出）、播放恢复 |
| 后台 + 线控 + 锁屏 | `Playback/PlayerEngine.swift` / `NowPlayingCenter.swift` | AVAudioSession(.playback)、MPRemoteCommandCenter、MPNowPlayingInfoCenter、封面 |
| 歌词解析 | `Lyrics/LyricParser.swift` | LRC / KRC / 无时间戳兜底；逐词结束时间语义与 Android 一致；翻译最近匹配；制作人员过滤 |
| 卡拉 OK 渲染 | `Lyrics/LyricsView.swift` | 逐词遮罩高亮、当前行放大、自动滚动、锁屏歌词行 |
| 本地资料库 | `Library/LibraryScanner.swift` / `LibraryStore.swift` | Documents 递归扫描、AVAsset 元数据/封面、同名 `.lrc` 自动读取、收藏 |
| 页面 | `Pages/HomeView.swift` / `LibraryView.swift` / `NowPlayingView.swift` / `SettingsView.swift` | 首页 / 资料库 / 播放页 / 设置 |
| 工程化 | `project.yml` / `Tests/LyricParserTests.swift` | XcodeGen 一键生成；解析器单测 |

## 3. 还没做（对应里程碑）

- **M1**：AVPlayerItem 就绪用 KVO 替换固定延时；队列拖拽排序；文件夹监听；播放速度菜单记住；音频焦点/打断细节。
- **M2**：Pear Wall（`pearmesh/shaders/*.frag` → Metal）；封面真实取色（Palette 等价）；渐进模糊顶栏接滚动偏移；越界回弹；横屏分栏。
- **M3**：在线曲库（`libkugou_server` 交叉编译或中转，见方案 §3.4）；`kugou://song/<hash>` 惰性解析用 `AVAssetResourceLoaderDelegate`；磁盘缓存。
- **M4**：KRC 内嵌翻译/罗马音完整对齐（当前已解析 `[language:n]` 分块）；自定义歌词字体；HDR 高光；高潮起点。
- **M5**：WidgetKit 小组件、ShazamKit 识曲、评论区、主题取色器、更新提示。

## 4. 文件职责（对着 Android 看更清楚）

| iOS | Android 对应 |
|---|---|
| `Playback/PlayerEngine.swift` | `code/MediaController.kt` + `YosPlaybackService` |
| `Playback/NowPlayingCenter.swift` | `MediaSession` / 通知栏 |
| `Playback/Track.swift` | `MediaItem` / `MediaMetadata` |
| `Lyrics/LyricEntry.swift` | `code/utils/lrc/LyricEntry.kt` |
| `Lyrics/LyricParser.swift` | `code/utils/lrc/YosLrcFactory.kt` |
| `Lyrics/LyricsView.swift` | `ui/widgets/YosLyricView.kt` + `YosLyricGeometry.kt` |
| `Design/GlassStyle.swift` | Haze + Backdrop + `ui/widgets/basic/*` |
| `Library/LibraryScanner.swift` | libPhonograph + TagLib |
| `Settings/SettingsStore.swift` | `YosDataSaver` + `SettingOption` |

## 5. 首次编译最可能踩的坑

1. **`@main` + `@MainActor`**：`SonifyApp` 标了 `@MainActor` 才能引用 `PlayerEngine.shared`（main-actor 单例）；如果 Xcode 仍报隔离错误，把 `shared` 改成 `nonisolated(unsafe) static let` 或把单例改成在 `onAppear` 里懒创建。
2. **`AVAsset.load(.duration)`**：iOS 15 的 async 属性 API；若报不可用，退回 `asset.duration`（会有警告，但可用）。
3. **`AnyCancellable` / Combine**：`RootView` 用了 `onReceive`，已 `import Combine`。
4. **玻璃在真机上偏亮/偏暗**：iPhone 12 的 `systemUltraThinMaterial` 与模拟器有差异；调 `GlassStyle.intensity` 与 `tintOpacity` 两个参数即可，别改结构。
5. **没有声音**：检查 Info.plist 的 `UIBackgroundModes: audio` 是否被 XcodeGen 保留，以及真机是否静音键打开（`AVAudioSession.playback` 不受静音键影响，但会受"音频路由"影响）。

## 6. 许可

上游为 **GPL-3.0**。此移植及其衍生作品必须继续以 GPL-3.0 开源，保留上游署名与第三方 NOTICE（Pear Wall / NexioSchedule / Cresto 等）。**不要提交到 App Store**（GPL 与 Apple 分发条款冲突）。

---

## 7. 没有电脑：用 GitHub Actions 出 IPA

仓库根目录已带 `.github/workflows/build-ipa.yml`：**每次 push 到 `main` 或手动触发，都会在 GitHub 的 macOS 机器上生成未签名 IPA**，并挂到 Releases 与 Actions Artifacts。

产物位置（手机浏览器可直接进）：

- Releases：`https://github.com/<你的账号>/<仓库>/releases` → 下载 `Sonify-unsigned.ipa`
- 或 Actions → 最近一次运行 → Artifacts → `Sonify-unsigned-ipa`

### 安装方式（按你的 iOS 版本选）

| 方式 | 前提 | 说明 |
|---|---|---|
| **TrollStore** | iOS 15.0–15.4.1（部分机型可到更高）且已装 TrollStore | 把 IPA 存进「文件」→ 用 TrollStore 打开安装，永久有效，不需要证书 |
| 付费开发者账号 ad-hoc | Apple Developer $99/年，登记 iPhone UDID | 可全流程在 CI 完成签名，再用 Safari 走 itms-services 安装；需把证书/描述文件放 Actions Secrets |
| 第三方签名工具（Esign / Scarlet 等） | 手上有可用证书 | 手机上直接签名安装；免费共享证书经常掉签 |
| 免费 Apple ID | **必须有电脑**（Xcode / AltServer 配对） | CI 里无法用免费账号签名，这条路对"无电脑"不成立 |

> 未签名 IPA 不能直接点安装（iOS 会提示无法验证），必须经过上面任一方式。
> 如果你的系统是 15.5 及以上，TrollStore 是否可用要按机型具体核对，别盲试。
