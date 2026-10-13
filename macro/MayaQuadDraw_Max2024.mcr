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