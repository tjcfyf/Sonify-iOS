# Sonify → iOS 移植方案（v1，基于仓库实际源码盘点）

> 目标机：iPhone 12 / iOS 15（你的设备）。所有结论按 iOS 15 可用来写，不按 iOS 26 的新玻璃 API 写。
> 盘点对象：`XiaoZhi0729/Sonify`，commit 抓取于 2026-11-24。

---

## 0. 结论速览

**一句话：Android 端 147,794 行 / 557 个 Kotlin 文件，1:1 全量移植不是"移植"，是"重做一款播放器"。但 Sonify 的价值集中在四块——液态玻璃视觉、逐字歌词、本地库+播放、酷狗在线曲库——这四块里前三块可以高质量复刻，第四块卡在一个预编译的 Android-only 原生库上。**

| 模块 | 移植可行性 | 说明 |
|---|---|---|
| 液态玻璃 UI / 主题 / 底栏定制 | **A（可高保真复刻）** | Haze/Backdrop 是 Compose 实现的"背景采样+多层模糊"，iOS 用 `UIVisualEffectView` + Metal 高斯 + 折射描边可以做得更接近 Apple 原味 |
| 播放内核（播放/队列/倍速/睡眠定时/后台/线控） | **A** | Media3 → AVQueuePlayer + AVAudioSession + MPNowPlayingInfoCenter + MPRemoteCommandCenter，语义一一对应 |
| 歌词（LRC/KRC 逐字、翻译、罗马音、字体、HDR 高光） | **A** | `LyricEntry` 语义已摸清，Swift 可 1:1 复刻解析与高亮几何 |
| 本地资料库（扫描、排序、MochiIndexBar 字母索引） | **A** | libPhonograph + TagLib → AVAsset 元数据 + 自建扫描器（ape/tta 等冷门格式需 FFmpeg） |
| 在线曲库（酷狗搜索/歌单/登录/URL 解析/音质档） | **C（受阻）** | 依赖 `libkugou_server.so`（Rust 本地 HTTP server，仅 armeabi-v7a/arm64-v8a Android 二进制），仓库不含源码 |
| 人声分离（TFLite MSS） | **C** | `.tflite` 模型被 .gitignore 排除，仓库本就不含模型；iOS 端要先有模型才能谈推理 |
| 状态栏歌词（Hook 方案） | **C（非越狱不可行）** | 非越狱 iOS 没有任何合法途径往状态栏挂歌词 |
| 桌面小组件 4×2 / 4×1 / 2×2 | **B** | WidgetKit 只有 small/medium/large，尺寸语义要重映射 |
| 听歌识曲 / 评论区 / 检查更新 | **B** | 识曲换 ShazamKit 或自建指纹；更新机制换 AltStore/自签流程 |

**务实路径：先拿 M0–M2（玻璃 UI + 本地播放 + 逐字歌词）做出一个"能天天用"的 iOS 版，在线曲库单独开一条线（见 §3.4 的三条路线），不要一开始就动在线。**

---

## 1. Android 端盘点（移植必须知道的硬事实）

### 1.1 规模

| 指标 | 数值 |
|---|---|
| Kotlin 文件 | 557（`app` + `overscroll_core`） |
| 代码行 | 147,794 |
| UI 体积 | `ui/` 4.2 MB（Compose 页面为主） |
| 数据层 | `data/` 896 KB |
| 播放/音频核心 | `code/` 744 KB |
| 单个最大文件 | `data/repositories/KugouRepository.kt` **194 KB**、`native/KugouApiService.kt` **109 KB**、`MainActivity.kt` 284 KB |
| 构建 | Gradle 9.3.1 / JDK 17 / SDK 37 / minSdk 23 |

> 这三个巨型文件就是移植的真实成本中心：它们不是"业务逻辑优雅分层"，而是长期堆叠的协议细节（风控、音质回退、错误码、缓存、登录态）。

### 1.2 架构骨架

- **单 Activity + 全 Compose**（`MainActivity` 即导航宿主，`ui/NavHost.kt`）。
- **播放单一事实源**：`object MediaController`（`code/MediaController.kt`）。
- **在线仓库**：`object KugouRepository`，经 OkHttp 打到 **本机 Rust HTTP server**（`http://127.0.0.1:<port>`），不是直连酷狗。
- **惰性 URL 解析**：队列里在线歌曲的 uri 是占位符 `kugou://song/<hash>`，ExoPlayer 真正读字节时才由 `KugouMediaSource.open()` 解析真实 CDN URL，配 Media3 `SimpleCache` 做磁盘缓存。这是整个播放体验的关键设计，iOS 必须用等价手段实现（见 §3.2）。
- **音质策略表驱动**：`QualitySwitchPolicy` 是纯函数，有 JVM 单测覆盖——这部分可以几乎原样搬成 Swift 纯函数 + XCTest。

### 1.3 依赖（决定 iOS 替换物）

| Android | 作用 | iOS 替换 |
|---|---|---|
| Jetpack Compose | 全部 UI | SwiftUI（iOS 15 可用部分，见 §4） |
| Haze 2.1.0 / Haze-blur | 玻璃模糊材质 | `UIVisualEffectView` + `UIViewPropertyAnimator` 强度控制 + Metal/CIFilter 自绘 |
| Backdrop（源码内嵌 `com.kyant`） | 实时背景采样 | `UIGraphicsImageRenderer` 快照 + 降采样 blur，或直接 MTKView |
| Media3 / ExoPlayer | 播放内核 | AVQueuePlayer / AVAudioEngine |
| Media3 FFmpeg 扩展 | 冷门格式软解 | FFmpeg 编译 `libavcodec`（iOS arm64），或 AudioConverter（flac/alac/wav 原生可解） |
| Coil | 图片加载 | AsyncImage + 自建磁盘缓存（或 Nuke） |
| MMKV | 键值存储 | UserDefaults / 自建 JSON 文件（要跨进程共享才需要 App Group） |
| OkHttp + Gson | 网络 + JSON | URLSession + Codable |
| TFLite | 人声分离推理 | TFLite C API 交叉编译 / Core ML（模型缺失，见 §3.5） |
| TensorFlow Lite 模型（MSS） | — | **仓库不含**（`assets/vocalsep/README.md` 明说） |
| libPhonograph (aar) | 本地库扫描 | 自建扫描 + AVAsset 元数据 |
| TagLib (Kyant0) | 标签读写 | AVAsset 只读；写入需 TagLib iOS 编译 |
| Shape/连续曲率圆角 | 圆角 | `RoundedRectangle(cornerRadius:style: .continuous)` 完全对应 |
| ComposeOverscroll（`overscroll_core`） | 越界回弹 | `UIScrollView` 弹簧 + CADisplayLink |
| ConfettiKit | 撒花动效 | 自绘 CAEmitterLayer |
| Palette / material-color-utilities | 封面取色 | `UIImage` 降采样 + k-means（或 CoreImage 平均色） |
| Lyric Getter API | 歌词来源 | 保留接口层，换基址 |

---

## 2. Android → iOS 架构映射

| Android 概念 | iOS 对应 | 备注 |
|---|---|---|
| `object MediaController`（单例、全应用唯一队列） | `@MainActor final class PlayerEngine` + `ObservableObject` | 单例仍保留，但要 `@MainActor` 化，所有状态变更串行 |
| `MediaSessionService`（`YosPlaybackService`） | `AVAudioSession(.playback)` + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | iOS 的后台播放靠 `UIBackgroundModes: audio` + audio session，不是 Service |
| `MediaItem` / `MediaMetadata` | `AVPlayerItem` + 自定义 `Track` struct | 建议 `Track` 是纯值类型，AVPlayerItem 只是运行时载体 |
| `SimpleCache` | 自建 `AudioCache`（LRU 目录 + 文件锁） | AVURLAsset 无原生分段缓存；要么自建 `AVAssetResourceLoaderDelegate`，要么先解析真实 URL 再缓存整段 |
| `kugou://song/<hash>` 惰性解析 | `AVAssetResourceLoaderDelegate` 拦截自定义 scheme，`shouldWaitForLoadingOf` 里异步解析后 302 | 这是 iOS 端最难写但最值得写的一段；M0 可先"播放前解析"降级 |
| `MMKV` | `UserDefaults(suiteName:)` / Codable JSON | 登录 token 建议 Keychain |
| Compose `State` / `remember` | `@Published` / `@State` | 注意 SwiftUI 差量刷新粒度不如 Compose，玻璃层要用 `drawingGroup` 慎用 |
| `YosLrcFactory` | `LyricParser`（已随骨架交付） | 语义见 §3.3 |
| `ui/pages/*` | `Sources/Pages/*` | 一页一文件，不要学 Android 那种巨型页面 |
| 单 Activity 导航 | `NavigationView` + `TabView`（iOS 15 无 `NavigationStack`） | iOS 16+ 才用 `NavigationStack`，要做 `#available` 分支 |

---

## 3. 五个移植关卡（按难度排序，逐个给方案）

### 3.1 关卡一：液态玻璃（决定"像不像"）

Android 侧实现拆开看是三层：

1. **背景采样**（Backdrop）：把下层内容实时渲染进纹理 → 缩小 → 高斯模糊 → 再作为材质背景。
2. **材质合成**（Haze）：模糊层 + 白色低透明度叠加 + 内阴影 + 边缘高光，参数随滚动位置渐变（渐进模糊顶栏）。
3. **描边**（iOS 27 双层立体玻璃描边）：外层细亮线 + 内层错位灰线 + 上下亮度差。

iOS 15 可用的三件套：

- `UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))` — 最省事，但**模糊半径不可调**，只有几档材质。
  - 想要"可调强度"：挂 `UIViewPropertyAnimator`，设 `fractionComplete = intensity`（0…1），能连续调低材质强度，这是 iOS 15 上最稳的做法（骨架里已实现）。
- **自绘模糊**：`UIGraphicsImageRenderer` 抓下层快照 → 降采样 1/4 → `CIGaussianBlur` → `UIImageView`。半径真正自由，但每帧抓快照很贵，只能在滚动停止/静态页用。
- **Metal**：`UIScene` 背景纹理 + `blur.frag` 等价 kernel，能做到 Android 那种"实时流体背景"。**Pear Wall 的 shader 可直接迁**：仓库里 `app/src/main/assets/pearmesh/shaders/` 有 `fullscreen.vert`、`blur.frag`、`material.frag`、`pinch.vert`、`rotation.vert`、`rotation.frag`，GLSL → MSL 是机械翻译（`texture2D`→`tex.sample`、`gl_FragColor`→`out.color`、`varying`→`[[stage_in]]` 结构体）。

**参数对齐表（照抄 Android 才能"像"）**

| 参数 | Android 取值方向 | iOS 落地 |
|---|---|---|
| 模糊强度 | 全局可调（设置页滑块） | `GlassStyle.intensity: 0…1` → animator.frac |
| 玻璃白叠加 | 极低 alpha（约 4%–12%，亮色模式更高） | `.white.opacity(0.06)` + 模式下修正 |
| 描边 | 1px 外层 `white.opacity(0.35)` + 内层 `black.opacity(0.08)` | `strokeBorder` 两层 `RoundedRectangle` |
| 圆角 | 连续曲率（Shapes 库） | `.continuous` |
| 顶栏渐进模糊 | 随 scroll offset 从 0→1 插值 | `GeometryReader` + `preference` 驱动 intensity |
| 性能 | 120Hz 滚动优化过 | iOS 15 关 `drawingGroup`，玻璃层用 `compositingGroup` 单独栅格化 |

### 3.2 关卡二：播放内核

必须逐项对齐的行为：

| 行为 | Android 实现 | iOS 做法 |
|---|---|---|
| 队列 | `MediaController` 维护 `nowPlayingQueue` + 索引 | `AVQueuePlayer` 或单 `AVPlayer` + 自维护队列（**推荐后者**：AVQueuePlayer 换项黑屏/无法任意跳，播放器 App 基本都自维护） |
| 后台播放 | Media3 Service | `AVAudioSession.setCategory(.playback, mode: .default)` + `UIBackgroundModes: audio` |
| 线控 | MediaSession | `MPRemoteCommandCenter`（play/pause/next/prev/changePlaybackPosition/changePlaybackRate） |
| 锁屏信息 | MediaMetadata | `MPNowPlayingInfoCenter`（title/artist/artwork/duration/elapsed/rate） |
| 音质切换 | `QualitySwitchPolicy` 表驱动 + 失败回退 | 纯函数照搬；回退链：目标档→低一档→标准→失败上报 |
| 缓存 | `SimpleCache`（LRU，边下边播） | 自建：解析出真实 URL 后写 `Caches/Audio/<hash>.<ext>`，命中直接 `fileURL`；播放中并发下载再切 |
| 冷门格式 | FFmpeg 扩展 | iOS 原生支持 mp3/aac/m4a/alac/wav/aiff/flac（iOS 11+）；ape/wma/tta/opus 需 FFmpeg 或放弃 |
| 倍速 | ExoPlayer `setPlaybackSpeed` | `AVPlayer.rate`（注意 <1 倍速需 `AVAudioTimePitchAlgorithm.timeDomain` 保音调） |
| 睡眠定时 | 倒计时 + 淡出 | `Timer` + 线性降 volume（`AVAudioMix` 或主音量淡出） |
| Crossfade 智能过渡 | 节拍+能量分析 | `AVAudioMix` 双 player 交叉淡入淡出；节拍分析需另做（M3 再说） |
| 播放恢复 | `PlaybackRestoreGate` | `UserDefaults` 存 queue + position，冷启动恢复但要防"刚杀进程又恢复"的死循环 |

**惰性 URL（核心插桩点）**：iOS 上实现方式

```swift
// 方案 A（推荐，效果等同 Android）：自定义 scheme + ResourceLoader
let asset = AVURLAsset(url: URL(string: "sonify-kugou://song/\(hash)")!)
asset.resourceLoader.setDelegate(KugouResourceLoader(), queue: .global())
// delegate 内异步解析真实 CDN URL，然后 AVAssetResourceLoadingRequest 用 302 重定向或直接喂数据

// 方案 B（M0 降级）：播放前解析
let realURL = try await kugou.songURL(hash: hash, quality: current)
player.replaceCurrentItem(with: AVPlayerItem(url: realURL))
```

A 的收益：列表滚动时不发任何网络请求、切歌零等待（命中缓存时）；代价是 resourceLoader 要自己处理 `contentInformationRequest` / `dataRequest`，坑多。**建议 M0 先用 B，M3 再上 A。**

### 3.3 关卡三：歌词引擎（最容易做到 1:1）

Android 的 `LyricEntry` 语义已经拿到，直接决定 iOS 模型：

```kotlin
data class LyricEntry(
    val mainLyric: List<Pair<Float, String>>, // 时间(ms) → 词/行文本
    val translation: String? = null,
    val romanization: String? = null
) { val startTime get() = mainLyric.firstOrNull()?.first ?: 0f }
```

关键语义（移植时不能想当然）：

- `mainLyric` 是**"高亮结束时间 → 文本"**，不是"开始时间 → 文本"；首元素是行起点锚点（文本空串），末尾再补一个空串锚点。渲染时用 `t[i]` 作为第 i 个词的**结束**，开始取 `t[i-1]`。
- **KRC**：行 `[start,duration]`，词 `<offset,duration,0>字`；词结束 = `start + offset + duration`（offset 是相对行起点的偏移）。
- **LRC** 没有词级时间：整行一个 span，靠"行起点 + 下一行起点"插值。
- **无时间戳纯文本**（M4A ©lyr / MP3 USLT 常见）：按总时长均分合成时间轴，否则滚动 UI 不动。
- **制作人员署名过滤**（作词/作曲/编曲…）不上屏。
- 翻译匹配：`nearestText`（时间最近的行）优先，其次按序号，最后才用行内第二段文本。
- KRC 内嵌翻译/罗马音：按结构分类（language + 是否逐字样式），**不能只看 language 值**——仓库里明确踩过"罗马音排在翻译前面导致整首译文为空"的坑。

渲染（Compose 侧 `YosLyricView` + `YosLyricGeometry`）→ SwiftUI 落地方式：

- 当前行：每个词用两色 `Text` 叠加 + `.mask` 渐变进度（或 `Canvas` 画已高亮宽度）。
- 相邻行：`scaleEffect` + `opacity` 插值；滚动用 `ScrollViewReader` 不宜，改用 `offset` 手动插值（iOS 15 的 `ScrollView` 动画会抖）。
- HDR 高光：`LinearGradient` + `blendMode(.plusLighter)` + 时间相位。
- 详情见骨架 `LyricsView.swift`（已实现逐词遮罩高亮，不含 HDR/字体管理）。

### 3.4 关卡四：在线曲库（唯一的硬阻塞）

事实：`app/libs/arm64-v8a/libkugou_server.so` 是 **Android-only 预编译 Rust 二进制**（`KugouNativeBridge` 通过 JNI 调 `startNode(port, dataDir)`，Kotlin 侧再 OkHttp 打 `127.0.0.1:<port>`）。仓库**不含 Rust 源码**，只有 `.so`。

三条路线：

| 路线 | 做法 | 工作量 | 风险 |
|---|---|---|---|
| **L1 交叉编译（最优）** | 从上游 `md3Music` 找 `kugou_api_server/rust` 源码，`cargo build --target aarch64-apple-ios`（static lib），再写 Swift/C 桥接 `start_server(port, data_dir)`，App 内置 server 起在本机端口 | 3–5 人日 + 调试 | 上游是否公开该 crate；iOS 后台对本地 server 的生命周期要跟 AVAudioSession 绑定 |
| **L2 Swift 重写协议** | 反读 `.so`/Kotlin 里的签名参数（`signature` 在 `KugouBlacklistApi.kt` 有 `signedPost` 参考；`KugouRepository` 里有 135 处 signature 相关），用 CryptoKit 重写 | 8–15 人日 | 风控参数（dfid/mid/guid/uuid、`errcode:20028` 验证）随时变；维护成本高 |
| **L3 中转服务器** | Rust server 跑在电脑/NAS，iOS 直接连 `http://192.168.x.x:port` | 半天 | 只能在同网段用；出门就废 |

**建议：M3 先 L3 验证链路，同时推进 L1；L2 只在 L1 彻底不可行时上。**
另外注意：`KugouApiService` 里三个常量对"能不能播"影响很大——`KUGOU_PLATFORM = "lite"`、`PREFERRED_PPAGE_ID = "356753938"`（收藏后无版权曲的解锁 page_id）、以及 dfid/mid 必须**持久化**（每进程重生成身份会被风控回 20028）。这三条 iOS 端必须原样保留。

### 3.5 关卡五：高级功能

| 功能 | iOS 方案 | 结论 |
|---|---|---|
| 实时人声分离 | TFLite C API 交叉编译，或 Core ML（MSS 含 STFT，coremltools 转换难度高） | **模型缺失**，需自备 `*.tflite`（MSS 系）才能开工 |
| 听歌识曲 | ShazamKit（免费、系统级）或 ACRCloud | ShazamKit 最省事 |
| 评论区 | 直接 SwiftUI 列表 + 分页 | 依赖在线层 |
| 检查更新 | AltStore / Sideloadly / 自签描述文件；iOS 不允许应用内下载 ipa 自装 | 只能给"有新版本，去 XX 下载" |
| 桌面小组件 | WidgetKit（small = 2×2，medium = 4×2，large = 4×4）；4×1 只能塞进 medium 的横向布局 | 可做，但要 App Group 共享当前曲目 |
| 状态栏歌词 | **无解**（非越狱）；替代：锁屏 Now Playing 副标题显示当前歌词行（iOS 15 可行） | 降级方案 |
| 车载蓝牙歌词 | 无 AVRCP 自定义元数据写入口（私有 API） | 只能靠 Now Playing 标题/副标题 |
| 平板横屏分栏 | `NavigationSplitView`（iOS 16）→ iOS 15 用 `HStack` 手写 | 可做 |

---

## 4. iOS 15 兼容红线（你的设备是 iPhone 12 + iOS 15，以下全部不能用）

| API | 最早版本 | iOS 15 替代 |
|---|---|---|
| `NavigationStack` | 16 | `NavigationView`（有已知样式 bug，需 `UINavigationBarAppearance` 压平） |
| `.glassEffect()` / Liquid Glass | 26 | 自定义玻璃层（§3.1） |
| `Live Activity` / 灵动岛 | 16.1 | 无（不做） |
| Lock Screen Widget | 16 | 无（只做桌面小组件） |
| `Charts` | 16 | 自绘 |
| `.scrollTargetBehavior` / `.scrollPosition` | 17 | 手动 offset + offset 回弹 |
| `ShareLink` | 16 | `UIActivityViewController` |
| `LabeledContent` / `.bold()` on Text 等 | 16 | 手写 HStack |
| `AsyncImage` 缓存（无磁盘缓存） | 15 可用但无缓存 | 自建缓存层 |
| `Refreshable` | 15 可用 | ✅ |
| `@FocusState` | 15 可用 | ✅ |
| Swift Concurrency | 13/15 可用 | ✅（`Task`、`async let` 都行） |
| `guard let self` 简写（Swift 5.8） | 工具链版本，非系统版本 | ✅ 但 Xcode 15+ 才支持 |
| 120Hz ProMotion | 需要 `CADisplayLink` 的 `preferredFrameRateRange`（iOS 15 可用） | ✅ 但 SwiftUI 动画默认 60，滚动想满帧要自绘或 UIKit |

**部署目标定 `iOS 15.0`**，所有 16+ API 用 `if #available` 包起来，保证在 iPhone 12 上能装。

---

## 5. 分期计划（M0–M5）

| 阶段 | 内容 | 验收标准 | 估工 |
|---|---|---|---|
| **M0 骨架**（已交付雏形） | 工程结构、玻璃组件、主题、PlayerEngine、本地库扫描、逐字歌词、播放页 | Xcode 打开可编译；能导入本地音频播放；歌词逐字高亮正确 | 3–4 人日 |
| **M1 本地体验闭环** | 队列管理、快进/上一首下一首、倍速、睡眠定时、后台+线控、播放恢复、排序/索引、文件夹导入 | 息屏播放 1 小时不掉；锁屏封面齐全；杀进程重启能恢复队列 | 4–6 人日 |
| **M2 视觉对齐** | 玻璃强度可调、封面取色、动态封面、Pear Wall Metal 背景、越界回弹、横屏分栏 | 与 Android 版同屏对比，玻璃质感/圆角/描边参数一致 | 6–8 人日 |
| **M3 在线曲库** | Rust server 交叉编译（或 L3 中转）、搜索/歌单/URL 惰性解析、音质策略、磁盘缓存、登录态 | 搜歌→播放→切音质→断网恢复全链路通过 | 8–12 人日（L1 顺利）/ 15+（L2） |
| **M4 歌词进阶** | 翻译/罗马音、自定义字体、HDR 高光、高潮起点、锁屏歌词行、歌词来源 fallback | KRC 逐字与 Android 版时间轴对齐（±30ms） | 4–5 人日 |
| **M5 其他** | 小组件、识曲、评论、设置页全量、主题取色器、关于/更新提示 | — | 8–10 人日 |

**合计约 33–45 人日（单人全职 ≈ 7–9 周）**，其中 M3 的不确定性最大。

---

## 6. 工程结构（骨架已按此落地）

```
SonifyIOS/
├─ project.yml                  # XcodeGen：一条命令生成 .xcodeproj
├─ README.md                    # 构建步骤 + 当前完成度
├─ Sources/
│  ├─ App/          SonifyApp.swift / RootView.swift
│  ├─ Design/       GlassStyle.swift / Theme.swift / GlassCard.swift
│  ├─ Playback/     PlayerEngine.swift / NowPlayingCenter.swift / Track.swift
│  ├─ Lyrics/       LyricEntry.swift / LyricParser.swift / LyricsView.swift
│  ├─ Library/      LibraryScanner.swift / LibraryStore.swift
│  ├─ Pages/        HomeView.swift / NowPlayingView.swift / LibraryView.swift
│  └─ Settings/     SettingsStore.swift
└─ Resources/       Info.plist（后台音频、文件共享）
```

**分层原则**（和 Android 的对应关系）：

- `PlayerEngine` = `MediaController`（唯一状态源，`@MainActor`）。
- `LibraryStore` = `data/libraries` + `FavoriteRepository`。
- `LyricParser` = `YosLrcFactory`（纯函数，可单测）。
- `GlassStyle` = Haze 参数表（一处调参，全 App 生效）。
- `SettingsStore` = `YosDataSaver` + 各 SettingOption。

---

## 7. 许可与分发（必须提前想清楚）

- Sonify 是 **GPL-3.0**。派生 iOS 版**必须同样以 GPL-3.0 开源**，且要保留原作者署名与 NOTICE（尤其 Pear Wall、NexioSchedule 的 Apache/AGPL 部分）。
- **App Store 与 GPL-3.0 存在冲突**（Apple 的分发条款加了额外限制），所以：**别指望上架**。你的 iPhone 12 走 **TrollStore（若 iOS 15 可持久化）或 AltStore/Sideloadly 自签（7 天重签）** 是现实路径。
- 酷狗接口：上游 README 已声明"仅供学习与技术交流"，别公开发布带在线音源的构建，否则容易被下架/发函。
- 图标/字体等资源若来自商业字体，移植时一并替换。

---

## 8. 本次已交付物 & 待办

**已交付（代码骨架，`SonifyIOS/`）**

1. 可在 Mac 上一条命令生成工程的 `project.yml`（XcodeGen）。
2. iOS 15 可用的**液态玻璃组件**（可调强度 + 双层描边 + 连续圆角）。
3. **PlayerEngine**：AVAudioSession / 后台播放 / 线控 / 锁屏信息 / 倍速 / 睡眠定时 / 播放恢复。
4. **LyricParser**：LRC + KRC + 纯文本合成时间轴 + 翻译最近匹配（对齐 Android 语义）。
5. **LyricsView**：逐词遮罩式卡拉 OK 高亮 + 相邻行缩放。
6. **LibraryScanner / LibraryStore**：本地文件扫描 + 元数据读取 + 播放队列。
7. 首页 / 播放页 / 资料库页 / 设置页最小可跑版本。

**明确未做（不要以为是 bug）**

- 在线曲库（需 Rust server 交叉编译，见 §3.4）。
- Pear Wall Metal 背景（shader 待迁，§3.1 已给路径）。
- 人声分离（模型缺失）。
- 小组件、识曲、评论、主题取色器、HDR 歌词。
- 代码**未在 Xcode 编译验证**（本环境是 Linux，无 Swift 工具链）；首次打开若有编译错误属于正常，按报错逐条修即可。

**下一步建议顺序**：M0 跑通 → 把你真实曲库导入测歌词对齐 → M1 后台/线控 → 再去啃 M3 的 Rust server。
