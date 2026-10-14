# 参与 MQD多边形绘制

欢迎把使用反馈、修改记录和代码改进提交回来。一个清楚的复现步骤，或者一项已经验证的细节改进，都能帮助后续版本。

[中文首页](README.md) · [English guide](README.en.md) · [FAQ](docs/FAQ.md) · [提交反馈 / Open an issue](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/issues/new/choose)

## 提交问题

在 Issues 选择问题反馈，填写发布版本、Max 版本、复现步骤、期望与实际结果。截图有帮助；模型并非必需。如果需要附场景，请制作最小副本，并确认可以公开。插件运行日志位于 Max 用户脚本目录下的 `MayaQuadDraw_Max2024/logs`，提交前请删除私人路径、客户信息和无关内容。

## 提交代码

从 `main` 新建自己的分支，围绕一个问题做清晰的改动，再发起 Pull Request。请说明：

- 改善了什么行为，为什么这样改。
- 影响哪些模块，有哪些兼容性限制。
- 执行了什么测试，哪些结果仍需确认。
- 是否影响拾取手感、预览与建面一致性、撤销、退出状态或安装升级。

包含 Max 运行时的改动，应先在空场景运行 `tests/max/MQD_SelfTest.ms`，再用副本验证实际操作。提交源码和必要文档即可，构建临时文件、SDK 和私人场景留在本地。

请让原版与修改版身份清晰。未经维护者发布的构建，不使用官方 Release 的身份。主动提交合入项目的贡献采用本仓库 LICENSE，贡献者保留自己的版权。

## 不方便提交代码时

可以只发 Issue，写下修改思路、使用体验或希望改善的操作。提交改进、公开私人修改和反馈使用记录均为自愿；项目没有自动上传功能。

## Contributing in English

Bug reports, workflow suggestions and code improvements are welcome. Use the issue templates and include the installed MQD release, Max version, reproduction steps, expected result and actual result. Share only screenshots, logs or minimal scenes that you have permission to publish.

For code changes, fork the repository, create a branch from main, and open a Pull Request explaining the purpose, scope, tests and known limitations. Runtime changes should be tested in an empty Max scene with `tests/max/MQD_SelfTest.ms`, then on a scene copy. Consider picking, preview/commit consistency, Undo/Redo and exit behavior.

If you do not have a Max development environment, clear reproduction steps, documentation fixes and translations are also useful. Avoid submitting SDK files, build outputs or private models. Intentional contributions are offered under the repository LICENSE unless separately agreed; contributors retain their copyright. Feedback and publication of private modifications remain voluntary.
