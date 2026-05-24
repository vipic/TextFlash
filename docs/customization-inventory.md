# 定制化逻辑清单

这份清单记录当前项目里按应用、场景或个人路径写死的逻辑。后续如果要提升可扩展性，可以优先把这些规则改成配置、策略表或用户设置。

## 按应用定制

| 位置 | 当前做法 | 问题 | 后续方向 |
| --- | --- | --- | --- |
| `Sources/TextFlash/EventController.swift` | `shouldPreferUnicodeInsertionForFocusedApplication()` 对 Codex、iTerm、Terminal、Electron 相关 Bundle ID 或应用名直接走 Unicode 注入 | 新增不兼容应用需要改代码发布；基于 `contains` 的匹配容易误伤 | 改为可配置的应用兼容性规则，例如按 Bundle ID 精确匹配并支持用户覆盖 |
| `Sources/TextFlash/EventController.swift` | 通过 `lastNonTextFlashApplication` 避免把 TextFlash 自己当作排除目标 | 这是菜单栏应用常见场景，但仍是 TextFlash 自身行为的特殊处理 | 保留为通用的“忽略自身 bundle 前缀”机制，并集中到应用上下文层 |

## 按场景定制

| 位置 | 当前做法 | 问题 | 后续方向 |
| --- | --- | --- | --- |
| `Sources/TextFlash/EventController.swift` | 退格后按 `deletionSettleDelayPerCharacter` 等待，注释中提到 Telegram 类应用延迟处理退格 | 通过全局延迟覆盖所有应用，慢应用和快应用无法分别调优 | 改为插入策略参数，可按应用、输入控件能力或失败重试结果动态选择 |
| `Sources/TextFlash/EventController.swift` | 优先 Accessibility 设置选中文本，失败后回退 Unicode 注入 | 这是合理的通用降级，但缺少可观测的失败原因和策略记录 | 抽成 `InsertionStrategy`，记录 AX 成功率、失败类型，再决定是否回退或记忆偏好 |
| `Sources/TextFlash/EventController.swift` | 检测 `AXIsSecureTextField` 和 `AXSecureTextField` 后禁用展开 | 安全场景必须保留，但目前检测逻辑散落在事件控制器里 | 抽成独立的 focused element classifier，后续统一处理 password、secure note 等安全控件 |
| `Sources/TextFlash/EventController.swift` | 将中文标点 `，。？、` 归一为英文触发符 | 这属于输入法场景定制，当前规则固定 | 改为用户可配置的触发符归一化表，或随语言/输入法配置启用 |

## 个人路径或迁移定制

| 位置 | 当前做法 | 问题 | 后续方向 |
| --- | --- | --- | --- |
| `Sources/TextFlash/DatabaseManager.swift` | 已删除首次启动时从 `~/Documents/Github/TextFlash/data/snippets.json` 和 `~/Documents/Luigi/TextFlash/data/snippets.json` 自动迁移旧 JSON 的逻辑 | 旧逻辑是个人开发路径，发布版本不应依赖这些路径 | 继续使用现有手动导入/导出功能处理 JSON 数据 |

## 打包和资源整理

| 位置 | 当前做法 | 处理结果 |
| --- | --- | --- |
| `release.sh` | 旧版本 DMG 输出到项目根目录 | 已改为输出到 `dist/TextFlash-<version>.dmg` |
| 根目录 | `AppIcon.icns` 放在根目录 | 已移动到 `Sources/TextFlash/Resources/Assets/AppIcon.icns` |
| 根目录 | 旧 `TextFlash-0.1.0.dmg` 放在根目录 | 已移动到 `dist/TextFlash-0.1.0.dmg` |
