<div align="center">

# Better Remote

### 让手机上的电脑，刚好装满你的屏幕

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat)](LICENSE)
&nbsp;
[![免费使用](https://img.shields.io/badge/%E8%B5%84%E8%B4%B9-%E5%85%8D%E8%B4%B9-brightgreen?style=flat)](#)
&nbsp;
[![系统要求](https://img.shields.io/badge/%E7%B3%BB%E7%BB%9F-macOS%2014%2B-0969da?style=flat)](#)

</div>

<br>

Better Remote 是独立开源工具，与任何远程软件无产品主副、附属或官方合作关系。

默认不采集个人信息；仅在你主动提交意见反馈时才会上传，且上传内容不含隐私数据。

本仓库同时提供源码与安装包发布（[Releases](https://github.com/pincc-debug/better-remote/releases)）。许可证为 [MIT](LICENSE)，贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。官网：https://betterremote.pincc.dev

---

用手机远程控制电脑，本该很方便。  
可真连上了才发现：

- **屏幕太小**：一整块电脑桌面被硬塞进手机里，缩成邮票大小
- **字看不清**：菜单、按钮、文字全都挤成一团，只能不停双指放大
- **点不准**：想点个按钮，手指一按就点歪
- **黑边一大片**：横屏还凑合，竖屏几乎没法用

问题不在你的手机，也不在远程软件，而是**两块屏幕的形状根本不一样**。

> **Better Remote 只做一件事：让电脑主动迁就手机。**

---

## ⚡ 连上的那一刻，一切就绪

手机一连上，电脑自动换成和手机一样的屏幕比例。横着拿、竖着拿、平板、折叠屏，画面都刚好铺满，字是正常大小，不用缩放。

断开时，电脑悄悄恢复原样。你坐回桌前，什么都不用调。

---

## 🖐️ 拇指够得着的工具条

屏幕边上多了一条工具条，按钮大小专门为手指设计。

- **窗口，一点就排好。** 选一个布局，依次点想放的窗口，铺满、对半、三栏、田字格，小屏幕上也一目了然。
- **快捷键，变成按钮。** 复制、粘贴、搜索、切换桌面……不用再在手机键盘上找组合键。
- **换个应用，换套按钮。** 在终端里是分屏，在别的应用里是它最常用的操作。按钮你自己定，图标你自己挑。

---

## 🍃 像用手机一样自然

手指一滑就是滚动。你只管用，剩下的交给它。

UU 自带的滚动条太快？在「设置 → 触控」直接调整 **滚动速度**，支持 1%–100% 和快捷档位，点击「原速」即可恢复。默认保持原速，无需额外开启开关；仅调整 UU 原生滚动，不改变本机鼠标、触控板或单指转换产生的滚动。

独立版「UU 轻滑」运行时，整合功能自动避让，退出独立版后再由 Better Remote 调速。算法改编自 MIT 开源项目 [UU 轻滑](https://github.com/Dameon020/uu-lightslide)，许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## 🎬 快速讲解

https://github.com/user-attachments/assets/7c1b78d7-e8d3-4902-a371-f555cc6897a5

## 💬 加入交流群

扫码加入体验反馈群。群二维码 7 天有效，如果已过期，请扫码加开发者微信，我拉你进群：

<div align="center">
<table>
<tr>
<td align="center" width="260" valign="top">
  <br>
  <img src="images/group-qr.png" alt="体验反馈群二维码" width="200">
  <p><strong>体验反馈群</strong></p>
</td>
<td align="center" width="260" valign="top">
  <br>
  <img src="images/wechat-qr.jpg" alt="开发者微信二维码" width="200">
  <p><strong>开发者微信</strong></p>
</td>
</tr>
</table>
</div>

---

## 📥 下载与安装

<div align="center">

<a href="https://github.com/pincc-debug/better-remote/releases/latest/download/Better-Remote.dmg">
  <img src="https://img.shields.io/badge/⬇%EF%B8%8F%20下载最新版-Better%20Remote.dmg-2ea44f?style=for-the-badge" alt="下载最新版 Better Remote" height="42">
</a>

<br><br>

**[下载最新版 Better Remote](https://github.com/pincc-debug/better-remote/releases/latest/download/Better-Remote.dmg)** · 免费 · macOS 14 及以上

官网：https://betterremote.pincc.dev

</div>

<br>

打开安装包，拖进「应用程序」，按提示开启「辅助功能」权限就能用。

> [!NOTE]
> 用 0.8.89 及更早版本的朋友，需要手动下载一次，之后都会自动更新。

---

## 🛠️ 从源码构建

需要 macOS 14+ 与 Swift / Xcode 工具链。

```bash
git clone https://github.com/pincc-debug/better-remote.git
cd better-remote
swift build
swift test
```

日常开发用 `swift build` / `swift test` 即可。签名、公证、打 dmg、更新 appcast 由维护者通过 `scripts/` 完成，贡献者请勿提交 `dist/` 或密钥。

---

## 🚀 使用方法

Better Remote 本身不是远程软件，它是在你远程的时候，让电脑这一端更好用。

1. **安装**：打开 `Better-Remote.dmg`，把 Better Remote 拖进「应用程序」，然后打开它。
2. **开权限**：按提示到「系统设置 › 隐私与安全性 › 辅助功能」，把 Better Remote 打开。
3. **设置常用设备**：在 Better Remote 里添加你常用的手机或平板，存好它们的分辨率和你习惯的设置。
4. **设置连接自动化**：打开后，手机一连上，电脑就自动切到对应的设置。
5. **用平时的远程软件连上电脑**：画面会刚好铺满手机屏幕。屏幕边上的工具条里有窗口布局、快捷按钮和分辨率。
6. **断开**：断开后电脑自动恢复原样，也可以在分辨率面板里点「还原本机」。

---

## ❓ 常见问题

**会把我电脑的分辨率改乱吗？**  
不会。断开就自动还原，也随时可以一键「还原本机」。

**能配合哪些远程软件？**  
常用的远程控制软件都可以，Better Remote 只负责让电脑这一端更好用。与任何远程软件无官方合作或主副产品关系。

**为什么要辅助功能权限？**  
排列窗口、快捷按钮都需要它，第一次使用时系统会提示你开启。

---

## 📝 最近更新（精简）

### 0.8.164

- 虚拟屏启动更稳，减少初始分辨率对不上

### 0.8.163

- 触控设置可调节 UU 滚动速度（<a href="https://github.com/Dameon020">@Dameon020</a> Rixin）

### 0.8.162

- 关于页可检查更新、看帮助、反馈问题
- 用 UU 远程时不再误弹退出确认

### 0.8.160

- 新增快捷操作「清理桌面」，点一下最小化所有窗口

完整安装包与说明见 [Releases](https://github.com/pincc-debug/better-remote/releases)。

---

## 🤝 贡献

欢迎开 Issue / PR。流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

<div align="center">

<sub>如果它帮到了你，可以请我喝杯咖啡</sub>

<img src="images/reward-qr.png" alt="赞赏码" width="160">

</div>
