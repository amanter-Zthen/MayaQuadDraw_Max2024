/* Maya Quad Draw for 3ds Max 2024 - lightweight startup loader. */

global MayaQuadDrawRootPath
global MayaQuadDrawInstalledRuntimeVersion
global PolyBoost
global MayaQuadDraw_Load
global MayaQuadDraw_Start
global MayaQuadDraw_Stop
global MayaQuadDraw_Toggle
global MayaQuadDraw_Settings

MayaQuadDrawRootPath = (getDir #userScripts) + "\\MayaQuadDraw_Max2024\\"

fn MayaQuadDraw_Load =
(
    local corePath = MayaQuadDrawRootPath + "runtime\\MayaQuadDraw_Core.ms"
    if not doesFileExist corePath then
    (
        messageBox ("MQD runtime is missing:\n\n" + corePath) title:"MQD installation"
        false
    )
    else
    (
        local alreadyLoaded = try (MayaQuadDrawInstalledRuntimeVersion == "1.0.0-max2024-v20-stack1") catch (false)
        if alreadyLoaded then true
        else
        (
            local loaded = try
            (
                fileIn corePath quiet:true
                true
            )
            catch
            (
                messageBox ("MQD could not load:\n\n" + getCurrentException()) title:"MQD startup"
                false
            )
            loaded
        )
    )
)

fn MayaQuadDraw_Start =
(
    global PolyToolsUI
    global PBo_Pickobject
    global MayaQuadDrawR6_Start

    local workMesh = if selection.count == 1 then selection[1] else undefined
    if not isValidNode workMesh or not (try (classOf workMesh.baseObject == Editable_Poly) catch (false)) then
    (
        messageBox "Select one Editable Poly work mesh, then run MQD again." title:"MQD"
        false
    )
    else
    (
        local targetSurface = try (PBo_Pickobject) catch (undefined)
        if not isValidNode targetSurface do
        (
            -- This is Autodesk PolyDraw's own Surface Pick command and shared target.
            try (PolyBoost.PolyDrawPickNode()) catch()
            targetSurface = try (PBo_Pickobject) catch (undefined)
        )

        if not isValidNode targetSurface then
        (
            messageBox "Use PolyDraw's Pick command to choose a drawing surface, then run MQD again." title:"MQD Surface Pick"
            false
        )
        else if targetSurface == workMesh then
        (
            messageBox "The work mesh and the picked drawing surface must be different objects." title:"MQD Surface Pick"
            false
        )
        else
        (
            local loaded = MayaQuadDraw_Load()
            if not loaded then false
            else
            (
                -- Core owns launch-state capture before it enters the MQD
                -- component/PolyDraw modes, and restores that state on exit.
                try (MayaQuadDrawR6_Start()) catch
                (
                    messageBox ("MQD could not start:\n\n" + getCurrentException()) title:"MQD"
                    false
                )
            )
        )
    )
)

fn MayaQuadDraw_Stop =
(
    global MayaQuadDrawR6
    global MayaQuadDrawR6_Stop
    global MayaQuadDrawUI_Close

    try (if MayaQuadDrawR6_Stop != undefined do MayaQuadDrawR6_Stop()) catch()
    try (if MayaQuadDrawUI_Close != undefined do MayaQuadDrawUI_Close()) catch()
    true
)

fn MayaQuadDraw_Toggle =
(
    global MayaQuadDrawR6
    local isActive = try (MayaQuadDrawR6 != undefined and MayaQuadDrawR6.active) catch (false)
    if isActive then MayaQuadDraw_Stop() else MayaQuadDraw_Start()
)

fn MayaQuadDraw_Settings =
(
    global MayaQuadDrawUI_Toggle
    if MayaQuadDraw_Load() then MayaQuadDrawUI_Toggle() else false
)

format "MQD Max 2024 action loader is ready.\n"
