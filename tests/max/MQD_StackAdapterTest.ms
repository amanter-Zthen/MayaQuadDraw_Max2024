/* Native interface adapter test. Load this file, then call setup(), context(),
   createFaces(), undoFace(), redoFace() in separate main-thread events.
   Leaves named fixtures. No scene reset, model import or pointer simulation. */
global MQDStackAdapterTest
struct MQDStackAdapterTestState
(
    target,
    meshes = #(),
    cycles = #(),
    checks = 0,
    failures = #(),
    rows = #(),
    savedPanel,
    savedEndResult,
    savedPick,
    savedDrawType,
    fn check label condition =
    (
        checks += 1
        append rows #(label,condition)
        if not condition do append failures label
        condition
    ),
    fn result = #(checks,failures.count,failures),
    fn liveFaces n = (polyop.getNumFaces n.baseObject)-(polyop.getDeadFaces n.baseObject).numberSet,
    fn setup allowedNodes:#() =
    (
        if maxFileName != "" or PBTrackGetToolActive() do throw "Unsaved idle test scene required"
        for node in objects where (findItem allowedNodes node)==0 do throw "Scene contains a node not owned by this test run"
        savedPanel = getCommandPanelTaskMode()
        savedEndResult = showEndResult
        savedPick = PBo_Pickobject
        savedDrawType = PolyToolsUI.PDDrawtype
        target = plane name:"MQD_AdapterTest_Target" length:40 width:40 lengthsegs:1 widthsegs:1
        for kind in #(#TurboSmooth,#OpenSubdiv) do
        (
            local n=plane name:("MQD_AdapterTest_"+(kind as string)) length:10 width:10 lengthsegs:2 widthsegs:2
            convertToPoly n
            append cycles (polyop.getFaceVerts n.baseObject 1)
            polyop.deleteFaces n.baseObject #{1} delIsoVerts:false
            local m=if kind==#TurboSmooth then TurboSmooth iterations:1 else OpenSubdiv iterations:1
            addModifier n m
            append meshes n
        )
        #(for n in meshes collect n.name)
    ),
    fn context =
    (
        for n in meshes do
        (
            for originalEntry in #(#base,#top) do for originalEnd in #(false,true) do
            (
                select n
                max modify mode
                local entry=if originalEntry==#base then n.baseObject else n.modifiers[1]
                modPanel.setCurrentObject entry node:n
                subObjectLevel=0
                showEndResult=originalEnd
                n.vertexTicks=false
                PBo_Pickobject=target
                local label=n.name+"/"+(originalEntry as string)+"/"+(originalEnd as string)
                local started=MayaQuadDraw_Start()
                check (label+" start") started
                if started do
                (
                    check (label+" base edit context") ((modPanel.getCurrentObject())==n.baseObject)
                    check (label+" final result on") showEndResult
                    check (label+" no evaluated vertex ticks") (not n.vertexTicks)
                    check (label+" low-poly counts") ((polyop.getNumVerts n.baseObject)==9 and matchPattern (MayaQuadDrawR6.countsText()) pattern:"V=9 *")
                    local query=globalVars.get #MQDNativeV16FilterStepBuildSourceIds
                    check (label+" native EPoly reachable") ((query n #(1,2,3,4,5,6,7,8,9))!=undefined)
                    check (label+" no automatic settings") (not MayaQuadDrawUI_IsOpen())
                    local evaluated=snapshotAsMesh n
                    check (label+" upper modifier evaluates") (evaluated.numverts>9 and n.modifiers[1].enabled)
                    MayaQuadDraw_Stop()
                    check (label+" entry restored") ((modPanel.getCurrentObject())==entry)
                    check (label+" display restored") (showEndResult==originalEnd)
                    check (label+" level and ticks restored") (subObjectLevel==0 and not n.vertexTicks)
                    check (label+" tracker ended") (not PBTrackGetToolActive())
                )
            )
        )
        result()
    ),
    fn createFace index =
    (
        local n=meshes[index]
        select n
        max modify mode
        modPanel.setCurrentObject n.baseObject node:n
        subObjectLevel=1
        showEndResult=true
        local countBefore=liveFaces n
        local vertexBefore=for i=1 to (polyop.getNumVerts n.baseObject) collect (polyop.getVert n.baseObject i)
        local evaluateBefore=snapshotAsMesh n
        local create=globalVars.get #MQDNativeV16CreateFaceSafe
        local face=create n cycles[index]
        check (n.name+" native face creation") (face!=undefined and liveFaces n==countBefore+1)
        local vertexAfter=for i=1 to (polyop.getNumVerts n.baseObject) collect (polyop.getVert n.baseObject i)
        check (n.name+" base vertices unchanged") ((vertexAfter as string)==(vertexBefore as string))
        local evaluateAfter=snapshotAsMesh n
        check (n.name+" upper topology refresh") (evaluateAfter.numfaces>evaluateBefore.numfaces and n.modifiers[1].enabled)
        result()
    ),
    fn undoFace index =
    (
        max undo
        check (meshes[index].name+" Undo base face") (liveFaces meshes[index]==3)
        check (meshes[index].name+" Undo keeps modifier") (meshes[index].modifiers.count==1 and meshes[index].modifiers[1].enabled)
        result()
    ),
    fn redoFace index =
    (
        max redo
        check (meshes[index].name+" Redo base face") (liveFaces meshes[index]==4)
        result()
    ),
    fn finish =
    (
        if MayaQuadDrawR6.active do MayaQuadDraw_Stop()
        subObjectLevel=0
        clearSelection()
        setCommandPanelTaskMode mode:savedPanel
        showEndResult=savedEndResult
        PBo_Pickobject=savedPick
        PolyToolsUI.PDDrawtype=savedDrawType
        result()
    )
)
MQDStackAdapterTest=MQDStackAdapterTestState()
