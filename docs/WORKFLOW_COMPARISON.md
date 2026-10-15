# MQD、Maya Quad Draw 与 Max PolyDraw

[中文首页](../README.md) · [English guide](../README.en.md)

## MQD 的定位

MQD多边形绘制把常用的多边形绘制动作集中到 3ds Max 2024 的一个交互流程中，让操作者少在面板和工具之间来回切换，多把注意力放在点的位置、边流和形体上。它面向手动重拓扑与参考表面建模，不负责自动为整个模型生成拓扑。

对 Maya 用户，熟悉的是“打点—预览—补面—调整—继续绘制”的思路；对 Max 用户，保留的是现有场景、Editable Poly 工作网格和原生参考表面参数。MQD 的主要价值是这两部分的结合。

## 三者的取舍

| 方面 | Maya Quad Draw | Max 原生 PolyDraw | MQD v1.1.0 的选择 |
|---|---|---|---|
| 绘制流程 | 一体化手动重拓扑工具，可预览和继续调整 [1][2] | Step Build、Extend、Optimize 等各有操作与组合键 [3] | 将常用操作合并，按鼠标位置和组合键切换动作，减少显式选工具 |
| 四边面 | Shift 预览后提交 [1] | Step Build 提供最近四点建面及显式选点方式 [3] | 采用最近四点的规则，加上持续候选预览和提交前复核 |
| 表面距离 | Live Constraint Options 中有 Surface Offset [2] | PolyDraw 有数值 Offset [3] | 沿用 Max 的 PDOffset；这是一项保留下来的原生能力，不是独有发明 |
| 三角洞 | 支持填补三角形空洞 [1] | 原生建面工具也有显式选点等路径 [3] | 在同一 Shift 补面流程中识别已有三边闭合的洞 |
| 宿主与后续编辑 | 在 Maya 工作流中继续编辑 | 在 Max 原生工作流中继续编辑 | 在 Max 的 Editable Poly 上工作，无需为了使用这种绘制方式切换到 Maya |

来源：[1] [Maya 创建多边形](https://help.autodesk.com/cloudhelp/2026/ENU/Maya-Modeling/files/GUID-5308DF0F-8E0F-4851-A203-491A597001AC.htm)；[2] [Maya Quad Draw 工具选项](https://help.autodesk.com/cloudhelp/2025/ENU/Maya-Modeling/files/GUID-35D650EE-C840-4E4B-8E5C-DC5FFE4DA53A.htm)；[3] [Max PolyDraw：添加几何与优化工具](https://help.autodesk.com/cloudhelp/2020/ENU/3DSMax-Modeling/files/GUID-3861007B-2549-4770-8E6F-AACC65DF50AE.htm)。官方页面说明各自工具行为；MQD 当前实现以本仓库 v1.1.0 代码为准。

## 真正增加的便利

**少切换，连续做。** 放置点后，可以直接拖动调整，再按住 Shift 查看补面候选；补完面后继续延展。改进的是操作的衔接，不是声称 Max 原先无法完成这些建模结果。

**连接关系先显示，再确认。** 点、边、面的识别反馈与候选面提示集中在视口中。点击时复核已显示的点和点序；条件变化就取消这次提交，让操作者重新定位。它让“准备连接谁”更容易检查，但不能替代操作者对拓扑的判断。

**保留 Max 原生参数。** 数值偏移来自 PolyDraw 的 Offset；MQD 读取 `PolyToolsUI.PDOffset` 并传给表面命中查询。这个数值控制绘制/贴面位置，不能理解为给已有整张网格添加了一个可随时回改的厚度修改器，也不能保证低模面内部处处都与弯曲参考面保持相同距离。

**接受条件统一。** 当前四点不合格时不寻找远处替代组合；预览、点序准备和实际提交相互核对，配合局部几何检查与原生撤销事务。收益是减少规则互相矛盾的情况；代价是某些位置不会给出候选，需要移动鼠标、调整点或使用 Max 的其他建面方式。

## 使用边界

- MQD 的快捷键并非 Maya 的完整复制，具体以[基本操作](../README.md#基本操作)为准。
- 松弛功能可用，但连续笔划与手感并未宣称达到或超过 Maya；需要时可以退出使用熟悉的原生松弛工具。
- 三角补面限定为已有三边闭合的洞；MQD 不覆盖 Max 原生工具的所有显式选点建面方式。
- 当前支持 Max 2024 x64，工作网格和参考表面为不同对象。复杂薄层、反向法线和密集几何仍应在模型副本上验证，具体回归范围见[测试说明](TESTING.md)。

## 对应实现

| 行为 | 可查看的实现入口 |
|---|---|
| 原生 Offset 与参考表面查询 | [Recognizer](../payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Recognizer.ms)：`syncSharedState`、`surfaceHitAt` |
| 四点候选、闭合三角洞与提交复核 | [CandidatePreview](../payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_CandidatePreview.ms)：`buildQuadCandidate`、`buildClosedTriangleHoleCandidate`、`validateCandidateForCommit` |
| 补面入口与操作分流 | [Core](../payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms)：`directFaceCommit` 及原生操作桥接 |
| 原生规则及回归用例 | [V16 源码](../source/native/MayaQuadDrawNativeBridgeV16)、[测试目录](../tests)、[测试范围](TESTING.md) |

## English summary

MQD's practical advantage is **workflow integration inside Max**, not a claim that its individual modeling operations are new. It brings point placement, component adjustment, candidate preview, face creation and extension into a continuous interaction flow while retaining an Editable Poly work mesh and native PolyDraw surface settings.

Maya already offers an integrated Quad Draw workflow, Shift face previews, triangular-hole filling and Surface Offset. Max already provides Step Build, Extend and numeric surface offset. MQD adapts those workflow ideas to Max and adds its own candidate feedback and preview-to-commit checks. See official references [1]–[3] above.

For a Max-based artist, the benefit is staying in the existing scene with fewer explicit tool changes. Offset is read from `PolyToolsUI.PDOffset`; it is not an MQD-exclusive feature or a persistent thickness modifier. The current candidate rule selects one nearest-four set and rejects it if invalid, rather than looking for a more distant substitute. Some locations therefore produce no preview and need repositioning or another modeling approach.

MQD is not a full Maya Quad Draw clone or a replacement for every native Max modeling tool. Its triangle-fill operation requires a closed three-edge hole, its Relax feel remains a limitation, and supported host compatibility is Max 2024 x64. The screenshots in both READMEs illustrate the workflow; they do not establish a performance advantage or universal geometry safety.
