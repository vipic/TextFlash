# TextFlash

TextFlash 是一款 macOS 菜单栏文本展开工具，基于 SwiftUI 和 SQLite 构建。

## 开发

运行测试：

```bash
mise run test
```

本地构建：

```bash
mise run build
```

部署开发版应用到 `~/Applications/TextFlash Dev.app`：

```bash
mise run deploy
```

也可以查看所有项目任务：

```bash
mise tasks
```

完整 mise 命令速查见 [docs/MISE.md](docs/MISE.md)。常用入口：

```bash
mise run ci
mise run deploy
mise run release-auto
```

文本展开需要 macOS 辅助功能权限。如果无法触发展开，请通过设置检查权限状态。

菜单栏：**左键**打开片段管理，**右键**打开菜单（检查更新、设置、Unicode 输入等）。

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

在设置中可管理排除列表与 Unicode 输入应用。排除列表按 bundle identifier 存储在 `UserDefaults` 中。菜单栏右键可快速将当前应用加入 Unicode 输入列表。

## 命令行备份与恢复

安装后的 app 内置了备份和恢复脚本，方便外部自动化调用：

```bash
"/Applications/TextFlash.app/Contents/Resources/Tools/textflash-backup.sh"
"/Applications/TextFlash.app/Contents/Resources/Tools/textflash-restore.sh" --launch "$HOME/Backups/TextFlash/20260620-120000"
```

备份内容包含片段数据库和当前版本对应的偏好设置。登录项由 macOS 管理，恢复后需要在设置里重新确认。

## 发布

完整发布流程见 [RELEASE.md](RELEASE.md)。本地签名要求见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

构建 DMG：

```bash
mise run release -- 0.1.0
```

按 git message 自动计算下一个版本并构建 DMG：

```bash
mise run release-auto
```

发布产物会写入 `dist/`。默认使用稳定代码签名证书 `Nekutai`（可通过 `CODESIGN_IDENTITY` 覆盖）；不支持 ad-hoc 回退。

默认运行测试。跳过测试仅打包查看：

```bash
RUN_TESTS=false mise run release -- 0.1.0
```

发布到 GitHub Releases：

```bash
mise run release -- 0.1.0 --publish
```

`--publish` 需要在 `main` 分支、Git 工作区干净，脚本会推送 tag 并创建 GitHub Release。