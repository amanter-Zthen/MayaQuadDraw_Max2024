/* UI-only test. Run manually with MQD and its settings window closed.
   No scene objects, native plugins, trackers or modeling operations are started. */
(
    global MQD_UI_SelfTestQuiet
    global MQD_UI_SelfTestResult
    global MayaQuadDraw_Load
    global MayaQuadDrawR6
    global MayaQuadDrawUIState
    global MayaQuadDrawUIFloater
    global MayaQuadDrawUIPosition
    global MayaQuadDrawUI_IsOpen
    global MayaQuadDrawUI_Toggle
    global MayaQuadDrawUI_Close
    global MayaQuadDrawUI_ReadPosition
    global MayaQuadDrawUI_SavePosition

    local activeTool = try (MayaQuadDrawR6 != undefined and MayaQuadDrawR6.active) catch (false)
    local activeTracker = try (PBTrackGetToolActive()) catch (false)
    local openSettings = try (MayaQuadDrawUI_IsOpen != undefined and MayaQuadDrawUI_IsOpen()) catch (false)
    if activeTool or activeTracker or openSettings then
        messageBox "请先退出 MQD/PolyDraw 并关闭 MQD 参数窗，再运行界面自检。" title:"MQD 界面自检"
    else
    (
        local checks = 0
        local failures = #()
        fn checkValue label actual failures =
        (
            format "MQD UI %: %\n" label actual
            if not actual do append failures label
        )
        local savedSelection = for n in selection collect (getHandleByAnim n)
        local savedObjectCount = objects.count
        local savedPanel = getCommandPanelTaskMode()
        local savedLevel = subObjectLevel
        local savedEndResult = showEndResult
        local savedPos = undefined
        local savedRadius = undefined
        try
        (
            if MayaQuadDraw_Load == undefined do fileIn ((getDir #userStartupScripts) + "\\MayaQuadDraw_Max2024_Startup.ms") quiet:true
            if not MayaQuadDraw_Load() do throw "Runtime load failed"
            savedPos = MayaQuadDrawUIPosition
            savedRadius = MayaQuadDrawUIState.relaxRadius
            checks += 1; checkValue "load keeps settings closed" (not MayaQuadDrawUI_IsOpen()) failures
            MayaQuadDrawUI_Toggle()
            checks += 1; checkValue "toggle opens" (MayaQuadDrawUI_IsOpen()) failures
            local firstWindow = MayaQuadDrawUIFloater
            local testPos = firstWindow.pos + [24,24]
            firstWindow.pos = testPos
            testPos = firstWindow.pos
            MayaQuadDrawUI_Toggle()
            checks += 1; checkValue "toggle closes" (not MayaQuadDrawUI_IsOpen()) failures
            checks += 1; checkValue "position persisted" ((distance (MayaQuadDrawUI_ReadPosition()) testPos) < 2) failures
            MayaQuadDrawUI_Toggle()
            checks += 1; checkValue "position restored" ((distance MayaQuadDrawUIFloater.pos testPos) < 2) failures
            -- Native window close exercises the same rollout close handler as X.
            closeRolloutFloater MayaQuadDrawUIFloater
            checks += 1; checkValue "window close clears handle" (MayaQuadDrawUIFloater == undefined) failures
            MayaQuadDrawUI_Toggle()
            checks += 1; checkValue "reopen after X" (MayaQuadDrawUI_IsOpen()) failures
            checks += 1; checkValue "parameter state retained" (MayaQuadDrawUIState.relaxRadius == savedRadius) failures
        )
        catch (append failures (getCurrentException()))

        try (if MayaQuadDrawUI_Close != undefined do MayaQuadDrawUI_Close()) catch()
        if savedPos != undefined do
        (
            MayaQuadDrawUIPosition = savedPos
            MayaQuadDrawUI_SavePosition()
        )
        checks += 1; checkValue "scene object count unchanged" (objects.count == savedObjectCount) failures
        checks += 1; checkValue "selection unchanged" (((for n in selection collect (getHandleByAnim n)) as string) == (savedSelection as string)) failures
        checks += 1; checkValue "panel and level unchanged" ((getCommandPanelTaskMode()) == savedPanel and subObjectLevel == savedLevel) failures
        checks += 1; checkValue "end result unchanged" (showEndResult == savedEndResult) failures
        checks += 1; checkValue "MQD remains inactive" (try (MayaQuadDrawR6 != undefined and not MayaQuadDrawR6.active) catch (false)) failures
        format "MQD UI checks=% failures=% details=%\n" checks failures.count failures
        MQD_UI_SelfTestResult = #(checks,failures.count,failures)
        if MQD_UI_SelfTestQuiet != true do messageBox ("checks=" + (checks as string) + " failures=" + (failures.count as string) + "\n\n详细结果在 MAXScript 侦听器中。\n这项测试只检查界面，不验证细分修改器。") title:"MQD 界面自检"
    )
)
