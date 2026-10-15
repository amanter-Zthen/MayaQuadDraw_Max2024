# MQD 常见问题与 Frequently Asked Questions

[中文首页](../README.md) · [English guide](../README.en.md) · [下载最新版 / Download](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/releases/latest)

## Max 有没有类似 Maya Quad Draw 的多边形绘制工具

MQD多边形绘制参考 Maya 的操作方式，把 Max 分散的四个多边形绘制模块整合起来，让打点、补面、移动调整、边界延展与松弛在连续操作中完成。重点是减少工具切换，保持创作思路连贯，不是复刻 Maya 的全部功能。

**Is there a Maya-style Quad Draw workflow for 3ds Max?** MQD provides an interactive polygon-drawing and manual-retopology workflow inside 3ds Max 2024. It integrates separate Max/PolyDraw operations; it does not claim to reproduce every Maya feature.

## MQD 是自动重拓扑还是手动重拓扑

它是手动重拓扑与交互式多边形绘制工具。操作者决定顶点位置与拓扑结构，工具提供表面约束、局部候选面和编辑操作，不会一键为整张高模自动重新布线。

**Is MQD an automatic remesher?** No. Artists place and edit geometry on a reference surface. Local face preview is an aid to manual retopology, not automatic whole-mesh reconstruction.

## 支持哪些软件和版本

当前发布面向 Windows x64 上的 3ds Max 2024。使用 MAXScript 和原生 DLX，交互验收环境为中文 Max。它运行在 Max 内，不需要安装 Maya。其他 Max 主版本需要重新构建并验证。

**Does MQD require Maya, or support other Max versions?** Maya is not required. The current binary release targets 3ds Max 2024 on Windows x64. Other major versions are not established as compatible.

## 普通用户应该下载哪个文件

在 [Releases](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/releases/latest) 下载 `.mzp`。GitHub 自动生成的 Source code ZIP 是开发源码，不是直接安装包。升级时先重启 Max，暂时不启动 MQD，再安装并按提示重启。

**Which download is the installer?** Use the `.mzp` release asset. The Source code archives are for developers. An already-loaded native plugin requires a Max restart before replacement.

## 上层修改器支持哪些？没有列出的可以用吗？

> [!WARNING]
> **目前仅验证 Editable Poly 基础对象上方的 TurboSmooth（涡轮平滑）和 OpenSubdiv 常规路径。其他修改器、特殊模式和组合尚未测试。** 不建议保留未测上层修改器时到基础层使用 MQD；超范围可能造成显示异常、撤销错乱、崩溃或数据损坏。风险已提前告知；如仍尝试，请备份并自行承担后果。

这里的 Editable Poly 指基础对象，不是宣称支持任意 Edit Poly 修改器堆栈。OpenSubdiv 的特殊 GPU 显示路径、所有参数和连续复杂修改器组合不在已验证范围。截图中的修改器快捷按钮不构成支持列表。

**Which upper modifiers are supported?** Only the tested standard TurboSmooth and OpenSubdiv paths over an Editable Poly base object are validated. Other modifiers/combinations and special GPU modes are untested. Avoid editing underneath them with MQD. Back up first; crashes, broken history and data damage are possible outside the validated scope, at your own risk.

## 参数窗在哪里？为什么自动焊接要撤销两次？

v1.1.0 默认不弹出参数窗。在 MQD 绘制视口中按 **Tab** 开关面板，也可运行独立设置动作。参数框内部的 Tab 保持字段切换，退出 MQD 后恢复 Max 原有 Tab 行为。

移动与自动焊接分成两条原生历史记录：**先撤焊接、再撤移动**。这是本版明确的操作方式，不做单步合并。普通未焊接的移动仍是一条记录；选择上层修改器或退出后再撤销，不会重新启动 MQD。

**Where are settings, and why two Undo steps?** Press Tab in the active drawing viewport to toggle settings. Tab in fields keeps normal navigation. A drag plus AutoWeld records movement and welding separately: undo the weld first, then the move. Exiting or selecting another modifier does not get undone into an active MQD session.

## 可以拿它接单或者在公司使用吗

可以。许可允许商业建模、接单、公司项目及出售自己制作的作品；限制的是插件本身或修改版的售卖、收费分发，以及把其代码并入收费插件/软件。完整条件见 [LICENSE](../LICENSE) 和[中文说明](../LICENSE.zh-CN.txt)。

**Can I use MQD for commercial modeling?** Yes. Paid production work and selling your output are permitted. Selling or charging for the plugin or a modified version, and incorporating its code into paid plugins/software, are restricted by the custom license. Source availability does not mean MIT/GPL licensing.

## 退出后为什么还有顶点方块

对象的“显示 → 显示属性 → 顶点标记”可能已经开启。工具恢复进入前状态，原先开启时就会恢复开启；该属性也可以随场景保存。关闭这个显示选项不删除顶点。若关闭后再次完整启动退出又异常开启，请提交版本和操作步骤。

**Why do vertex markers remain after exit?** Check the object's Vertex Ticks display property. MQD restores the captured value; a previously enabled value remains enabled. This is a display setting, not extra geometry.

## 如何把自己的修改改进反馈回来

欢迎通过 [Issues](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/issues/new/choose) 分享体验、问题与修改记录，通过 Pull Request 提交代码改进。希望大家尽量把有效改进带回原项目。反馈自愿，不要求上传私人模型，插件也没有自动上传功能。

**How can I contribute improvements?** Open an Issue with a reproducible report or a Pull Request with your changes and tests. Voluntary feedback helps the upstream project improve. Share only material you have permission to publish.

## main 和正式版本有什么区别

`main` 保存后续开发与说明更新，正式可下载版本由 `vX.Y.Z` 标签和 Release 对应。请在问题反馈中写出实际安装的发行版本，而不仅仅说“最新版”。已有发行包保持可追溯；文字说明更新不自动替换本机插件。

**Should I use main or a release?** Use a tagged Release for a fixed installable version. Developers work from main, which can contain later changes. Include your installed release number when reporting a problem.
