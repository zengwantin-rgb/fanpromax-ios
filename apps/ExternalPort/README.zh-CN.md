# FanProMAX iOS

面向 **iPhone 15 Pro Max / iOS 17.0 / TrollStore** 的独立原生 iOS 移植工程，仓库所有者为 `zengwantin-rgb`。本项目按用户提供的 FanProMAX Android APK 做功能核对；APK 的 DEX、ELF 和 Android 驱动不能直接编译或改后缀得到 iOS 程序。

当前 0.1.0 为外置显示基础版，复用本用户既有 iOS 工程的采样、悬浮显示及权限诊断代码，重新设置独立的应用身份和存储目录。它不是完整的 Android 功能移植，也未打通游戏控制权限。

- 已接入：原生控制界面、独立 HUD、人物方框/姓名/距离/血量条/射线、载具及空投显示、二维雷达、背敌箭头、队友过滤、样式和位置设置、诊断导出。骨架及地面物资仍标记实验性。
- 未移植：自瞄、子弹追踪、压枪、人物加速、飞车、无敌/减伤、除草、画质和账号切换。没有为这些项提供会假装成功的功能开关。
- 「功能」页列出已提供项与待移植项；它不代表 APK 所有功能已经在 iOS 生效。
- 现有 iOS 外置实现曾在设备读到游戏数据；最新权限对照中游戏控制端口返回 5。root 身份、巨魔安装、声明权限和自有子进程写入成功均不等于游戏可写。新 Bundle 的实际读取与悬浮层还需本机验证。

安装包为 `FanProMAX-iOS.ipa`，通过 TrollStore 安装。Bundle ID 为 `io.github.zengwantin.fanpromax`，与原 NSP 工具可并存，设置和后台停止通知隔离。安装后先在「总览」启动悬浮层，再开启游戏读取；游戏须为 NEW STATE **0.9.98（804）**。版本不匹配不强行采样。

发生问题时在「工具」导出状态；权限验证仅对本工具自建目标执行小范围写入/恢复，并申请、释放游戏控制端口，不修改游戏数据。新版本没有 APK 授权联网、Android 驱动、第三方密钥或游戏二进制。

所有编译、原生自动化测试、签名/IPA 校验与模拟器 UI 检查只在 **GitHub 托管 macOS** 执行。本地只编辑源码、Git 和读取文本/图片报告；模拟器通过不等于真机跨应用 HUD 或游戏权限已验证。

APK 功能清单和证据边界见 [analysis/apk-features.json](analysis/apk-features.json)。输入 SHA-256 为 `02d6e9e30f0f25865552c75ae66e625c0466b017114ba9e5051edb60655024d9`，包内标识 `com.fanpromax.launcher`、版本 3.3.0。没有运行或安装 APK，也未移植/破解其授权模块。

iOS 基础来源：用户原仓库 `zwthys-cyber/newstate-ios-port`，快照 `b73e6ef` 的 `apps/ExternalPort`、`PortCore` 和 `RemoteImage`。这是原外置只读基础，不包含游戏内 r13 自瞄模块。Lessica/TrollSpeed 的 MIT 许可保留在 [ThirdPartyNotices.txt](apps/ExternalPort/ThirdPartyNotices.txt)。新图标由本项目的原生矢量脚本生成，不提取 APK 图形资源。
