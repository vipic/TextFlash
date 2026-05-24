# TextFlash

TextFlash 是一款 macOS 菜单栏文本展开工具，基于 SwiftUI 和 SQLite 构建。

## 开发

运行测试：

```bash
swift test
```

本地构建：

```bash
swift build
```

部署开发版应用到 `~/Applications/TextFlash Dev.app`：

```bash
./deploy.sh
```

文本展开需要 macOS 辅助功能权限。如果无法触发展开，请通过菜单栏检查权限状态。

CI 会在 macOS 上运行 shell 脚本语法检查、`swift test` 和 `swift build -c release`。重要变更详见 `CHANGELOG.md`。

## 片段管理

片段以 SQLite 格式存储在 Application Support 目录下。管理窗口支持 JSON 导入导出。导入兼容 TextFlash 备份 JSON、原始分组数组或单个分组对象。导入前会校验备份数据，覆盖现有数据前自动生成备份。

自动导入备份路径：

```text
~/Library/Application Support/TextFlash/Backups
```

应用最多保留 20 份自动备份。

使用管理工具栏中的文件夹按钮可快速打开备份目录。

## 应用排除

通过菜单栏可以暂停展开、排除当前应用、管理排除列表。排除列表按 bundle identifier 存储在 `UserDefaults` 中。

## 发布

构建 DMG：

```bash
./release.sh 0.1.0
```

发布产物会写入 `dist/`，避免多个版本的 DMG 堆在项目根目录。

默认运行测试。跳过测试仅打包查看：

```bash
RUN_TESTS=false ./release.sh 0.1.0
```

发布需要 Developer ID 签名和公证：

```bash
CODESIGN_IDENTITY="Developer ID Application: Example" \
NOTARIZE=true \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
./release.sh 0.1.0 --publish
```

`--publish` 需要 Git 工作区干净，脚本会推送当前 `HEAD` 和发布 tag。
