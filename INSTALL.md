# 在 Windows 上把「拾贝」装进 iPhone 17

全程不需要 Mac。整条链路：

```
你的 Windows ──push──> GitHub ──Actions(macOS)──> 未签名 .ipa
                                                        │
iPhone 17 <──USB── Sideloadly（用你的 Apple ID 签名）<──┘
```

预计第一次操作 **40–60 分钟**，其中等待云编译约 5 分钟。

> 前置条件：iPhone 17（iOS 27.0.1）、一台 Windows 10/11、数据线、你的 Apple ID 密码（建议先开双重认证）。

---

## 第 0 步：先确认能接受的两个限制

| 限制 | 说明 |
| --- | --- |
| 7 天有效期 | 免费 Apple ID 签名的 App 每 7 天过期，过期后打不开，重签一次即可（约 1 分钟，不用重新编译） |
| 最多 3 个 | 同一台设备同时最多装 3 个自签名 App |

不想每 7 天重签 → 加入 Apple Developer Program（$99/年），签名有效期 1 年，还能用 TestFlight。**先按免费方案走通，再决定要不要付费。**

---

## 第 1 步：安装依赖（Windows）

### 1.1 iTunes（必须有）

Sideloadly 依赖 Apple 的驱动与 `AppleMobileDeviceSupport`。

- 打开 <https://www.apple.com/itunes/download/win64> 下载 **Windows 版 iTunes** 安装。
- ⚠️ 不要用 Microsoft Store 里的版本，Sideloadly 识别不到设备。
- 装完打开 iTunes，用数据线连上 iPhone，点「信任此电脑」，确认 iTunes 能看到设备。

### 1.2 GitHub Desktop（里面自带 git）

- 下载：<https://desktop.github.com>
- 安装后用 GitHub 账号登录（没有就注册一个，免费）。

### 1.3 Sideloadly

- 下载：<https://sideloadly.io>
- 安装后先别打开。

---

## 第 2 步：把代码推到 GitHub

1. 打开 GitHub Desktop → **File → Add local repository…**
2. 选择文件夹：`D:\Software\deepseek harness\ShiBei`
   （这是工程根目录，里面能看到 `project.yml`、`ShiBei/`、`.github/`）
3. 如果提示 "not a git repository"，点 **create a repository**，Name 填 `shibei`，点 Create。
4. 左下角填一句提交信息（如 `init`），点 **Commit to main**。
5. 点顶部 **Publish repository**。
   - 公开或私有都可以，Actions 都能跑。只想自己用就选 **Keep this code private**。
   - 点 Publish。

---

## 第 3 步：等云端编译出 IPA

1. 打开 `https://github.com/<你的用户名>/shibei` → 顶部 **Actions** 标签。
2. 应该能看到 `Build IPA` 正在跑（黄点）。第一次约 5–8 分钟。
3. 变成绿勾后，点进这次运行 → 页面底部 **Artifacts** → 下载 `ShiBei-ipa`。
4. 解压得到 `ShiBei.ipa`。

> 如果 Actions 显示红叉：点进去看 `Archive (unsigned)` 那一步的日志，把报错发我，我改代码后你再 Commit 一次即可。
>
> 免费额度：公开仓库不限分钟数；私有仓库每月 2000 分钟，macOS 按 10 倍计费，一次构建约消耗 50–80 分钟额度。

---

## 第 4 步：用 Sideloadly 签名安装

1. iPhone 用数据线连电脑，解锁并点「信任」。
2. 打开 Sideloadly：
   - **iOS Device** 选你的 iPhone 17
   - 把 `ShiBei.ipa` 拖进 **IPA** 框（或点文件夹图标选择）
   - **Apple ID** 填你的 Apple ID 邮箱
3. 点 **Start**。
4. 弹出密码框 → 输入 Apple ID 密码。
   - 开了双重认证的话，**不要**用登录密码，去 <https://appleid.apple.com> → 登录与安全 → App 专用密码 → 生成一个，填这个。
5. 等待进度条走完，日志出现 `Done.` 即安装成功。

### 如果提示 "Developer Mode"

iOS 16 以后自签 App 需要开发者模式：

1. iPhone：**设置 → 隐私与安全性 → 开发者模式** → 打开
2. 重启手机，解锁后确认「打开」

### 如果提示「不受信任的开发者」

iPhone：**设置 → 通用 → VPN 与设备管理 → 开发者 App → 你的 Apple ID → 信任**

---

## 第 5 步：第一次打开

1. 桌面出现「拾贝」图标。
2. 打开后允许**相册写入**权限（保存图片/视频/实况图要用）。
3. 复制一条小红书或抖音的分享链接 → 回到 App 点右上角 **+** → 粘贴 → **解析内容** → **保存并缓存**。
4. 断网试一下：缓存过的条目仍能看图文、播视频、按住看实况。

---

## 第 5.5 步：验收清单（首次运行建议逐项打勾）

| 检查项 | 预期 |
| --- | --- |
| 小红书 · 图文 | 图片数量正确、正文完整、带「实况」角标的图按住能动 |
| 抖音 · 视频 | 能看到封面与时长，缓存后能播放 |
| B 站 · 视频 | 缓存后**有声音**（说明 DASH 音轨合并成功） |
| 知乎 · 回答 | 正文段落完整，结尾没有被截断 |
| 微博 · 图文 | 九宫格顺序与原文一致 |
| 小黑盒 | 至少能拿到封面图与摘要 |
| 离线 | 开飞行模式，已缓存条目仍可浏览、播放视频、按住看实况 |
| 存相册 | 图片 / 视频 / 实况能出现在系统相册 |

任何一项失败：进入该条目详情 → 右上角 ⋯ →「查看解析日志」（会复制到剪贴板）→ 把日志发我，我按平台修解析器。

---

## 第 6 步：7 天后重签

过期表现：点图标闪退，或提示「App 不可用」。

重签**不需要重新编译**，用同一个 IPA 再走一遍第 4 步即可：

1. Sideloadly 重新拖入 `ShiBei.ipa`（本地留一份）
2. 同样的 Apple ID → Start
3. 覆盖安装，收藏和缓存数据都会保留（数据在 App 沙盒内，重签不抹除）

建议：把 `ShiBei.ipa` 放在固定文件夹，顺手在日历里设个 6 天后的提醒。

---

## 常见问题

| 现象 | 处理 |
| --- | --- |
| Sideloadly 看不到设备 | 换原装线 / 换 USB 口；确认装的是官网 iTunes；重启 Apple Mobile Device Service |
| `Provision.cpp:266` 或 `Failed to sign` | Apple ID 或密码错误；改用 App 专用密码；确认账号未开启「双重认证限制」 |
| 安装后闪退 | 先在设置里信任开发者证书；仍闪退则把 Sideloadly 日志发我 |
| `Maximum number of apps` | 免费账号上限 3 个，先删掉其他自签 App |
| 解析失败 | 详情页右上角 ⋯ →「查看解析日志」，把日志发我，我针对该平台修解析器 |
| B 站只有 480P | 未登录的客观限制，需要后续加 Cookie 入口 |

---

## 备选方案（不想折腾 GitHub）

1. **租云 Mac**（MacinCloud / MacStadium，约 ¥2–5/小时）：远程 Xcode 直接编译，但真机安装仍需 IPA 回到本地侧载，步骤并不会更少。
2. **付费开发者账号**（$99/年）：Sideloadly 同样能用，只是证书 1 年有效，免去 7 天重签。
3. **TestFlight 分发**：需要付费账号 + App Store Connect 配置，适合以后想给朋友用。
