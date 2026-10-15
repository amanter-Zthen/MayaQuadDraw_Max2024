/* UI callback test on an explicitly supplied MQD test fixture. No geometry
   writes, history traversal, key simulation, scene loading or scene reset.
   Physical Tab routing and input-field traversal require manual acceptance. */
global MQDSettingsTabTest
struct MQDSettingsTabTestState
(
    checks=0, failures=#(),
    fn check label condition =
    (
        checks+=1
        if not condition do append failures label
        format "MQD Tab %: %\n" label condition
        condition
    ),
    fn result = #(checks,failures.count,failures),
    fn meshSignature n =
    (
        local b=n.baseObject
        with printAllElements on
        (
            #(n.transform,
              (for i=1 to polyOp.getNumVerts b collect polyOp.getVert b i),
              (for i=1 to polyOp.getNumFaces b collect polyOp.getFaceVerts b i),
              (for i=1 to polyOp.getNumEdges b collect polyOp.getEdgeVerts b i)) as string
        )
    ),
    fn run n =
    (
        if not isValidNode n or not matchPattern n.name pattern:"MQD_TabTrial_*" do throw "Explicit Tab test fixture required"
        if MayaQuadDrawInstalledRuntimeVersion != "1.1.0-max2024" do throw "MQD 1.1.0 runtime required"
        if not MayaQuadDrawR6.active or MayaQuadDrawR6.ownerNode != n or not PBTrackGetToolActive() do throw "Active test session required"
        if MayaQuadDrawR6.historyPending or MayaQuadDrawR6.contextPending do throw "Wait for host context to settle"
        if theHold.Holding() or theHold.IsSuspended() do throw "Idle native Undo context required"
        local token=MayaQuadDrawR6.sessionToken
        local initialOpen=MayaQuadDrawUI_IsOpen()
        local geometry=meshSignature n
        local undoNames=theHold.getUndoNames() as string
        local redoNames=theHold.getRedoNames() as string
        local puts=theHold.GetGlobalPutCount()
        local savedSelection=selection as array
        local savedCount=objects.count
        local savedLevel=subObjectLevel
        local savedEnd=showEndResult
        local savedStack=modPanel.getCurrentObject()
        local savedParameters=#(MayaQuadDrawUIState.relaxRadius,MayaQuadDrawUIState.relaxFocus,MayaQuadDrawUIState.relaxStrength,MayaQuadDrawUIState.weldDistance)
        local hookFn=globalVars.get #MQDNativeV16SettingsTabHookActive
        try
        (
            check "native session hook active" (hookFn != undefined and hookFn())
            check "stale token rejected" (not MayaQuadDrawR6.onSettingsTab (token+1))
            check "stale request preserves window" (MayaQuadDrawUI_IsOpen()==initialOpen)
            for i=1 to 4 do
            (
                check ("toggle callback "+(i as string)) (MayaQuadDrawR6.onSettingsTab token)
                check ("window state "+(i as string)) (MayaQuadDrawUI_IsOpen()==(if (mod i 2)==1 then not initialOpen else initialOpen))
            )
            local suspendedResult=undefined
            undo off (suspendedResult=MayaQuadDrawR6.onSettingsTab token)
            check "suspended history leaves UI untouched" (suspendedResult==false and MayaQuadDrawUI_IsOpen()==initialOpen)
        )
        catch (append failures (getCurrentException()))
        if MayaQuadDrawUI_IsOpen()!=initialOpen do MayaQuadDrawUI_Toggle()
        check "geometry identical" ((meshSignature n)==geometry)
        check "Undo labels identical" ((theHold.getUndoNames() as string)==undoNames)
        check "Redo labels identical" ((theHold.getRedoNames() as string)==redoNames)
        check "no native Restore objects added" (theHold.GetGlobalPutCount()==puts)
        check "same drawing session" (MayaQuadDrawR6.active and MayaQuadDrawR6.sessionToken==token and PBTrackGetToolActive())
        check "same native command" (MayaQuadDrawR6.ownsNativeCommand())
        check "same selection" (((selection as array) as string)==(savedSelection as string))
        check "same scene object count" (objects.count==savedCount)
        check "same stack and end-result state" (modPanel.getCurrentObject()==savedStack and subObjectLevel==savedLevel and showEndResult==savedEnd)
        check "same settings values" ((#(MayaQuadDrawUIState.relaxRadius,MayaQuadDrawUIState.relaxFocus,MayaQuadDrawUIState.relaxStrength,MayaQuadDrawUIState.weldDistance) as string)==(savedParameters as string))
        check "window restored" (MayaQuadDrawUI_IsOpen()==initialOpen)
        result()
    ),
    fn checkStopped oldToken =
    (
        if MayaQuadDrawR6.active or PBTrackGetToolActive() do throw "Exit MQD first"
        local initialOpen=MayaQuadDrawUI_IsOpen()
        local hookFn=globalVars.get #MQDNativeV16SettingsTabHookActive
        check "native Tab hook inactive after exit" (not hookFn())
        check "exited callback rejected" (not MayaQuadDrawR6.onSettingsTab oldToken)
        check "exit request leaves window unchanged" (MayaQuadDrawUI_IsOpen()==initialOpen)
        result()
    )
)
MQDSettingsTabTest=MQDSettingsTabTestState()
