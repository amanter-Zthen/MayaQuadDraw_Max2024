# MayaQuadDraw_Max2024

[中文](README.md) · [English](README.en.md) · [下载最新版](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/releases/latest) · [安装说明](docs/INSTALL.md) · [常见问题](docs/FAQ.md) · [反馈问题](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/issues/new/choose)

**MQD多边形绘制**是一款适用于 Windows 上 Autodesk 3ds Max 2024 的多边形绘制与重拓扑插件。它参考 Maya 的操作方式，将 Max 原本分散的四个多边形绘制模块整合为统一工具。

制作这款插件的初衷，是减少工具切换和零散操作，让操作者在绘制多边形时，既拥有简洁的操作方式，也能保持连贯的创作思路，将注意力更多地放在模型本身。

插件支持在参考模型表面打点、预览补面，并进行点、边、面的调整。

**Maya-style polygon drawing and manual retopology for 3ds Max 2024.** MQD brings separate PolyDraw operations into one continuous surface-modeling workflow: place vertices, preview and create faces, move components, extend borders, and relax geometry. It is an interactive drawing tool, not an automatic remesher. [English guide](README.en.md).

这是项目的第一个公开版本 **v1.0.0**。欢迎免费使用，也欢迎把遇到的问题、使用建议和代码改进提交回来，一起把这个工具做得更顺手。

源码公开，采用自定义免费使用许可：**允许用于商业建模和公司项目；插件本身及修改版免费提供，不得售卖、收费分发或并入收费插件。** 这不是 MIT/GPL 或 OSI 标准开源许可。完整条件见 [LICENSE](LICENSE) 和[中文许可说明](LICENSE.zh-CN.txt)。

## 下载与安装

**普通使用者：[打开最新发行版，下载 `.mzp` 安装包](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/releases/latest)。** 开发者可以克隆整个仓库；GitHub 自动提供的 Source code ZIP 是源码归档，不是直接拖入 Max 的 MZP 安装包。

| 项目 | 当前支持范围 |
|---|---|
| 宿主 | Autodesk 3ds Max 2024，64 位 |
| 系统 | Windows |
| 用途 | 多边形绘制、手动重拓扑、参考表面上的几何调整 |
| 工作网格 | Editable Poly，参考表面为另一个对象 |
| 界面与验收 | 中文参数界面，交互测试使用中文 Max |
| 许可 | 允许商业制作使用；插件本身及修改版禁止售卖 |

1. 保存场景。升级时先退出并重新打开 Max，暂时不要启动 MQD，确保旧原生插件尚未加载。
2. 把 `.mzp` 拖入 Max 视口，按提示安装，再重启 Max。
3. 在热键编辑器中找到分类 **MQD Tools**、动作 **MQD Quad Draw**，自行绑定 **Ctrl+Shift+Q**。安装器不覆盖已有快捷键。
4. 选择一个作为工作网格的 **Editable Poly**，通过 PolyDraw 的 **Pick/拾取** 选择另一个参考表面，再启动 MQD。

目标环境为 **3ds Max 2024 x64 / Windows**。交互测试使用中文 Max；其他 Max 主版本需要对应 SDK 构建与单独验证，不应直接混用 DLX。

首次使用和升级后，先在场景副本上验证。详细步骤、卸载和显示状态处理见[安装与使用说明](docs/INSTALL.md)。

## 基本操作

| 操作 | 功能 |
|---|---|
| 点击参考表面空白位置 | 放置顶点 |
| 拖动可识别的点、边或面 | 调整位置，贴合参考表面 |
| 按住 Shift 悬停并点击 | 预览并提交四边面，或填补闭合三角洞 |
| Shift 拖动边界 | 单边延展 |
| Ctrl+Shift 拖动边界 | 整圈延展 |
| Ctrl 点击边 | 插入线圈 |
| Ctrl+Alt 点击点、边或面 | 删除对应元素 |
| Shift 在内部区域拖动 | Relax，手感仍有改进空间 |
| 右键或退出当前工具 | 结束 MQD，恢复进入前的相关状态 |

四边面采用一组最近四点的判断方式。这组点不能构成合格面时不显示候选，移动鼠标后再计算。预览与点击提交使用同一组点和确定的点序，同时检查重复面、共享边、朝向与局部穿插。

## 操作示例与实际优势

MQD 的重点是**让习惯 Max 的操作者，在原有场景里获得接近 Maya Quad Draw 的连续绘制体验**：打点、看预览、补面、拖动调整，再接着延展。参考的是操作思路，快捷键和建面规则仍按 Max 环境适配。

### 先看清要连接的点，再提交面

![MQD 在 3ds Max 2024 参考表面上预览四边面：青色轮廓连接四个高亮顶点，蓝色区域是已有网格](docs/images/quad-preview.png)

按住 **Shift** 悬停，青色轮廓和四个高亮角点提示当前准备连接的位置；确认后点击补面。这样可以在提交前判断布线走向，而不是先生成面再看连接到了哪里。松开 Shift 后，可以继续打点或拖动点、边、面调整位置，不必为每一步重新选择一个绘制工具。

### 在同一工具里补上闭合三角洞

**补面前：** 三条已有边围成一个三角形空洞。

![MQD 补面前：蓝色拓扑网格中央有一个由三条已有边围成的三角洞](docs/images/triangle-hole-before.png)

**补面后：** 在洞内按住 **Shift** 查看候选并点击，将这处空洞接回周围网格，随后可以继续绘制。这适用于已有三条边闭合的三角洞，不是任意三个散点成面。

![MQD 补面后：原来的三角洞已填入一个面，与周围蓝色网格连接](docs/images/triangle-hole-after.png)

这三张图来自实际使用截图；前后视角略有变化，展示的是候选提示与补洞结果，不是拖动速度测试。

### 改进集中在哪里

| 设计重点 | 对操作的实际影响 |
|---|---|
| 将分散的常用 PolyDraw 操作放进一个交互流程 | 减少打点、调整、延展之间的工具切换，把注意力留在布线上 |
| 点、边、面识别提示，加上 Shift 候选预览 | 提交前能看清当前对象和连接位置；预览与点击复核同一组点 |
| 保留 Max 原生参考表面与数值偏移 | 继续使用 PolyDraw 的 **Offset/偏移** 控制绘制时离参考面的距离，无需离开 Max 重新搭建工作流程 |
| 按 Max 的建面约束处理候选 | 最近四点不合格时等待重新定位，不用更远的点替换；配合方向、重复面和局部穿插检查 |

**表面偏移不是 MQD 独有功能。** Maya Quad Draw 也提供 Surface Offset；MQD 的价值是保留 Max 原生参数，并把它接入统一的绘制流程。预览补面、三角洞填补也属于 Maya 已有的操作思路。MQD 不宣称功能全面超过 Maya，Relax 手感仍有改进空间。详见[与 Maya / Max 原生工具的对照与设计取舍](docs/WORKFLOW_COMPARISON.md)，其中附有官方说明和对应代码入口。

## 常见问题

**Max 能否用类似 Maya Quad Draw 的方式绘制多边形？** MQD 的目标就是把原生 PolyDraw 中分散的打点补面、移动调整、边界延展和松弛等操作整合为连续工作流程，减少切换。它是 Max 插件，不是 Maya 插件，也不要求安装 Maya。

**这是自动重拓扑工具吗？** 不是。MQD 由操作者决定点的位置与拓扑走向；Shift 提供局部候选预览和建面，不会自动为整个模型重新布线。

更多兼容性、商业用途、安装和显示问题，见[中英文 FAQ](docs/FAQ.md)。

## 版本与验证

- 产品版本：`1.0.0`，首个公开发行版。
- 原生桥接实现：`0.17.6-max2024-v16-unified-stepbuild`。
- Relax 实现：`0.20.0-max2024-sdk-paint-deform-dense-stroke`。
- 2026-09-16 完成的 Max 内 v4 自检：**81 项通过，0 失败**；随后用户确认实际操作正常。
- 独立候选规则测试 121 项、深度数值测试 71 项；测试源码随仓库提供。

这些结果覆盖既定测试用例，不是对任意场景的保证。公开首版保留已验收的运行时和 DLX；安装清单已更新为 V16，发布包完成文件与结构校验，新的干净环境安装仍需用户验证。详细范围见[测试说明](docs/TESTING.md)。

## 源码与构建

```text
payload/MayaQuadDraw_Max2024/runtime/  MAXScript 运行时
payload/MayaQuadDraw_Max2024/plugins/  已验收的原生 DLX
source/native/                        原生 C++ 源码及 Visual Studio 工程
startup/                             启动加载器
macro/                               工具动作
tests/                               独立 C++ 测试和 Max 内自检
tools/                               构建、校验与打包脚本
```

V16 编译时包含 V15 的输入桥接源码，因此 V15 源目录是必要依赖；正常安装只部署 V16 和 Relax V20 两个 DLX。3ds Max、Max SDK 和 Visual Studio 需自行合法安装，不随仓库分发。参见[构建说明](docs/BUILD.md)与[第三方说明](THIRD_PARTY_NOTICES.md)。

## 反馈和改进

希望大家把使用情况和改进尽量反馈回来：

- 遇到问题，请通过 [Issues](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/issues) 说明插件版本、Max 版本、操作步骤和实际结果。
- 修改了代码，欢迎发起 [Pull Request](https://github.com/amanter-Zthen/MayaQuadDraw_Max2024/pulls)，说明改动及测试结果。
- 如果暂时不方便提交代码，发一个改进思路或问题说明也有帮助。

反馈与贡献是自愿的。插件没有自动收集或上传功能；请只上传有权分享的最小复现材料，保护客户模型与私人文件。详见[贡献指南](CONTRIBUTING.md)。

## 后续更新

`main` 用于后续开发，正式版本以 `vX.Y.Z` 标签和 Releases 为准。每版源码、安装包、[更新日志](CHANGELOG.md)与 SHA-256 校验文件对应；已经发布的标签和安装包不被另一版覆盖。不要把本仓库首版与早期未发布的同号实验 MZP 混用。

项目与 Autodesk 无隶属或认可关系；Maya、3ds Max 等名称属于其各自权利人。
