# 第三方产品与依赖

MQD 使用 Autodesk 3ds Max 的 MAXScript、PolyDraw、Editable Poly 和 Painter/SDK 接口，并参考宿主的建模行为实现自己的工具逻辑。它不是 Autodesk 官方产品，也未获得 Autodesk 认可或背书。

运行需要用户自行安装并取得适当授权的 3ds Max 2024。编译原生源码还需要 3ds Max 2024 SDK、Visual Studio C++ 工具链及 Windows SDK；这些依赖遵循各自的条款，不由 MQD 的 LICENSE 授权。

仓库不提供 Autodesk 程序二进制、SDK 头文件/库/样例文件，或第三方反编译输出。`source/native` 是本项目的集成实现；代码中的接口名、技术引用和算法来源说明不意味着授予第三方产品或代码的权利。

预编译的两个 DLX 是 MQD 插件构建产物。源码仓库保留 V15 输入桥接实现，因为 V16 编译时需要它；发布安装器仅安装 V16 和 Relax V20。

Maya、3ds Max、Autodesk、Microsoft、Windows 及 Visual Studio 等名称或商标归各自权利人所有。
