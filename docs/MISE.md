# Mise 命令速查

TextFlash 仍然以现有 shell 脚本作为真实执行入口。`mise` 只做一层统一命令面板：把 `deploy.sh`、`release.sh`、Swift 测试、release build 和版本计算收束到同一个 `mise run ...` 入口。

## 准备

安装 `mise` 后，在仓库根目录执行：

```bash
brew install mise
mise trust
mise tasks
```

`mise tasks` 会列出当前项目支持的全部任务。

## 日常开发

```bash
mise run build
mise run test
mise run build:release
mise run ci
```

- `build`：debug 编译，带 `-DDISABLE_PREVIEWS`。
- `test`：Swift 单测，带 `-DDISABLE_PREVIEWS`。
- `build:release`：release 编译，带 `-Osize` 与 `-DDISABLE_PREVIEWS`。
- `ci`：脚本语法检查、单测、release 编译。

## 应用工作流

```bash
mise run deploy
```

`deploy` 会编译、签名并启动 `~/Applications/TextFlash Dev.app`。

## 版本号

```bash
mise run version:current
mise run version:next
```

- `version:current`：读取最高的 SemVer 发布 tag。
- `version:next`：扫描最近 tag 到 `HEAD` 的 commit message，并按最高影响级别计算下一个 SemVer。

计算规则：

- `BREAKING CHANGE` 或 `type!`：major，例如 `0.1.11 -> 1.0.0`
- `feat`：minor，例如 `0.1.11 -> 0.2.0`
- `fix` 或 `perf`：patch，例如 `0.1.11 -> 0.1.12`
- 其他非空发布内容：默认 patch

如果多个 commit 同时包含 `feat` 和 `fix`，取更高影响级别，也就是 minor；只要有 breaking，就取 major。

## 发布

```bash
mise run release -- 0.1.12
mise run release -- 0.1.12 --force
mise run release-auto
mise run release-auto -- --force
mise run publish -- 0.1.12
mise run publish
```

- `release`：显式传版本号和参数给 `release.sh`。
- `release-auto`：先计算下一个版本号，再执行 `release.sh`。
- `publish`：执行 `release.sh <version> --publish`。不传版本号时，会先自动计算下一个版本。

凡是要传给底层脚本的参数，都放在 `--` 后面。
