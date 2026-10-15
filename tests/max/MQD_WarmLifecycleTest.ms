/* Explicit test fixtures only. Caller supplies the work mesh and target.
   Measures warm entry/exit, not startup DLL load or sustained gesture latency. */
global MQDWarmLifecycleTest
struct MQDWarmLifecycleTestState
(
    rows=#(),
    failures=#(),
    timings=#(),
    fn check label condition =
    (
        append rows #(label,condition)
        if not condition do append failures label
        condition
    ),
    fn run n target =
    (
        if maxFileName!="" or not isValidNode n or not matchPattern n.name pattern:"MQD_*" do throw "Owned test fixture required"
        if MayaQuadDrawR6.active or PBTrackGetToolActive() or MayaQuadDrawUI_IsOpen() do throw "Idle MQD with settings closed required"
        select n
        max modify mode
        modPanel.setCurrentObject n.baseObject node:n
        subObjectLevel=0
        PBo_Pickobject=target
        local core=MayaQuadDrawR6
        local ui=MayaQuadDrawUIState
        for i=1 to 2 do
        (
            local t=timeStamp()
            local loaded=MayaQuadDraw_Load()
            local loadMs=timeStamp()-t
            t=timeStamp()
            local started=MayaQuadDraw_Start()
            local startMs=timeStamp()-t
            t=timeStamp()
            local stopped=MayaQuadDraw_Stop()
            local stopMs=timeStamp()-t
            append timings #(loadMs,startMs,stopMs)
            check "warm call succeeds" (loaded and started and stopped)
            check "core and settings resources retained" (core==MayaQuadDrawR6 and ui==MayaQuadDrawUIState)
            check "settings remain closed by default" (not MayaQuadDrawUI_IsOpen())
            check "drawing references released" (MayaQuadDrawR6.ownerNode==undefined and MayaQuadDrawR6.sessionBaseObject==undefined and not PBTrackGetToolActive())
        )
        MayaQuadDrawUI_Open()
        local floater=MayaQuadDrawUIFloater
        local position=floater.pos
        check "start with explicit settings" (MayaQuadDraw_Start())
        check "stop with explicit settings" (MayaQuadDraw_Stop())
        check "same settings window retained" (MayaQuadDrawUI_IsOpen() and floater==MayaQuadDrawUIFloater)
        check "settings position retained" (floater.pos==position)
        MayaQuadDrawUI_Close()
        check "explicit close still works" (not MayaQuadDrawUI_IsOpen())
        #(rows.count,failures.count,failures,timings)
    )
)
MQDWarmLifecycleTest=MQDWarmLifecycleTestState()
