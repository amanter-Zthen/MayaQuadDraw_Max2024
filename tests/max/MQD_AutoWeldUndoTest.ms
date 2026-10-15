/* Additive fixtures only. No scene reset, no history flush, no pointer simulation.
   Invoke each phase separately on Max's main thread. Existing nodes are snapshotted
   and checked; Undo/Redo is allowed only when our expected label is at the top. */
global MQDWeldUndoTest
struct MQDWeldUndoTestState
(
    fixtures=#(), originalNodes=#(), originalStates=#(),
    current, original, moved, welded, caseLabel="", moveLabel="",
    checks=0, failures=#(), rows=#(), lastResult,
    fn check label condition =
    (
        checks+=1
        append rows #(label,condition)
        if not condition do append failures label
        condition
    ),
    fn same a b =
    (
        if classOf a != classOf b then false
        else if classOf a == Array then
        (
            if a.count != b.count then false
            else
            (
                local ok=true
                for i=1 to a.count while ok do ok=same a[i] b[i]
                ok
            )
        )
        else if classOf a == Point3 then (distance a b)<0.000001
        else a==b
    ),
    fn snapshot n =
    (
        local b=n.baseObject
        if classOf b != Editable_Poly then #((classOf b) as string,n.transform)
        else
        (
            local maps=#()
            for c in #(0,1) where polyop.getMapSupport b c do
                append maps #(c,for i=1 to polyop.getNumMapVerts b c collect polyop.getMapVert b c i,
                    for i=1 to polyop.getNumMapFaces b c collect polyop.getMapFace b c i)
            #((for i=1 to polyop.getNumVerts b collect polyop.getVert b i),
              (for i=1 to polyop.getNumFaces b collect #(polyop.getFaceVerts b i,polyop.getFaceMatID b i,polyop.getFaceSmoothGroup b i)),
              (for i=1 to polyop.getNumEdges b collect polyop.getEdgeVerts b i),
              polyop.getDeadVerts b,polyop.getDeadFaces b,maps)
        )
    ),
    fn holdState = #(theHold.Holding(),theHold.IsSuspended(),theHold.GetBeginDepth(),theHold.SuperLevel(),theHold.GetGlobalPutCount()),
    fn idle = not theHold.Holding() and not theHold.IsSuspended() and theHold.GetBeginDepth()==0 and theHold.SuperLevel()==0,
    fn result = #(checks,failures.count,failures),
    fn setup =
    (
        if MayaQuadDrawR6.active or PBTrackGetToolActive() or not idle() do throw "Idle host required"
        originalNodes=for n in objects collect n
        originalStates=for n in originalNodes collect snapshot n
        true
    ),
    fn checkOriginals =
    (
        local ok=true
        for i=1 to originalNodes.count do
            if not (isValidNode originalNodes[i]) or not (same (snapshot originalNodes[i]) originalStates[i]) do ok=false
        check "Original scene geometry unchanged" ok
    ),
    fn fresh kind sourceId targetId =
    (
        if MayaQuadDrawR6.active or PBTrackGetToolActive() or not idle() do throw "Idle host required"
        caseLabel=(kind as string)+"/"+(sourceId as string)+"->"+(targetId as string)+"/"+((fixtures.count+1) as string)
        moveLabel="MQD WeldTest Move "+caseLabel
        undo off
        (
            current=plane name:(uniqueName "MQD_WeldTest_") length:12 width:12 lengthsegs:3 widthsegs:3
            convertToPoly current
            current.pos=[1000+fixtures.count*20,0,0]
            if kind==#TurboSmooth do addModifier current (TurboSmooth iterations:1)
            if kind==#OpenSubdiv do addModifier current (OpenSubdiv iterations:1)
            if kind==#Transformed do current.transform=matrix3 [2,0,0] [0,0.5,0] [0,0,1.5] current.pos
            current.isHidden=true
        )
        append fixtures current
        original=snapshot current
        undo moveLabel on
        (
            polyop.setVert current.baseObject sourceId ((polyop.getVert current.baseObject targetId)+[0.15,0.1,0])
            update current
        )
        moved=snapshot current
        check (caseLabel+" move changes geometry") (not (same original moved))
        #(current.name,holdState())
    ),
    fn probeNativeWeld sourceId targetId outsideUndoOff:false =
    (
        local n=current
        local puts=theHold.GetGlobalPutCount()
        local before=holdState()
        fn perform n sourceId targetId =
        (
            theHold.Begin()
            try
            (
                polyop.weldVerts n.baseObject sourceId targetId (polyop.getVert n.baseObject targetId)
                update n
                theHold.Accept "MQD Probe Weld"
            )
            catch
            (
                if theHold.Holding() do theHold.Cancel()
                throw()
            )
        )
        if outsideUndoOff then (undo off (perform n sourceId targetId)) else perform n sourceId targetId
        welded=snapshot n
        append rows #(caseLabel,"native weld probe",outsideUndoOff,before,holdState())
        check (caseLabel+" native weld count") (welded[1].count==moved[1].count-1)
        check (caseLabel+" native records registered") (theHold.GetGlobalPutCount()>puts)
        check (caseLabel+" native hold closed") (idle())
        result()
    ),
    fn candidateWeld sourceId targetId =
    (
        MayaQuadDrawR6.ownerNode=current
        lastResult=MayaQuadDrawR6.commitAutoWeldTarget sourceId targetId 1.0
        welded=snapshot current
        append rows #(caseLabel,"candidate weld",lastResult,MayaQuadDrawR6.lastWeldUndoTrace)
        check (caseLabel+" candidate committed") lastResult[1]
        check (caseLabel+" candidate count") (welded[1].count==moved[1].count-1)
        check (caseLabel+" hold closed") (idle())
        result()
    ),
    fn undoWeld label =
    (
        local names=theHold.getUndoNames()
        if names.count==0 or names[1]!=label do throw ("Unexpected Undo top; stopped: "+(names as string))
        max undo
        if not (check (caseLabel+" Undo weld EXACT moved state incl indices/maps") (same (snapshot current) moved)) do throw "Weld undo mismatch; stopped"
        check (caseLabel+" still inactive after Undo weld") (not MayaQuadDrawR6.active and not PBTrackGetToolActive())
        checkOriginals()
        result()
    ),
    fn undoMove =
    (
        local names=theHold.getUndoNames()
        if names.count==0 or names[1]!=moveLabel do throw "Unexpected Move Undo top"
        max undo
        if not (check (caseLabel+" Undo move EXACT original") (same (snapshot current) original)) do throw "Move undo mismatch; stopped"
        result()
    ),
    fn redoMove =
    (
        local names=theHold.getRedoNames()
        if names.count==0 or names[1]!=moveLabel do throw "Unexpected Move Redo top"
        max redo
        if not (check (caseLabel+" Redo move EXACT moved") (same (snapshot current) moved)) do throw "Move redo mismatch; stopped"
        result()
    ),
    fn redoWeld label =
    (
        local names=theHold.getRedoNames()
        if names.count==0 or names[1]!=label do throw "Unexpected Weld Redo top"
        max redo
        if not (check (caseLabel+" Redo weld EXACT welded") (same (snapshot current) welded)) do throw "Weld redo mismatch; stopped"
        check (caseLabel+" hold still closed") (idle())
        checkOriginals()
        result()
    ),
    fn guards =
    (
        MayaQuadDrawR6.ownerNode=current
        local before=snapshot current
        local names=theHold.getUndoNames()
        local r
        undo off (r=MayaQuadDrawR6.commitAutoWeldTarget 1 2 1.0)
        check "Suspended Undo refuses weld" (not r[1] and same (snapshot current) before)
        check "Suspended Undo creates no record" (same names (theHold.getUndoNames()))
        undo "MQD WeldTest foreign record" on
        (
            local depth=theHold.GetBeginDepth()
            r=MayaQuadDrawR6.commitAutoWeldTarget 1 2 1.0
            check "Foreign Hold preserved" (not r[1] and theHold.Holding() and theHold.GetBeginDepth()==depth and same (snapshot current) before)
        )
        check "Foreign empty Hold creates no record" (same names (theHold.getUndoNames()))
        r=MayaQuadDrawR6.commitAutoWeldTarget 1 1 1.0
        check "Self pair refused without mutation" (not r[1] and same (snapshot current) before)
        r=MayaQuadDrawR6.commitAutoWeldTarget 0 2 1.0
        check "Invalid index refused without mutation" (not r[1] and same (snapshot current) before)
        check "Rejected indices create no record" (same names (theHold.getUndoNames()))
        check "Guards leave native Undo idle" (idle())
        result()
    ),
    fn rejectedClosedWeld =
    (
        local n
        undo off (n=box name:(uniqueName "MQD_WeldTest_Closed_") length:10 width:10 height:10; convertToPoly n; n.pos=[1400,0,0]; n.isHidden=true)
        append fixtures n
        local before=snapshot n
        local names=theHold.getUndoNames()
        MayaQuadDrawR6.ownerNode=n
        local r=MayaQuadDrawR6.commitAutoWeldTarget 1 7 1.0
        append rows #("native rejects internal pair",r)
        check "Internal weld rejected" (not r[1])
        check "Rejected weld restores exact geometry" (same (snapshot n) before)
        check "Rejected weld creates no Undo record" (same names (theHold.getUndoNames()))
        check "Rejected weld leaves Hold idle" (idle())
        result()
    ),
    fn startContext =
    (
        select current
        max modify mode
        modPanel.setCurrentObject current.baseObject node:current
        subObjectLevel=0
        PBo_Pickobject=originalNodes[1]
        check (caseLabel+" MQD start") (MayaQuadDraw_Start()==true)
        check (caseLabel+" session active") (MayaQuadDrawR6.active and PBTrackGetToolActive())
        result()
    ),
    fn contextUndoWeld =
    (
        local names=theHold.getUndoNames()
        if names.count==0 or names[1]!="MQD Auto Weld" do throw "Unexpected context Undo top"
        max undo
        check (caseLabel+" context Undo exact moved state") (same (snapshot current) moved)
        result()
    ),
    fn assertContext expectedActive =
    (
        check (caseLabel+" context active state "+(expectedActive as string)) (MayaQuadDrawR6.active==expectedActive and PBTrackGetToolActive()==expectedActive)
        check (caseLabel+" context geometry unchanged") (same (snapshot current) moved)
        check (caseLabel+" context Hold idle") (idle())
        checkOriginals()
        result()
    ),
    fn writeResult path =
    (
        local s=createFile path
        format "MQD AutoWeld native-record regression\nchecks=% failures=%\n" checks failures.count to:s
        format "Scope: direct native geometry APIs and candidate weld transaction; not real mouse/PolyDraw Move gesture coverage.\n" to:s
        for row in rows do format "%\n" row to:s
        close s
        result()
    )
)
MQDWeldUndoTest=MQDWeldUndoTestState()
