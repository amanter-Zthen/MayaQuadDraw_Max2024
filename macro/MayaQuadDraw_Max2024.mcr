macroScript MayaQuadDrawMax2024Toggle
category:"MQD Tools"
internalCategory:"MQD Tools"
toolTip:"MQD Quad Draw - Start or Stop"
buttonText:"MQD Quad Draw"
silentErrors:false
autoUndoEnabled:false
(
    global MayaQuadDraw_Toggle
    global MayaQuadDrawR6

    on isEnabled return true

    on isChecked return
    (
        try
        (
            MayaQuadDrawR6 != undefined and MayaQuadDrawR6.active
        )
        catch
        (
            false
        )
    )

    on execute do
    (
        if MayaQuadDraw_Toggle == undefined do
        (
            local loaderPath = (getDir #userStartupScripts) + "\\MayaQuadDraw_Max2024_Startup.ms"

            if doesFileExist loaderPath do
            (
                fileIn loaderPath quiet:true
            )
        )

        if MayaQuadDraw_Toggle != undefined then
        (
            MayaQuadDraw_Toggle()
        )
        else
        (
            messageBox "MQD startup loader could not be loaded. Reinstall the package." title:"MQD"
        )
    )
)

macroScript MayaQuadDrawMax2024Settings
category:"MQD Tools"
internalCategory:"MQD Tools"
toolTip:"MQD 参数设置 - 显示或隐藏"
buttonText:"MQD 设置"
silentErrors:false
autoUndoEnabled:false
(
    global MayaQuadDraw_Settings
    global MayaQuadDrawUI_IsOpen

    on isEnabled return true
    on isChecked return (try (MayaQuadDrawUI_IsOpen != undefined and MayaQuadDrawUI_IsOpen()) catch (false))

    on execute do
    (
        if MayaQuadDraw_Settings == undefined do
        (
            local loaderPath = (getDir #userStartupScripts) + "\\MayaQuadDraw_Max2024_Startup.ms"
            if doesFileExist loaderPath do fileIn loaderPath quiet:true
        )
        if MayaQuadDraw_Settings != undefined then MayaQuadDraw_Settings()
        else messageBox "MQD 启动加载器未找到，请重新安装。" title:"MQD 设置"
    )
)
