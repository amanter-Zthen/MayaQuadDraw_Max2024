/* MQD public installer. Copies the verified runtime; no scene changes. */
(
    local packageRoot = getFilenamePath (getSourceFileName())
    local rootPath = (getDir #userScripts) + "\\MayaQuadDraw_Max2024\\"
    local fileAPI = dotNetClass "System.IO.File"
    local changed = #()
    local ready = false
    local productVersion = ""
    local backupRoot = rootPath + "install_backups\\" + ((dotNetClass "System.DateTime").Now.ToString "yyyyMMdd_HHmmss_fff") + "\\"
    local entries = #(
        #("payload\\MayaQuadDraw_Max2024\\runtime\\MayaQuadDraw_Core.ms", rootPath+"runtime\\MayaQuadDraw_Core.ms"),
        #("payload\\MayaQuadDraw_Max2024\\runtime\\MayaQuadDraw_CandidatePreview.ms", rootPath+"runtime\\MayaQuadDraw_CandidatePreview.ms"),
        #("payload\\MayaQuadDraw_Max2024\\runtime\\MayaQuadDraw_Recognizer.ms", rootPath+"runtime\\MayaQuadDraw_Recognizer.ms"),
        #("payload\\MayaQuadDraw_Max2024\\plugins\\MayaQuadDrawNativeBridge_v16.dlx", rootPath+"plugins\\MayaQuadDrawNativeBridge_v16.dlx"),
        #("payload\\MayaQuadDraw_Max2024\\plugins\\MayaQuadDrawInternalRelax_v20.dlx", rootPath+"plugins\\MayaQuadDrawInternalRelax_v20.dlx"),
        #("startup\\MayaQuadDraw_Max2024_Startup.ms", (getDir #userStartupScripts)+"\\MayaQuadDraw_Max2024_Startup.ms"),
        #("macro\\MayaQuadDraw_Max2024.mcr", (getDir #userMacros)+"\\MayaQuadDraw_Max2024.mcr"),
        #("Uninstall_MayaQuadDraw_Max2024.ms", rootPath+"Uninstall_MayaQuadDraw_Max2024.ms"),
        #("VERSION", rootPath+"docs\\VERSION.txt"),
        #("README.md", rootPath+"docs\\README.md"),
        #("LICENSE", rootPath+"docs\\LICENSE"),
        #("LICENSE.zh-CN.txt", rootPath+"docs\\LICENSE.zh-CN.txt"),
        #("docs\\INSTALL.md", rootPath+"docs\\INSTALL.md")
    )
    try
    (
        local versionValue = (maxVersion())[1]
        if versionValue < 26000 or versionValue >= 27000 do throw "此安装包仅适用于 3ds Max 2024。"
        local loadedBridge = try (globalVars.get #MQDNativeV15BridgeVersion) catch (undefined)
        local loadedRelax = try (globalVars.get #MQDInternalRelaxV20BridgeVersion) catch (undefined)
        local loadedRelaxStep = try (globalVars.get #MQDInternalRelaxV20Step) catch (undefined)
        if loadedBridge != undefined or loadedRelax != undefined or loadedRelaxStep != undefined do
            throw "MQD 原生插件已在当前 Max 中加载。请保存场景并重启 Max，暂时不要启动 MQD，再运行安装包。"
        for entry in entries do
            if not doesFileExist (packageRoot+entry[1]) do throw ("安装包缺少文件："+entry[1])
        local versionStream = openFile (packageRoot+"VERSION")
        productVersion = readLine versionStream
        close versionStream
        makeDir (rootPath+"logs\\") all:true
        for i = 1 to entries.count do
        (
            local target = entries[i][2]
            local previous = undefined
            makeDir (getFilenamePath target) all:true
            if doesFileExist target do
            (
                makeDir backupRoot all:true
                previous = backupRoot+(i as string)+"_"+(filenameFromPath target)
                fileAPI.Copy target previous true
            )
            append changed #(target,previous)
            fileAPI.Copy (packageRoot+entries[i][1]) target true
        )
        fileIn ((getDir #userStartupScripts)+"\\MayaQuadDraw_Max2024_Startup.ms") quiet:true
        fileIn ((getDir #userMacros)+"\\MayaQuadDraw_Max2024.mcr") quiet:true
        ready = true
        messageBox ("MQD多边形绘制 v"+productVersion+" 安装完成。\n\n请重启 Max 后使用。\n动作分类：MQD Tools\n动作名称：MQD Quad Draw\n建议手动绑定：Ctrl+Shift+Q\n\n安装位置：\n"+rootPath) title:"MQD多边形绘制"
    )
    catch
    (
        local reason = getCurrentException()
        local rollbackOK = true
        for i = changed.count to 1 by -1 do
        (
            local entry = changed[i]
            try
            (
                if entry[2] != undefined then fileAPI.Copy entry[2] entry[1] true
                else if doesFileExist entry[1] do (if not (deleteFile entry[1]) do rollbackOK = false)
            )
            catch (rollbackOK = false)
        )
        local note = if rollbackOK then "\n\n未完成安装；如已复制文件，已恢复先前文件。请重启 Max 后重试。" else
            ("\n\n部分文件未能恢复，请保留此提示和备份目录：\n"+backupRoot)
        messageBox (reason+note) title:"MQD 安装未完成"
    )
    ready
)
