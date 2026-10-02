# 仓库导航

macOS Swift 菜单栏应用，Xcode 项目 `ExtShot.xcodeproj`、scheme `ExtShot`，部署目标 macOS 14.6。

- App/菜单/快捷键/通知接收/保存：`ExtShot/ExtShot.swift`。
- 选框与坐标转换：`ExtShot/ScreenshotWindow.swift`。
- 当前捕获实现：`ExtShot/SCRCapture.swift`；保存路径：`ScreenshotManager.generateScreenshotPath()`。
- 热键回调：`ExtShot/HotKeyCallbacks.swift`。
- 版本/权限：`ExtShot/Info.plist`、`ExtShot/ExtShot.entitlements`；构建：`ExtShot.xcodeproj/project.pbxproj`。
- [README.md](README.md) 包含命令行编译和交互复核步骤。

菜单/热键 → `ScreenshotPanel` → `.takeScreenshot` → `SCRCapture` 是当前运行链路。`PopoverView` 没有被 App 入口实例化，`ScreenshotManager` 的其他捕获方法不能代表这条链路。没有自动化测试 target，真实截图需要本机权限和交互验证。
