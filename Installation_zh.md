# VinylVault 安装指南

本指南将帮助您使用 MacBook 在 iPhone 12 上安装 VinylVault。该应用未在 App Store 上架，因此我们将使用 Xcode 直接从源代码安装。

## 📋 前提条件

开始之前，请确保您拥有：

### 硬件要求：
- **MacBook**（任何可以运行 macOS Sonoma 或更高版本的型号）
- **iPhone 12**（需 iOS 17.0 或更高版本）
- **USB-C 转 Lightning 数据线**（用于连接 iPhone 和 MacBook）

### 软件要求：
- **macOS Sonoma (14.0) 或更高版本** - [检查您的 macOS 版本](https://support.apple.com/zh-cn/HT201260)
- **Xcode 15.0 或更高版本** - [从 Mac App Store 下载](https://apps.apple.com/cn/app/xcode/id497799835)
- **Apple 开发者账户**（免费） - 我们将在指南中创建
- **Git**（随 Xcode 一起安装）

## 🚀 分步安装指南

### 步骤 1：检查您的 macOS 版本

1. 点击屏幕左上角的 **Apple 菜单**（🍎）
2. 选择 **关于本机**
3. 查看 **macOS 版本** 号
4. **如果是 Sonoma (14.0) 或更高版本**，您可以继续！
5. **如果是旧版本**，您需要更新：
   - 前往 **系统设置** → **通用** → **软件更新**
   - 安装所有可用更新

### 步骤 2：安装 Xcode

1. 在 MacBook 上打开 **App Store**
2. 在搜索栏中搜索 **"Xcode"**
3. 点击 **获取** 按钮（免费）
4. 等待下载和安装（可能需要 30-60 分钟）
5. 安装完成后，从应用程序文件夹打开 Xcode
6. 首次启动时，同意许可协议
7. 让 Xcode 安装其他组件（可能需要几分钟）

### 步骤 3：创建免费的 Apple 开发者账户

您需要此账户才能在 iPhone 上安装应用：

1. 打开 **Xcode**
2. 前往 **Xcode** 菜单 → **设置**（或 **偏好设置**）
3. 点击 **账户** 标签页
4. 点击左下角的 **+** 按钮
5. 选择 **Apple ID** 并点击 **继续**
6. 使用您的 **Apple ID** 登录（与 iCloud 使用的相同）
7. 如果提示，同意 Apple 开发者协议
8. 等待 Xcode 设置您的账户

### 步骤 4：下载 VinylVault 源代码

1. 在 MacBook 上打开 **Safari**
2. 访问：`https://github.com/brovlofski/SecondSpin`
3. 点击绿色的 **Code** 按钮
4. 点击 **Download ZIP**
5. 文件将下载到您的 **下载** 文件夹
6. 双击下载的 ZIP 文件进行解压
7. 您现在应该有一个名为 `SecondSpin-main` 的文件夹

### 步骤 5：准备您的 iPhone

1. **解锁** 您的 iPhone 12
2. 使用 USB-C 转 Lightning 数据线将 iPhone 连接到 MacBook
3. 在 iPhone 上，如果看到 **"信任此电脑？"**，点击 **信任**
4. 如果需要，输入 iPhone 密码
5. 在 Mac 上，您应该会在 Finder 中看到您的 iPhone

### 步骤 6：在 Xcode 中打开项目

1. 在 MacBook 上打开 **Xcode**
2. 前往 **文件** → **打开...**
3. 导航到您的 **下载** 文件夹 → **SecondSpin-main** 文件夹
4. 选择 **SecondSpin.xcodeproj**（蓝色图标）
5. 点击 **打开**

### 步骤 7：为您的 iPhone 配置项目

1. 在 Xcode 中，查看顶部工具栏
2. 找到设备选择器（可能显示 "iPhone 17" 或类似内容）
3. 点击它并选择 **您的 iPhone 名称**（应该出现在列表中）
4. 如果看不到您的 iPhone：
   - 确保它已连接并解锁
   - 尝试断开并重新连接数据线
   - 如果需要，重启 Xcode

### 步骤 8：设置签名（最重要的一步！）

这告诉 Apple 您被允许安装此应用：

1. 在 Xcode 中，在左侧边栏点击 **SecondSpin**（顶部项目）
2. 在主区域中，点击 **TARGETS** 下的 **VinylVault**
3. 点击 **Signing & Capabilities** 标签页
4. 在 **Signing** 下，勾选 **"Automatically manage signing"**
5. 从下拉菜单中选择您的 **Personal Team**
6. 您可能会看到警告 - 这是正常的
7. Xcode 将自动为您创建证书

### 步骤 9：构建并运行应用

1. 点击 Xcode 左上角的 **播放按钮**（▶）
2. **仅第一次**：您会看到关于 "No matching provisioning profiles" 的错误
3. 别担心！只需再次点击 **播放按钮**（▶）
4. 在您的 iPhone 上，您可能会看到：**"未受信任的开发者"**
5. 在您的 iPhone 上，前往：**设置** → **通用** → **VPN 与设备管理**
6. 在 **开发者 App** 下，点击您的 **Apple ID 邮箱**
7. 点击 **信任"[您的邮箱]"**
8. 再次点击 **信任** 进行确认
9. 返回 Xcode 并再次点击 **播放按钮**（▶）

### 步骤 10：等待安装

1. Xcode 现在将：
   - 构建应用（编译代码）
   - 安装到您的 iPhone
   - 自动启动
2. 第一次可能需要 2-5 分钟
3. 您将在 Xcode 的顶部栏看到进度
4. 在您的 iPhone 上，将出现 VinylVault 应用图标
5. 安装完成后，应用将自动打开

## 🎉 恭喜！

您已成功安装 VinylVault！应用现在应该在您的 iPhone 上运行。

## 🔧 常见问题故障排除

### 问题 1："No matching provisioning profiles found"
- **解决方案**：确保您在步骤 8 中选择了 **Personal Team**
- 也可以尝试：Xcode → Product → Clean Build Folder，然后重试

### 问题 2：iPhone 未出现在 Xcode 设备列表中
- **检查**：您的 iPhone 是否已解锁？
- **检查**：您是否在 iPhone 上点击了 "信任"？
- **尝试**：断开并重新连接 USB 数据线
- **尝试**：重启您的 iPhone 和 MacBook

### 问题 3："Failed to register bundle identifier"
- **解决方案**：在 Xcode 中，前往 Signing & Capabilities
- 将 **Bundle Identifier** 更改为唯一的内容
- 示例：`com.您的名字.VinylVault`（将 "您的名字" 替换为您的名字）

### 问题 4：应用打开后立即崩溃
- **解决方案**：在您的 iPhone 上，前往 设置 → 隐私与安全性
- 向下滚动并确保 **开发者模式** 已启用
- 如果看不到开发者模式，您需要启用它：
  1. 将 iPhone 连接到 Mac
  2. 打开 Xcode
  3. 前往 Window → Devices and Simulators
  4. 选择您的 iPhone
  5. 勾选 "Show as run destination"
  6. 重启您的 iPhone

### 问题 5："Could not launch application"
- **解决方案**：在您的 iPhone 上，如果应用存在则删除它
- 在 Xcode 中：Product → Clean Build Folder
- 从步骤 9 重新尝试构建

## 📱 使用应用

### 首次设置：
1. 应用将请求 **相机访问权限** - 点击 **允许**
   - 这是扫描条形码所必需的
2. 应用需要 **互联网访问** - 确保您已连接到 Wi-Fi 或蜂窝网络

### 基本功能：
- **首页标签**：每天显示您收藏中的随机专辑
- **收藏标签**：查看所有黑胶唱片
- **搜索标签**：搜索您的收藏
- **列表标签**：创建自定义列表（收藏夹、愿望清单等）
- **+ 按钮**：添加新唱片（扫描条形码或手动搜索）

### 添加您的第一张唱片：
1. 点击 **+** 按钮（浮动蓝色按钮）
2. 选择 **"扫描条形码"**
3. 将相机对准黑胶唱片的条形码
4. 或选择 **"手动搜索"** 并输入艺术家和专辑名称

## 🔄 更新应用

当添加新功能时，您可以更新应用：

1. 再次从 GitHub 下载最新的 ZIP
2. 用新文件夹替换旧文件夹
3. 在 Xcode 中打开项目
4. 构建并运行（▶）- 它将自动更新

## 📞 获取帮助

如果您遇到困难，可以：

1. **截图** 任何错误消息
2. **再次查看本指南** 中的具体步骤
3. **向分享此应用的人寻求帮助**

## ⚠️ 重要注意事项

- **7 天限制**：以此方式安装的应用在 7 天后过期
- **续期**：只需在过期前再次从 Xcode 构建并运行（▶）
- **数据安全**：您的收藏数据仅存储在您的 iPhone 上
- **不在 App Store**：这是开发版本，不是 App Store 版本
- **免费账户限制**：您一次只能以这种方式安装 3 个应用

## 🎯 快速参考

| 步骤 | 操作内容 | 操作位置 |
|------|------------|----------------|
| 1 | 检查 macOS 版本 | Apple 菜单 → 关于本机 |
| 2 | 安装 Xcode | Mac App Store |
| 3 | 创建 Apple 开发者账户 | Xcode → 设置 → 账户 |
| 4 | 下载源代码 | GitHub → Download ZIP |
| 5 | 连接 iPhone | USB 数据线，点击"信任" |
| 6 | 打开项目 | Xcode → 文件 → 打开 |
| 7 | 选择设备 | Xcode 顶部栏 → 您的 iPhone |
| 8 | 设置签名 | Xcode → Signing & Capabilities |
| 9 | 构建并运行 | 点击播放按钮（▶） |
| 10 | 在 iPhone 上信任 | 设置 → 通用 → VPN 与设备管理 |

## 💡 成功提示

1. **保持耐心** - 第一次构建时间最长
2. **按顺序执行步骤** - 不要跳过
3. **阅读错误消息** - 它们通常告诉您问题所在
4. **如果卡住就重启** - 有时重启 Xcode 或您的设备有帮助
5. **保持 iPhone 连接** - 在整个安装过程中

---

**享受使用 VinylVault 管理您的黑胶唱片收藏吧！** 🎵

如果一切顺利，您应该在 iPhone 主屏幕上看到一个黑胶唱片图标的应用。点击它开始添加您的收藏！

*最后更新：2026年3月*