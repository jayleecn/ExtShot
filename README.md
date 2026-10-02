# ExtShot

ExtShot 是一个 macOS 菜单栏应用程序，用于快速截取指定尺寸的屏幕截图。

**当前版本：** 0.1.0

## 功能特点

- 支持两种预设尺寸：
  - 大尺寸：1280 x 800 像素
  - 小尺寸：640 x 400 像素
- 支持快捷键操作：
  - Option + Shift + 1：截取大尺寸截图
  - Option + Shift + 2：截取小尺寸截图
- 菜单栏快速访问
- 截图自动保存到下载文件夹
- 截图完成后在访达中选中保存的文件

## 使用方法

1. 点击菜单栏中的相机图标打开菜单
2. 选择需要的截图尺寸
3. 或使用快捷键打开截图选框：
   - Option + Shift + 1：1280 x 800
   - Option + Shift + 2：640 x 400
4. 拖动选框定位，双击确认截图；按 ESC 退出。

## 系统要求

- macOS **14.6** 或更高版本（与 Info.plist 和 Xcode 项目中的部署目标一致）

## 构建说明

1. 使用 Xcode 打开 `ExtShot.xcodeproj`，选择 `ExtShot` scheme；在本机配置签名后运行
2. 选择 "Product > Build" 构建项目
3. 构建完成后，可以在 "Products" 文件夹中找到应用程序

## 安装

将应用拖到应用程序文件夹即可。首次运行时，需要授予屏幕录制权限。

## 更新日志

### 0.1.0 (2024-12-15)
- 初始版本发布
- 支持两种预设尺寸的截图
- 支持快捷键操作
- 菜单栏快速访问
- 截图自动保存到下载文件夹

## 开发导航

| 要改的功能 | 入口 |
| --- | --- |
| App 入口、菜单栏、快捷键、截图通知接收与 PNG 保存 | [ExtShot/ExtShot.swift](ExtShot/ExtShot.swift) |
| 选框、拖动、双击确认、ESC 与屏幕坐标转换 | [ExtShot/ScreenshotWindow.swift](ExtShot/ScreenshotWindow.swift) |
| 当前菜单/快捷键链路使用的屏幕捕获 | [ExtShot/SCRCapture.swift](ExtShot/SCRCapture.swift) |
| 下载目录与文件名生成 | [ExtShot/ScreenshotManager.swift](ExtShot/ScreenshotManager.swift) 的 `generateScreenshotPath()` |
| Carbon 热键回调 | [ExtShot/HotKeyCallbacks.swift](ExtShot/HotKeyCallbacks.swift) |
| 最低系统版本、权限说明、签名/构建配置 | [ExtShot/Info.plist](ExtShot/Info.plist)、[ExtShot/ExtShot.entitlements](ExtShot/ExtShot.entitlements)、[ExtShot.xcodeproj/project.pbxproj](ExtShot.xcodeproj/project.pbxproj) |

当前链路：`ExtShotApp` → `AppDelegateObject` → `ScreenshotPanel` → `.takeScreenshot` 通知 → `SCRCapture.capture()` → PNG 写入下载目录。`ScreenshotManager` 还保留其他捕获方法；`PopoverView.swift` 没有被当前 App 入口实例化，`ScreenCapturePermissionManager.swift` 也没有当前调用点，定位菜单栏截图时先看上述链路。

仅检查编译可运行：

```bash
xcodebuild -project ExtShot.xcodeproj -scheme ExtShot -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

交互复核仍需运行 App 并授予屏幕录制权限：分别触发两种尺寸，拖动/双击/ESC，确认下载目录生成 PNG 且取消后可以再次截图。仓库没有自动化测试 target。
