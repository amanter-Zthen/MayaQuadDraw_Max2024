# 从源码构建

## Windows 原生插件

需要 3ds Max 2024 SDK、Visual Studio 2019 C++ 工具集及匹配的 Windows SDK。安装依赖后，运行：

```powershell
.\tools\Build-Native.ps1 -MaxSDK "C:\Program Files\Autodesk\3ds Max 2024 SDK\maxsdk" -MSBuild "完整路径\MSBuild.exe"
```

脚本构建 V16 和 Relax V20。V16 直接包含 V15 输入桥接源码，请保留 V15 目录。构建输出在各工程 `bin/Release`，默认不覆盖仓库中已验收的 DLX，也不修改本机 Max 安装。

要更新发布目录中的 DLX，可在完成验证后使用 `-StageBinaries`。不同编译器、路径或构建时间可能产生不同文件哈希；构建成功不代替 Max 内功能验证。

## 不依赖 Max SDK 的规则测试

使用 C++17 编译器，包含目录指定为 `source/native/MayaQuadDrawNativeBridgeV16`。例如在安装了 g++ 的 Linux/WSL 或 Windows 开发环境：

```sh
mkdir -p test-build
g++ -std=c++17 -Wall -Wextra -I source/native/MayaQuadDrawNativeBridgeV16 tests/native/stepbuild_candidate_tests.cpp -o test-build/stepbuild
g++ -std=c++17 -Wall -Wextra -I source/native/MayaQuadDrawNativeBridgeV16 tests/native/visibility_depth_tests.cpp -o test-build/visibility
g++ -std=c++17 -Wall -Wextra tests/native/settings_tab_tests.cpp -o test-build/settings-tab
./test-build/stepbuild
./test-build/visibility
./test-build/settings-tab
```

预期分别通过 121、71 和 138 项。原生 Max DLX 本身仍使用 Windows SDK 工具链构建。

## 校验与打包

```powershell
.\tools\Verify-Package.ps1
.\tools\Package-Release.ps1
```

输出在 `dist`，包括以 VERSION 命名的 MZP 和 SHA-256 文件。打包脚本按明确清单收集文件，保留发布所需 LICENSE 和文档，SDK、日志、私有场景、构建临时目录不进入安装包。

## 发布新版

1. 从 `main` 新建开发分支，完成改动、测试和审查后合并。
2. 更新根目录 `VERSION`、更新日志和相关说明。产品版本与 V16/V20 内部实现版本分别记录；若改内部版本，要同步启动与运行时依赖。
3. 按源码重新构建需要更新的 DLL，验证后同步发布目录，重新生成校验值和安装包。
4. 提交所有发布内容，再创建新的 `vX.Y.Z` 标签和对应 GitHub Release。
5. 将这一版的 MZP 与校验文件附在该 Release，保留旧标签和旧发行文件。

产品后续更新时，安装器从 VERSION 读取版本，无需在多个地方手工改版本提示。发布说明应区分历史基线测试和本版实际测试。

仓库规则保护 `main` 不被删除或强制改写历史，普通提交和合并仍可使用。`v*` 版本标签在创建后受更新和删除保护；新版本应使用新标签。这些规则保护 Git 引用，不等于锁定 Release 附件，维护者仍需按上述流程保留已发布的安装包。
