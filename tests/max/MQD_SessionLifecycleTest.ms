/* Local candidate regression. Creates named fixtures only in an empty scene.
   Invoke phases separately through Max's main thread. No reset or Undo flush. */
global MQDSessionTest
struct MQDSessionTestState
(
    target,
    current,
    fixtures = #(),
    checks = 0,
    failures = #(),
    rows = #(),
    rememberedToken = 0,
    rememberedRefresh = 0,
    rememberedCount = 0,
    rememberedPosition = [0,0,0],
    fn check label condition =
    (
        checks += 1
        append rows #(label,condition)
        if not condition do append failures label
        condition
    ),
    fn result = #(checks,failures.count,failures),
    fn setup =
    (
        if objects.count != 0 or maxFileName != "" or PBTrackGetToolActive() do throw "Empty idle scene required"
        target=plane name:"MQD_SessionTest_Target" length:40 width:40 lengthsegs:1 widthsegs:1
        true
    ),
    fn fresh kind conversion:false fromTop:false =
    (
        if MayaQuadDrawR6.active or PBTrackGetToolActive() do throw "Previous test session still active"
        undo off (current=plane name:("MQD_SessionTest_"+((fixtures.count+1) as string)) length:20 width:20 lengthsegs:1 widthsegs:1)
        append fixtures current
        local n=current
        if conversion then
        (
            undo "MQD Session Convert To Poly" on (convertToPoly n)
            undo "MQD Session Add Modifier" on (addModifier n (if kind==#TurboSmooth then TurboSmooth iterations:1 else OpenSubdiv iterations:1))
        )
        else undo off
        (
            convertToPoly n
            polyop.deleteFaces n.baseObject #{1} delIsoVerts:false
            addModifier n (if kind==#TurboSmooth then TurboSmooth iterations:1 else OpenSubdiv iterations:1)
        )
        select n
        max modify mode
        modPanel.setCurrentObject n.baseObject node:n
        subObjectLevel=0
        showEndResult=true
        n.vertexTicks=false
        if fromTop do modPanel.setCurrentObject n.modifiers[1] node:n
        PBo_Pickobject=target
        check ((kind as string)+" start") (MayaQuadDraw_Start()==true)
        n.name
    ),
    fn abortDelegate route =
    (
        local label=(classOf current.modifiers[1] as string)+"/"+(route as string)
        local succeeded=true
        try
        (
            case route of
            (
                #build: MayaQuadDrawR6_BuildDelegate #mouseAbort false false false
                #move: MayaQuadDrawR6_MoveDelegate #mouseAbort false false false
                #border: MayaQuadDrawR6_BorderDelegate #mouseAbort false false false
                #optimizer: MayaQuadDrawR6_OptimizerDelegate #mouseAbort false false false
            )
        )
        catch (succeeded=false; append rows #("exception",getCurrentException()))
        check (label+" no exception") succeeded
        check (label+" wrapper stopped") (not MayaQuadDrawR6.active)
        check (label+" recognition stopped") (not MayaQuadDrawR1.active and not MayaQuadDrawR3.active and not MayaQuadDrawR3.candidateValid)
        check (label+" cleanup result") MayaQuadDrawR6.lastExitSucceeded
        -- Direct delegate tests do not execute the bridge's deferred native stop.
        PBEndTrack()
        result()
    ),
    fn undoConversion =
    (
        max undo
        max undo
        check "Conversion Undo restores Plane" (classOf current.baseObject==Plane)
        check "Stop succeeds after type change" (MayaQuadDraw_Stop()==true)
        check "No session after type change" (not MayaQuadDrawR6.active and not PBTrackGetToolActive() and not MayaQuadDrawR1.active and not MayaQuadDrawR3.active)
        result()
    ),
    fn redoConversion =
    (
        max redo
        max redo
        check "Conversion Redo restores EP" (classOf current.baseObject==Editable_Poly and current.modifiers.count==1)
        check "Redo does not reopen MQD" (not MayaQuadDrawR6.active and not PBTrackGetToolActive())
        result()
    ),
    fn badLogStop =
    (
        local oldPaths=#(MayaQuadDrawR6.logPath,MayaQuadDrawR1.logPath,MayaQuadDrawR3.logPath)
        local succeeded=false
        try
        (
            MayaQuadDrawR6.logPath=getDir #temp
            MayaQuadDrawR1.logPath=getDir #temp
            MayaQuadDrawR3.logPath=getDir #temp
            succeeded=MayaQuadDraw_Stop()
        )
        catch (append rows #("bad log exception",getCurrentException()))
        MayaQuadDrawR6.logPath=oldPaths[1]
        MayaQuadDrawR1.logPath=oldPaths[2]
        MayaQuadDrawR3.logPath=oldPaths[3]
        check "Log path failure does not block stop" succeeded
        check "Log failure leaves no session" (not MayaQuadDrawR6.active and not PBTrackGetToolActive() and not MayaQuadDrawR1.active and not MayaQuadDrawR3.active)
        check "Repeated stop is safe" (MayaQuadDraw_Stop()==true)
        result()
    ),
    fn remember =
    (
        rememberedToken=MayaQuadDrawR6.sessionToken
        rememberedRefresh=MayaQuadDrawR6.historyRefreshCount
        rememberedCount=polyop.getNumVerts current.baseObject
        rememberedPosition=polyop.getVert current.baseObject 1 node:current
        true
    ),
    fn seedStalePreview =
    (
        MayaQuadDrawR1.hoverIndex=99999
        MayaQuadDrawR3.candidateValid=true
        MayaQuadDrawR3.candidateVerts=#(99999,99998,99997,99996)
        MayaQuadDrawR3.visibleIds=#(99999)
        MayaQuadDrawR3.eligibleIds=#(99999)
        MayaQuadDrawR3.quadSourceIds=#(99999)
        true
    ),
    fn makePointEdit =
    (
        remember()
        undo "MQD Session Point" on (polyop.createVert current.baseObject [2,2,0] node:current)
        update current
        seedStalePreview()
        true
    ),
    fn makeMoveEdit =
    (
        remember()
        undo "MQD Session Move" on (polyop.setVert current.baseObject 1 (rememberedPosition+[1,0,0]) node:current)
        update current
        seedStalePreview()
        true
    ),
    fn assertContinuing label =
    (
        check (label+" active/tracker") (MayaQuadDrawR6.active and PBTrackGetToolActive())
        check (label+" session identity") (MayaQuadDrawR6.sessionToken==rememberedToken and rememberedToken!=0)
        check (label+" valid base context") (MayaQuadDrawR6.hasSessionContext())
        check (label+" stale caches empty") (MayaQuadDrawR1.hoverIndex!=99999 and not MayaQuadDrawR3.candidateValid and MayaQuadDrawR3.visibleIds.count==0 and MayaQuadDrawR3.eligibleIds.count==0 and MayaQuadDrawR3.quadSourceIds.count==0)
        check (label+" history settled") (not MayaQuadDrawR6.historyPending and MayaQuadDrawR6.historyRefreshCount>rememberedRefresh)
        result()
    ),
    fn assertStopped label =
    (
        check (label+" wrapper stopped") (not MayaQuadDrawR6.active and MayaQuadDrawR6.sessionToken==0)
        check (label+" tracker stopped") (not PBTrackGetToolActive())
        check (label+" references released") (MayaQuadDrawR6.ownerNode==undefined and MayaQuadDrawR6.sessionBaseObject==undefined and MayaQuadDrawR1.ownerNode==undefined and MayaQuadDrawR1.targetNode==undefined and MayaQuadDrawR3.candidateOwner==undefined)
        check (label+" exit success") MayaQuadDrawR6.lastExitSucceeded
        result()
    )
)
MQDSessionTest=MQDSessionTestState()
