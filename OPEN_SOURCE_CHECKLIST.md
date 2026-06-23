# 绘云轩开源发布清单

这份清单用于正式公开 GitHub 仓库、发布 APK 或邀请他人协作前逐项检查。

## 1. 先确认语料版权

古代诗词原文通常可以公开使用，但译文、注释、赏析、整理文本可能仍受版权保护。

发布前请重点检查：

- `唐诗三百首.json`
- 任何从网页、书籍、公众号、百科或资料库整理来的译文、注释、赏析
- README、截图、示例数据中是否包含受版权限制的内容

如果无法确认授权，建议：

1. 只保留诗词原文。
2. 将译文、注释、赏析替换为自己写的内容。
3. 或者不把该语料文件放入公开仓库，只在 release 中说明用户可自行导入。

## 2. 检查不要提交的文件

在 PowerShell 中执行：

```powershell
Set-Location E:\huiyunxuan
git status --short
git ls-files | findstr /i "key.properties .jks .keystore .apk .aab .hyxbak local.properties .env"
```

这些文件不应进入 Git：

- `*.hyxbak`
- `*.apk`
- `*.aab`
- `*.jks`
- `*.keystore`
- `key.properties`
- `local.properties`
- `.env`
- 任何真实 API Key、私人数据库、私人备份

## 3. 搜索疑似密钥

```powershell
rg -n "sk-[A-Za-z0-9]" .
rg -n "OPENAI_API_KEY|Authorization: Bearer|api_key|apiKey|apikey" lib android pubspec.yaml README.md
```

搜到字段名本身不一定有问题；真正危险的是硬编码的真实密钥。

## 4. 更新版本号

检查 `pubspec.yaml`：

```yaml
version: 1.0.5+6
```

规则：

- `1.0.5` 是用户看到的版本名。
- `+6` 是 Android versionCode，每次发布到用户手里都应递增。

## 5. 运行检查

如果本机环境允许，依次执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

如果 `flutter analyze` 或构建命令长时间卡住，先保留终端输出，再针对报错处理。

## 6. 安装升级测试

测试两种场景：

1. 覆盖安装旧版本：确认原诗词库、收藏夹、学习笔记、训练进度仍在。
2. 全新安装：确认默认存在“唐诗三百首”和“收藏夹”。

注意：卸载 App 后再安装会清空本地数据，这是 Android 的正常行为。

## 7. 准备 Git 提交

确认改动：

```powershell
git status --short
git diff --check
```

提交：

```powershell
git add -A
git commit -m "Prepare open source release"
git push origin main
```

如果 `唐诗三百首.json` 的版权没有确认，不要执行 `git add -A`，应先替换或移除该文件。

## 8. GitHub 仓库设置

建议：

- 仓库描述：`A Flutter Android app for Chinese poetry learning, training, and prosody assistance.`
- License 选择 MIT。
- 添加 topics：`flutter`, `android`, `poetry`, `chinese-poetry`, `sqlite`, `openai-compatible-api`。
- 开启 Issues，方便用户反馈。

## 9. GitHub Release

发布 APK 时：

1. 进入 GitHub 仓库的 Releases。
2. 创建新版本，例如 `v1.0.5`。
3. 上传 `build\app\outputs\flutter-apk\app-release.apk`。
4. 在说明中写清楚：
   - 覆盖安装可保留旧数据。
   - 卸载后重装会清空本地数据。
   - 升级前建议导出备份。
   - API Key 和备份文件只保存在用户本地。

## 10. 发布后维护

- 每次发布前递增 `pubspec.yaml` 的 build number。
- 保留一份 changelog 或 release notes。
- 不在 issue 中要求用户公开上传备份包。
- 处理用户问题时，优先让用户提供截图、终端报错或脱敏后的导入文件。
