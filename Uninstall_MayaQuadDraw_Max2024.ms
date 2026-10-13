(
    try
    (
        if MayaQuadDraw_Stop != undefined do MayaQuadDraw_Stop()
    )
    catch()

    local rootPath = (getDir #userScripts) + "\\MayaQuadDraw_Max2024\\"
    local loaderPath = (getDir #userStartupScripts) + "\\MayaQuadDraw_Max2024_Startup.ms"
    local macroPath = (getDir #userMacros) + "\\MayaQuadDraw_Max2024.mcr"

    if doesFileExist macroPath do
    (
        try (deleteFile macroPath) catch()
    )

    if doesFileExist loaderPath do
    (
        try (deleteFile loaderPath) catch()
    )

    local uninstallMessage =
        "MQD startup and action registration were removed.\n\n" +
        "Restart 3ds Max, then delete this folder if you want to remove all MQD files:\n\n" +
        rootPath

    messageBox uninstallMessage title:"MQD uninstall"

    true
)