# 拾贝 · ShiBei

Picseed 同功能的 iOS 内容收藏 App（**已去除笔记模块**）：把小红书、抖音、B 站、知乎、微博、小黑盒的图文与视频，连同**完整正文**收进本地，支持**实况图**、**本地播放器**和**自定义离线缓存**。

- 纯 SwiftUI + SwiftData，零第三方依赖
- 部署目标 iOS 18.0，iPhone 竖屏
- 离屏 `WKWebView` 处理纯前端渲染的平台（抖音）
- 不登录、不上传，数据只存在设备本地

---

## 功能对照

| 要求 | 实现 |
| --- | --- |
| 整体 UI 符合 iOS 设计规范 | 系统字体与控件、SF Symbols、原生 Tab / Sheet / Menu / Form、深色模式、动态字体 |
| 功能与 Picseed 一致，取消笔记 | 收藏流、平台筛选、标签、搜索、画廊模式、分享、缓存管理；无笔记入口 |
| 六平台图文/视频链接识别 | 独立 Resolver + 通用 OpenGraph 降级，见下表 |
| 图片 / 视频 / 文字整理 | `ParsedMedia` 统一模型，按原始顺序落库 |
| 实况图识别与展示 | 小红书 / 抖音 / 微博的 `livePhoto` 资源，本地用 `PHLivePhotoView` 按住播放 |
| 本地视频播放器 | AVKit `VideoPlayer` + 本地文件优先，支持画中画 |
| 文字完整加载 | 解析阶段取全文（非分享预览），卡片与详情均不截断 |
| 自定义缓存 | 逐条手动缓存或自动缓存，媒体全部落地，链接失效仍可浏览/播放 |
| 登录态（可选） | 设置里粘贴 B 站 / 微博 Cookie，解锁清晰度、绕过部分风控 |

---

## 六平台解析策略

| 平台 | 短链入口 | 数据来源 | 媒体 |
| --- | --- | --- | --- |
| 小红书 | `xhslink.com` → `explore/{id}` | `window.__INITIAL_STATE__` → `note.noteDetailMap[id].note` | `imageList[]`、`video.media.stream`、`imageList[i].video`（实况） |
| 抖音 | `v.douyin.com` → `iesdouyin.com/share/{video,note,slides}/{id}` | 分享页已改为纯前端渲染：优先 SSR，失败后由**离屏 WKWebView 截获页面自身的签名接口** | `video.play_addr`（去水印）、`images[]`、`images[i].video`（实况） |
| B 站 | `b23.tv` → `BV…` | `x/web-interface/view` + `x/player/playurl` | DASH 分离音视频（优先 H.264 轨，下载后 AVFoundation 合并）或 durl 单文件；专栏走 `__INITIAL_STATE__.readInfo` |
| 知乎 | 回答 / 专栏 / 想法 / zvideo | `js-initialData` → `initialState.entities` | 正文 `<img>` 原图字段、`zvideos.playlist` |
| 微博 | `weibo.com/{uid}/{bid}`、`m.weibo.cn/detail/{mid}` | `m.weibo.cn/statuses/show` | `pics[].large`、`page_info.media_info` 的 MP4、`pic_infos[].video`（实况） |
| 小黑盒 | 分享链接 `link_id` | 内嵌 JSON 深扫描 → OpenGraph | 任意 JSON 中的图片/视频直链 |

解析失败时自动降级到 **OpenGraph / JSON-LD / 页面图片** 通用解析，并把诊断信息写进条目的「解析日志」。

---

## 目录

```
ShiBei/
├─ project.yml                 # XcodeGen 工程定义（不提交 .xcodeproj）
├─ .github/workflows/build-ipa.yml
├─ INSTALL.md                  # Windows 装机手册
└─ ShiBei/
   ├─ App/                     # 入口、Tab、全局状态、Toast
   ├─ Design/                  # 设计令牌与通用组件
   ├─ Models/                  # Platform / Item / MediaAsset / ParsedContent
   ├─ Data/                    # 存储、下载器、合并、缓存、相册导出
   ├─ Network/                 # HTTP、内嵌 JSON 切分、HTML 工具
   ├─ Parsing/                 # 链接提取、路由、六个平台 Resolver
   ├─ Playback/                # 本地播放器、实况图视图
   ├─ Features/                # 收藏 / 详情 / 添加 / 缓存 / 设置 / 搜索
   ├─ Intents/                 # 快捷指令
   └─ Resources/               # Info.plist、Assets（AppIcon 已生成）
```

---

## 本地数据布局

```
Application Support/ShiBei/Library/<item-uuid>/
├─ item.json          # 元数据快照（数据库损坏时可人工恢复）
├─ images/            # 封面、静图、实况帧
└─ videos/            # 视频、实况视频、合并后的 MP4
```

数据库使用 SwiftData（`Item` ↔ `MediaAsset` 级联删除）。删除条目会连同文件夹一起删除；「清理缓存」只删文件、保留收藏记录。

---

## 构建

### 方式一：云端（Windows 可用，推荐）

推送到 GitHub 后，Actions 自动跑 `xcodegen` + `xcodebuild archive`，产出**未签名** `ShiBei.ipa`。详见 [INSTALL.md](INSTALL.md)。

### 方式二：本地 Mac

```bash
brew install xcodegen
cd ShiBei
xcodegen generate
open ShiBei.xcodeproj
```

Xcode 里选你的开发者账号即可真机运行。

> 部署目标固定 18.0：这样无论 CI 上是 Xcode 16 还是 26 都能编译。若用 Xcode 26 / iOS 26 SDK 编译，系统控件会自动获得 Liquid Glass 外观。

---

## 已知限制（请先读）

1. **抖音需要网页渲染**：2026 年起抖音分享页不再在 HTML 里输出 `item_list`，静态抓取已不可行。App 会启动一个离屏 `WKWebView` 运行分享页，注入脚本截获页面自己发出的签名接口响应。代价是首次解析多等 3–8 秒，且如果页面要求登录或弹验证码会失败。
2. **小红书自动救援**：被 `/404/sec` 安全页拦截时，App 会改用离屏浏览器重新加载，读取 JS 执行后的 `__INITIAL_STATE__` 再解析一次；仍失败才提示错误。
2. **平台风控**：小红书、微博、小黑盒依赖公开页面数据，平台改版或加强风控时会失效，需要更新对应 Resolver；App 会自动降级到 OpenGraph，并把原始错误写进解析日志（详情页右上角 → 查看解析日志）。
3. **知乎 40362**：知乎对部分网络（尤其是机房 IP）直接返回风控页。手机蜂窝网络通常正常；遇到时换网络重试。
4. **高清视频需要登录态**：B 站未登录通常只能拿到 480P/720P。设置 → 下载 → 登录态 Cookie，粘贴浏览器的 `SESSDATA` 即可解锁 1080P；微博遇到 432 也可用同样方式补 Cookie。Cookie 只存本机。
5. **小黑盒最不稳定**：其接口带签名（hkey），公开页字段也常变，当前以深扫描 + OG 兜底，可能只能拿到封面图与摘要。
6. **实况图**：App 内可完整播放（JPEG + MOV 配对）。导出到系统相册时依赖 `PHAssetCreationRequest` 的 pairedVideo 资源；个别系统版本可能导入为「图片 + 视频」，这是相册侧的识别问题。
7. **B 站合并**：DASH 音轨是分片 MP4（m4s），极少数编码（如 FLAC 音轨）合并失败时会保留无声视频，日志里会记录原因。
8. **缓存期间请保持前台**：下载使用前台 URLSession，锁屏或切到后台后可能被系统挂起，回到 App 会自动继续未完成的任务。
9. **免费签名 7 天**：见 INSTALL.md 的重签说明。

---

## 范围说明

为了让「免费 Apple ID 也能装」成立，以下能力没有纳入：

- **iCloud 同步**：需要 iCloud 容器 entitlement，免费签名无法申请。
- **桌面小组件**：需要 App Group 在主 App 与扩展之间共享数据，会显著增加侧载失败率。

笔记模块按要求整体移除；收藏、平台分类、标签、搜索、画廊、离线缓存、分享均已包含。

---

## 免责声明

本工具仅用于保存你有权访问的公开内容，供个人离线阅读。请遵守各平台服务条款，不要用于二次分发、去水印商用或其他侵权用途。
