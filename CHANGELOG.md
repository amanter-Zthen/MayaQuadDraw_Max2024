# 更新日志

## 1.1.0 — 2026-10-15

> [!WARNING]
> **上层修改器目前只验证 TurboSmooth（涡轮平滑）和 OpenSubdiv 的常规已测路径。其他修改器、特殊模式和组合尚未测试，不建议保留它们时在基础层使用 MQD。** 超范围尝试可能导致显示异常、撤销错乱、崩溃或数据损坏；请先备份，自行承担使用风险（后果自负）。这不是所有参数与场景均已通过的保证。

### 新增与改善

- **Tab 开关参数面板**：MQD 激活且焦点在绘制视口时生效，长按不反复跳窗；参数框内和退出后保留 Max 的正常 Tab 行为。
- **参数窗按需显示并记住位置**：进入绘制不再把窗口弹到屏幕中央，显式打开后的窗口独立于绘制会话管理。
- **TurboSmooth / OpenSubdiv 基础层适配**：原生接口编辑 Editable Poly 控制网格，上层由 Max 求值；避免把细分输出的顶点当成控制点显示或操作。
- **热启停**：保留已加载运行资源，减少重复初始化、选择和重绘；退出时释放当前网格绑定与会话回调。
- **退出与撤销边界**：选择其他修改器或进入其他工具时结束 MQD；后续 Undo/Redo 不自动重开绘制，也不把用户切回旧层级。
- **自动焊接改为两条原生撤销记录**：先撤焊接、再撤移动；普通未焊接的拖动仍为一次。遇到不能记录的历史上下文时保留移动、不强行焊接。
- 增加生命周期、细分接口、两步焊接和 Tab 的回归测试，并补充真实试用截图及兼容性边界。

### 范围与版本

- 目标：Windows x64 / 3ds Max 2024；本机交互验收使用中文 Max 2024.2。
- 产品/运行时：`1.1.0` / `1.1.0-max2024`；原生桥 `0.17.9-max2024-v16-settings-tab`；Relax 接口 `0.20.1-max2024-sdk-paint-deform-base-object`。
- 本次不重做 Relax 手感/算法，不宣称支持其他修改器、所有 GPU 模式或任意中途取消组合。
- 用户已试用本轮细分、修改器切换、焊接撤销与 Tab，并反馈正常；自动检查的覆盖与限制见 [TESTING](docs/TESTING.md)。
- 本机正式安装目录冷启动：补面回归 81/0、面板/启停 31/0，核对运行时与原生模块实际路径；不等同于所有机器或干净 MZP 安装均验证。
- 发布新标签和新安装包，保留 v1.0.0，不覆盖历史发行文件。许可条款保持不变。

### English summary

- Session-scoped **Tab** toggles settings; the on-demand panel remembers its position.
- Adapted native editing to the **Editable Poly base cage** beneath tested TurboSmooth / OpenSubdiv paths.
- Retained loaded resources for warmer activation; selecting another modifier ends drawing and later Undo does not reopen MQD.
- Native movement and AutoWeld now have **two independent Undo entries**: undo the weld, then the move.
- **Other upper modifiers and combinations are untested. Avoid using MQD underneath them.** Back up first; experimenting outside the validated scope is at your own risk and may cause crashes or data damage.
- Added regression coverage and an actual OpenSubdiv trial screenshot. Relax feel was not redesigned; licensing is unchanged.

## 1.0.0 — 2026-10-13

首个 GitHub 公开发行版，中文名“MQD多边形绘制”。

- 表面打点、点边面移动、候选预览与补面、闭合三角洞、单边与整圈延展、插入线圈、删除、自动焊接与 Relax。
- 四边面统一为最近四点决策；预览准备最终点序，点击复核后使用严格建面入口。
- 保留层叠遮挡、安全建面与原生撤销；恢复中文参数面板、隐藏视口调试文字及退出状态处理。
- 原生实现基线为 V16 0.17.6 与 Relax V20 0.20.0；Max v4 自检历史结果为 81 项通过。
- 发布安装清单使用 V16，保留修复后的宏作用域声明；新增构建、校验、打包与反馈模板。
- 采用允许商业生产使用、限制插件售卖的自定义免费使用许可。

首版基于 2026-09-16 至 17 日完成验收的运行时；公开发布日期与运行时测试日期不同。此前本地同号实验安装包不属于本仓库 Release。
