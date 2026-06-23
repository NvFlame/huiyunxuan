# 绘云轩

绘云轩是一款 Flutter 安卓诗词学习与训练 App，目标是把本地诗词库、学文、展才训练、收藏、备份、AI 助手与格律辅助整合在一个轻量应用里。

项目目前以 Android 端为主，所有诗词库与学习数据默认保存在本机本地数据库中，不依赖云同步。

## 当前功能

- 诗词库管理：新建、编辑、删除诗词库，浏览库内诗词。
- 诗词元素：标题、作者、朝代、序/小序、正文、译文、注释、学习笔记、赏析、备注。
- 收藏夹：内置收藏库，可将诗词收藏到收藏夹。
- 学文：阅读诗词、查看注释/译文/赏析/学习笔记、切换上下首、跳转展才。
- 展才：秀才、举人、贡生、进士四种训练模式，即时批改/最终批改。
- 默诵值：记录首次通过进士模式的诗词。
- 格律辅助：近体诗基础审查，部分词牌词谱审查，支持人工/智能校准平仄与韵部。
- AI 助手：可配置 OpenAI 兼容 API 与搜索接口，用于问答、补全、添加或更正诗词资料。
- 导入导出：支持诗词/诗词库导入导出，以及整包备份与恢复。

## 开发环境

- Flutter SDK
- Android Studio
- Android SDK
- Windows PowerShell 或其他终端

项目目录示例：

```powershell
Set-Location E:\huiyunxuan
flutter pub get
flutter run
```

## 构建 APK

调试版：

```powershell
flutter build apk --debug
```

发布版：

```powershell
flutter build apk --release
```

发布 APK 通常位于：

```text
build\app\outputs\flutter-apk\app-release.apk
```

## 数据保留

同一个包名下覆盖安装新版 APK，Android 会保留 App 本地数据；卸载后重新安装会清空本地数据。升级前建议先在 App 设置中导出备份。

## 隐私与 API Key

API Key、诗词库、训练进度和备份数据默认保存在本地。备份包可能包含 API Key、学习笔记和完整诗词库，请不要公开分享自己的备份文件。

详见 [PRIVACY.md](PRIVACY.md)。

## 语料版权提醒

项目中的诗词原文多为古代作品，但译文、注释、赏析、整理文本可能存在版权。若要公开发布包含内置语料的源码或 APK，请确认相关内容允许再分发；不能确认时，请替换为自写内容、公共领域内容，或只保留原文。

当前内置语料文件：

```text
唐诗三百首.json
```

发布前请特别核验该文件中的译文、注释和赏析来源。

## 开源发布清单

发布前请按 [OPEN_SOURCE_CHECKLIST.md](OPEN_SOURCE_CHECKLIST.md) 检查密钥、备份、语料版权、构建产物和版本号。

## 许可证

本项目代码计划以 MIT License 开源。详见 [LICENSE](LICENSE)。
