# 贡献指南

Better Remote 是独立开源工具，与任何远程软件无产品主副、附属或官方合作关系。

默认不采集个人信息；仅在你主动提交意见反馈时才会上传，且上传内容不含隐私数据。

感谢你愿意一起改进 Better Remote。下面是协作方式。

## 怎么贡献

1. Fork 本仓库
2. 从 `main` 拉出你的改动分支
3. 本地改完后跑一遍测试：`swift test`
4. 向本仓库的 `main` 开 Pull Request，说明改了什么、为什么改

## 请注意

- 不要提交 `dist/`、`.build/`、`.swiftpm/`、`.DS_Store` 或任何密钥、证书、公证凭据
- 正式发版（签名、公证、上传 Release / appcast）由维护者完成，贡献者不用也不要提交安装包
- 讨论和 PR 里请友善协作；有分歧就事论事

## 开发环境

- macOS 14+
- Xcode / Swift 工具链（能跑 `swift build`、`swift test`）

本地构建可参考根目录 `README.md` 的构建说明，以及 `scripts/build.sh`（维护者发版脚本）。
