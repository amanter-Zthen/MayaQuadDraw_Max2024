/*
Maya Quad Draw 1.1 for 3ds Max 2024.

    V16 owns the PBStartTrack channel, preserves the V15 input ABI, and adds
    Maya-style target-surface visibility filtering for hover and possible faces.
    Motion remains a click until it crosses a DPI-scaled six-pixel threshold.
    - Surface-blank click: native PolyBPolyDrawBuild creates one point.
    - Vertex drag: real mouseMove/mousePoint events are forwarded to native Move.
    - Shift + surface-blank click: ordered node-local EPoly creation with Undo.
    - Shift + boundary-edge drag: real mouseMove/mousePoint events are forwarded
      to Autodesk PolyBPolyDrawBorder.
    - Ctrl + Shift + boundary-edge drag: native Border extends the complete
      open boundary loop and creates a ring of new faces.
    - Ctrl + click over a connected quad strip: Autodesk Swift Loop previews
      and inserts one edge loop without leaving the unified tracker.
    - Ctrl + Alt + click vertex/edge/face: context delete with isolated-vertex
      cleanup. Vertex deletion also deletes every incident face.
    - Shift-hover inside a closed three-edge boundary hole: purple triangle
      preview; Shift-click fills it through the same guarded native face entry.
    - Three loose dots never form a triangle candidate.
    - Shift + boundary-edge click: blocked (no drag, no extension).
    - Shift + surface-blank drag: blocked (not a click, not an edge drag).
    - Vertex release near another visible vertex: weld the dragged vertex to it.
    - Edge drag: call native Drag with its Shift behavior internally.
    - Face drag: call native Drag with its Ctrl behavior internally.
    - Preview and commit share one Maya-style topology gate, preventing folded,
      overlapping, crossing, diagonal-spanning and non-manifold candidates.
    - Shift-drag beginning on an internal component runs SDK-native Relax in
      this same PBStartTrack session. No Painter handoff or tool switch occurs.
    - The native viewport supplies the cursor coordinates, covered internal
      vertices are equal-weighted, boundary vertices remain locked, and each
      step is projected back to the picked surface.
*/

global MayaQuadDrawR1
global MayaQuadDrawR3
global MayaQuadDrawR6
global MayaQuadDrawR6_DrawCallback
global MayaQuadDrawR6_BuildDelegate
global MayaQuadDrawR6_MoveDelegate
global MayaQuadDrawR6_BorderDelegate
global MayaQuadDrawR6_OptimizerDelegate
global MayaQuadDrawR6_Start
global MayaQuadDrawR6_Stop
global PolyToolsUI
global PBo_Pickobject
global PolyToolsModeling
global PolyBPolyDrawBuild
global PolyBPolyDrawMove
global PolyBPolyDrawBorder
global PolyBPolyDrawSwiftLoop
global MayaQuadDrawUIState
global MayaQuadDrawUIFloater
global MayaQuadDrawUIRollout
global MayaQuadDrawUI_Open
global MayaQuadDrawUI_Close
global MayaQuadDrawUI_IsOpen
global MayaQuadDrawUI_Toggle
global MayaQuadDrawUIPosition
global MayaQuadDrawUI_ReadPosition
global MayaQuadDrawUI_SavePosition
global MayaQuadDrawR16_PainterActivate
global MayaQuadDrawR16_PainterResume
global MayaQuadDrawRootPath
global MayaQuadDrawInstalledRuntimeVersion

MayaQuadDrawInstalledRuntimeVersion = "1.1.0-max2024"

try (if MayaQuadDrawR6 != undefined and MayaQuadDrawR6.active do MayaQuadDrawR6.stopManual()) catch()

try (unregisterRedrawViewsCallback MayaQuadDrawR6_DrawCallback) catch()

fileIn (MayaQuadDrawRootPath + "runtime\\MayaQuadDraw_CandidatePreview.ms")

struct MayaQuadDrawUIStateStruct
(
    relaxRadius = 20.0,
    relaxFocus = 50.0,
    relaxStrength = 1.0,
    weldDistance = 10.0,
    suppressEvents = false,

    fn nativeWeldDistance =
    (
        try (PolyToolsUI.PDDistance as float) catch (weldDistance)
    ),

    fn writeNativeWeldDistance value =
    (
        weldDistance = value
        local wroteValue = false
        try
        (
            PolyToolsUI.PDDistance = value
            PolyToolsUI.PolyDrawSettings()
            wroteValue = true
        )
        catch()
        wroteValue
    ),

    fn syncWeldFromNative spinnerControl:undefined =
    (
        if suppressEvents then false
        else
        (
            local nativeValue = nativeWeldDistance()
            if abs (nativeValue-weldDistance) > 0.0001 do
            (
                suppressEvents = true
                weldDistance = nativeValue
                if spinnerControl != undefined do spinnerControl.value = weldDistance
                suppressEvents = false
            )
            true
        )
    )
)

try
(
    if MayaQuadDrawUIFloater != undefined do
    (
        try (if MayaQuadDrawUIFloater.dialogBar do cui.UnRegisterDialogBar MayaQuadDrawUIFloater) catch()
        try (closeRolloutFloater MayaQuadDrawUIFloater) catch()
    )
)
catch()
MayaQuadDrawUIFloater = undefined
MayaQuadDrawUIState = MayaQuadDrawUIStateStruct()

fn MayaQuadDrawUI_ReadPosition =
(
    -- Only UI coordinates are stored here; no scene state or executable text.
    local positionValue = [32,160]
    local settingsPath = (getDir #plugcfg) + "\\MayaQuadDraw_Max2024_UI.ini"
    try
    (
        local xText = getINISetting settingsPath "Window" "X"
        local yText = getINISetting settingsPath "Window" "Y"
        if xText != "" and yText != "" do positionValue = [xText as integer,yText as integer]
    )
    catch()
    positionValue
)

fn MayaQuadDrawUI_SavePosition =
(
    if MayaQuadDrawUIPosition == undefined then false
    else
    (
        local settingsPath = (getDir #plugcfg) + "\\MayaQuadDraw_Max2024_UI.ini"
        try
        (
            setINISetting settingsPath "Window" "X" ((MayaQuadDrawUIPosition.x as integer) as string)
            setINISetting settingsPath "Window" "Y" ((MayaQuadDrawUIPosition.y as integer) as string)
            true
        )
        catch (false)
    )
)

fn MayaQuadDrawUI_IsOpen =
(
    try (MayaQuadDrawUIFloater != undefined and MayaQuadDrawUIFloater.open) catch (false)
)

if MayaQuadDrawUIPosition == undefined do MayaQuadDrawUIPosition = MayaQuadDrawUI_ReadPosition()

rollout MayaQuadDrawUIRollout "参数" width:196 height:118
(
    spinner radiusSpinner "松弛半径:" range:[1.0,500.0,20.0] type:#float scale:0.5 fieldWidth:70 pos:[10,8]
    spinner focusSpinner "松弛焦距:" range:[0,100,50] type:#integer scale:1 fieldWidth:70 pos:[10,35]
    spinner strengthSpinner "松弛强度:" range:[0.0,1.0,1.0] type:#float scale:0.01 fieldWidth:70 pos:[10,62]
    spinner weldSpinner "自动焊接:" range:[0.1,1000.0,10.0] type:#float scale:0.1 fieldWidth:70 pos:[10,89]
    timer nativeSyncTimer interval:350 active:false

    on MayaQuadDrawUIRollout open do
    (
        MayaQuadDrawUIState.suppressEvents = true
        MayaQuadDrawUIState.weldDistance = MayaQuadDrawUIState.nativeWeldDistance()
        radiusSpinner.value = MayaQuadDrawUIState.relaxRadius
        focusSpinner.value = MayaQuadDrawUIState.relaxFocus
        strengthSpinner.value = MayaQuadDrawUIState.relaxStrength
        weldSpinner.value = MayaQuadDrawUIState.weldDistance
        MayaQuadDrawUIState.suppressEvents = false
        nativeSyncTimer.active = true
    )

    on radiusSpinner changed value do if not MayaQuadDrawUIState.suppressEvents do MayaQuadDrawUIState.relaxRadius = value
    on focusSpinner changed value do if not MayaQuadDrawUIState.suppressEvents do MayaQuadDrawUIState.relaxFocus = value
    on strengthSpinner changed value do if not MayaQuadDrawUIState.suppressEvents do MayaQuadDrawUIState.relaxStrength = value
    on weldSpinner changed value do if not MayaQuadDrawUIState.suppressEvents do MayaQuadDrawUIState.writeNativeWeldDistance value
    on nativeSyncTimer tick do MayaQuadDrawUIState.syncWeldFromNative spinnerControl:weldSpinner
    on MayaQuadDrawUIRollout moved positionValue do MayaQuadDrawUIPosition = positionValue
    on MayaQuadDrawUIRollout close do
    (
        nativeSyncTimer.active = false
        MayaQuadDrawUI_SavePosition()
        MayaQuadDrawUIFloater = undefined
    )
)

fn MayaQuadDrawUI_Close =
(
    if MayaQuadDrawUI_IsOpen() do try (MayaQuadDrawUIPosition = MayaQuadDrawUIFloater.pos) catch()
    MayaQuadDrawUI_SavePosition()
    try (if MayaQuadDrawUIFloater != undefined and MayaQuadDrawUIFloater.dialogBar do cui.UnRegisterDialogBar MayaQuadDrawUIFloater) catch()
    try (if MayaQuadDrawUIFloater != undefined do closeRolloutFloater MayaQuadDrawUIFloater) catch()
    MayaQuadDrawUIFloater = undefined
    true
)

fn MayaQuadDrawUI_Open =
(
    if not MayaQuadDrawUI_IsOpen() then
    (
        local windowPos = MayaQuadDrawUIPosition
        -- Explicit x/y matches the Max 2024 host probe (older docs reverse
        -- these positional argument labels). Max also brings
        -- off-screen floaters back into view after monitor-layout changes.
        MayaQuadDrawUIFloater = newRolloutFloater "MQD 参数设置" 202 148 (windowPos.x as integer) (windowPos.y as integer)
        addRollout MayaQuadDrawUIRollout MayaQuadDrawUIFloater
        MayaQuadDrawUIPosition = MayaQuadDrawUIFloater.pos
    )
    true
)

fn MayaQuadDrawUI_Toggle =
(
    if MayaQuadDrawUI_IsOpen() then MayaQuadDrawUI_Close() else MayaQuadDrawUI_Open()
)

struct MayaQuadDrawR6State
(
    active = false,
    ownerNode = undefined,
    targetNode = undefined,
    borderGestureActive = false,
    borderLoopGesture = false,
    borderStartEdge = 0,
    borderMoveEvents = 0,
    borderBeforeVerts = 0,
    borderBeforeEdges = 0,
    borderBeforeFaces = 0,
    relaxGestureActive = false,
    relaxReleasePending = false,
    painterHandoffPending = false,
    painterHandoffInProgress = false,
    painterSessionOwned = false,
    painterExitRequested = false,
    relaxStartFace = 0,
    relaxMoveEvents = 0,
    relaxChangedSteps = 0,
    relaxStrokeCommits = 0,
    moveGestureActive = false,
    moveStartVertex = 0,
    moveStartLevel = #none,
    moveStartIndex = 0,
    moveAffectedVerts = #{},
    moveMoveEvents = 0,
    moveBeforeVerts = 0,
    moveBeforeEdges = 0,
    moveBeforeFaces = 0,
    moveStartPosition = [0,0,0],
    autoWeld = true,
    weldDistance = 10.0,
    distanceType = 1,
    autoWeldCommits = 0,
    lastWeldTarget = 0,
    lastWeldUndoTrace = #(),
    pointCommits = 0,
    moveCommits = 0,
    edgeMoveCommits = 0,
    faceMoveCommits = 0,
    recoveredPointClicks = 0,
    recoveredFaceClicks = 0,
    directFaceCommits = 0,
    triangleFillCommits = 0,
    borderCommits = 0,
    loopExtensionCommits = 0,
    swiftLoopCommits = 0,
    swiftLoopSessionArmed = false,
    swiftLoopPreviewActive = false,
    swiftLoopHandoffs = 0,
    vertexDeleteCommits = 0,
    edgeDeleteCommits = 0,
    faceDeleteCommits = 0,
    lastFreeHoverLevel = #none,
    lastFreeHoverIndex = 0,
    lastFreePoint = [0,0],
    lastFreeTick = 0,
    statusText = "Not started",
    trackerExpected = false,
    exitInProgress = false,
    lastExitSucceeded = true,
    lastExitErrors = #(),
    lastExitReason = "",
    sessionToken = 0,
    sessionBaseObject = undefined,
    historyPending = false,
    contextPending = false,
    historyRefreshCount = 0,
    contextCheckCount = 0,
    launchStateCaptured = false,
    savedSelection = #(),
    savedCommandPanelMode = undefined,
    savedSubObjectLevel = undefined,
    savedStackObject = undefined,
    savedShowEndResult = undefined,
    savedOwnerVertexTicks = undefined,
    savedPDDrawtype = undefined,
    savedPDAutoWeld = undefined,
    savedPickObject = undefined,
    savedPDTool = 0,
    pluginPath = MayaQuadDrawRootPath + "plugins\\MayaQuadDrawNativeBridge_v16.dlx",
    internalRelaxPluginPath = MayaQuadDrawRootPath + "plugins\\MayaQuadDrawInternalRelax_v20.dlx",
    logPath = MayaQuadDrawRootPath + "logs\\MayaQuadDraw.log",

    -- MAXScript binds struct functions in declaration order. These members
    -- are called by earlier handlers and must be visible when those compile.
    fn abortSession eventValue shiftValue ctrlValue altValue = false,
    fn finishRelaxGesture cancelValue reasonText = false,
    fn resumeAfterPainter = false,
    fn stopManual = false,
    fn completeExit reasonText endNativeTrack:true restoreContext:true = false,

    fn appendLog textValue =
    (
        local stream = undefined
        local written = false
        try
        (
            stream = openFile logPath mode:"a"
            if stream != undefined do
            (
                format "%\r\n" textValue to:stream
                written = true
            )
        )
        catch()
        if stream != undefined do try (close stream) catch()
        written
    ),

    fn initializeLog =
    (
        local newFile = not doesFileExist logPath
        local stream = if newFile then createFile logPath else openFile logPath mode:"a"
        if newFile do
        (
            format "MQD R20 SDK PAINT DEFORM DENSE-STROKE RELAX PROBE\r\n" to:stream
            format "R9 preserved | Shift hover dot/open edge/blank selects possible face\r\n" to:stream
            format "native Drag mapping: vertex=Normal edge=Shift polygon=Ctrl\r\n" to:stream
            format "Ctrl+Alt click deletes hovered vertex/edge/face; Ctrl+Shift boundary drag extends a full loop.\r\n" to:stream
            format "Ctrl+click embeds Autodesk Swift Loop and inserts at the cursor position.\r\n" to:stream
            format "Shift-hover previews a closed triangle hole in purple; Shift-click fills it.\r\n" to:stream
            format "native intent threshold=6 logical pixels scaled by viewport DPI; R6 recovery remains emergency-only\r\n" to:stream
        )
        format "\r\n--- NEW R20 SDK PAINT DEFORM DENSE-STROKE SESSION ---\r\n" to:stream
        close stream
        true
    ),

    fn countsText =
    (
        if not isValidNode ownerNode then "V=<invalid> E=<invalid> F=<invalid>"
        else
        (
            try
            (
                local base = ownerNode.baseObject
                if classOf base != Editable_Poly then "V=<unsupported> E=<unsupported> F=<unsupported>"
                else
                    "V=" + (polyOp.getNumVerts base as string) +
                    " E=" + (polyOp.getNumEdges base as string) +
                    " F=" + (polyOp.getNumFaces base as string)
            )
            catch ("V=<unavailable> E=<unavailable> F=<unavailable>")
        )
    ),

    fn recordExitError stage exceptionText =
    (
        append lastExitErrors (stage + ": " + exceptionText)
        appendLog ("exit.error " + lastExitErrors[lastExitErrors.count])
        false
    ),

    fn makeBits indices =
    (
        local result = #{}
        for indexValue in indices do result[indexValue] = true
        result
    ),

    fn currentPoint =
    (
        try (mouse.pos) catch ([0,0])
    ),

    fn ownsNativeCommand =
    (
        local queryFn = try (globalVars.get #MQDNativeV16SessionOwnsCommand) catch (undefined)
        sessionToken != 0 and queryFn != undefined and (try (queryFn sessionToken) catch (false))
    ),

    fn hasSessionContext =
    (
        try
        (
            isValidNode ownerNode and isValidNode targetNode and
            classOf ownerNode.baseObject == Editable_Poly and ownerNode.baseObject == sessionBaseObject and
            selection.count == 1 and selection[1] == ownerNode and
            getCommandPanelTaskMode() == #modify and modPanel.getCurrentObject() == sessionBaseObject and
            subObjectLevel == 1
        )
        catch (false)
    ),

    fn invalidateRecognition reasonText =
    (
        MayaQuadDrawR1.lastTick = 0
        MayaQuadDrawR1.lastStateKey = ""
        MayaQuadDrawR1.resetHover #none false
        MayaQuadDrawR3.invalidateCaches reasonText
        lastFreeHoverLevel = #none
        lastFreeHoverIndex = 0
        lastFreeTick = 0
        local hintFn = try (globalVars.get #MQDNativeV15SetMoveHint) catch (undefined)
        local cacheFn = try (globalVars.get #MQDNativeV16InvalidateVisibilityCache) catch (undefined)
        if hintFn != undefined do try (hintFn false) catch()
        if cacheFn != undefined do try (cacheFn()) catch()
        true
    ),

    fn onHostEvent token kind =
    (
        if not active or token != sessionToken or exitInProgress do return false
        contextPending = true
        if kind == #history do
        (
            historyPending = true
            -- Forget index-based preview data before Undo can replace it.
            -- Host geometry and its Undo records remain entirely native.
            invalidateRecognition "Host Undo/Redo"
        )
        local requestFn = try (globalVars.get #MQDNativeV16SessionRequest) catch (undefined)
        if requestFn == undefined then false else try (requestFn sessionToken (if kind == #history then 1 else 2)) catch (false)
    ),

    fn removeSessionCallbacks =
    (
        callbacks.removeScripts id:#MayaQuadDrawSessionLifecycle
        local endFn = try (globalVars.get #MQDNativeV16SessionEnd) catch (undefined)
        if sessionToken != 0 and endFn != undefined do endFn sessionToken
        true
    ),

    fn installSessionCallbacks =
    (
        callbacks.removeScripts id:#MayaQuadDrawSessionLifecycle
        local prefix = "if MayaQuadDrawR6 != undefined do MayaQuadDrawR6.onHostEvent " + (sessionToken as string)
        for eventId in #(#preSceneUndo,#sceneUndo,#preSceneRedo,#sceneRedo) do
            callbacks.addScript eventId (prefix + " #history") id:#MayaQuadDrawSessionLifecycle persistent:false
        for eventId in #(#modPanelObjPostChange,#modPanelSelChanged,#selectionSetChanged,#nodePostDelete) do
            callbacks.addScript eventId (prefix + " #context") id:#MayaQuadDrawSessionLifecycle persistent:false
        true
    ),

    fn onSettingsTab token =
    (
        if not active or token != sessionToken or exitInProgress or historyPending or contextPending do return false
        if not (hasSessionContext()) or not (ownsNativeCommand()) or not PBTrackGetToolActive() do return false
        if moveGestureActive or borderGestureActive or relaxGestureActive do return false
        if theHold.Holding() or theHold.IsSuspended() or theHold.RestoreOrRedoing() do return false
        -- Display only: reuse the loaded floater/settings, without starting or
        -- stopping any modeling tool or adding a geometry Undo record.
        local result = MayaQuadDrawUI_Toggle()
        appendLog ("settings.tab open=" + (MayaQuadDrawUI_IsOpen() as string))
        result
    ),

    fn onHostDeferred token flags ownsMode =
    (
        if not active or token != sessionToken or exitInProgress do return false
        contextCheckCount += 1
        -- The host may report an Undefined edit object midway through a stack
        -- change. Validate the settled context on the deferred main-thread call.
        if not (hasSessionContext()) or not ownsMode or not PBTrackGetToolActive() then
            completeExit "host context changed" endNativeTrack:ownsMode restoreContext:false
        else
        (
            local settingsRequested = flags == 4 and not historyPending and not contextPending
            if historyPending do
            (
                invalidateRecognition "Host Undo/Redo settled"
                if not moveGestureActive and not borderGestureActive and not relaxGestureActive do
                (
                    local inputFn = globalVars.get #MQDNativeV16SessionResetInput
                    inputFn sessionToken
                )
                historyRefreshCount += 1
            )
            historyPending = false
            contextPending = false
            if settingsRequested do onSettingsTab token
            true
        )
    ),

    fn canDispatch eventValue =
    (
        if not active do return false
        if eventValue == #mouseAbort do return true
        if historyPending or not (hasSessionContext()) or not (ownsNativeCommand()) then
        (
            onHostEvent sessionToken #context
            false
        )
        else true
    ),

    fn refreshRecognition shiftValue ctrlValue altValue recordFree:false preservePreview:false =
    (
        local p = currentPoint()
        local deleteChord = ctrlValue and altValue and not shiftValue
        local recognitionAlt = if deleteChord then false else altValue
        local previewShift = shiftValue and not ctrlValue and not altValue
        MayaQuadDrawR1.updateHover p shiftValue ctrlValue recognitionAlt false force:(not recordFree)
        if not preservePreview do MayaQuadDrawR3.updatePreview p previewShift
        if recordFree do
        (
            local setMoveHintFn = try (globalVars.get #MQDNativeV15SetMoveHint) catch (undefined)
            if setMoveHintFn != undefined do
            (
                local componentMoveReady = not shiftValue and not ctrlValue and not altValue and
                    (MayaQuadDrawR1.hoverLevel == #vertex or MayaQuadDrawR1.hoverLevel == #boundaryEdge or MayaQuadDrawR1.hoverLevel == #interiorEdge or MayaQuadDrawR1.hoverLevel == #face)
                try (setMoveHintFn componentMoveReady) catch()
            )
            lastFreeHoverLevel = MayaQuadDrawR1.hoverLevel
            lastFreeHoverIndex = MayaQuadDrawR1.hoverIndex
            lastFreePoint = p
            lastFreeTick = timeStamp()
        )
        true
    ),

    fn liveTopologyCounts =
    (
        if not isValidNode ownerNode then #(0,0,0)
        else
        (
            local deadVerts = try (polyOp.getDeadVerts ownerNode.baseObject) catch (#{} )
            local deadEdges = try (polyOp.getDeadEdges ownerNode.baseObject) catch (#{} )
            local deadFaces = try (polyOp.getDeadFaces ownerNode.baseObject) catch (#{} )
            #(
                (polyOp.getNumVerts ownerNode.baseObject)-deadVerts.numberSet,
                (polyOp.getNumEdges ownerNode.baseObject)-deadEdges.numberSet,
                (polyOp.getNumFaces ownerNode.baseObject)-deadFaces.numberSet
            )
        )
    ),

    fn isSwiftLoopChord shiftValue ctrlValue altValue =
    (
        ctrlValue and not shiftValue and not altValue
    ),

    fn swiftLoopHoverIsEdge =
    (
        MayaQuadDrawR1.hoverLevel == #boundaryEdge or MayaQuadDrawR1.hoverLevel == #interiorEdge
    ),

    fn nativeSwiftLoopEvent eventValue =
    (
        local beforeLive = liveTopologyCounts()
        local nativeResult = #continue
        local exceptionText = "none"

        -- Physical Ctrl belongs to the Maya-style wrapper.  Autodesk's
        -- callback receives no modifiers so it runs its native Insert branch;
        -- native Ctrl would select an existing loop instead.
        try (nativeResult = PolyBPolyDrawSwiftLoop eventValue false false false)
        catch
        (
            exceptionText = getCurrentException()
            nativeResult = #continue
        )

        if eventValue == #mousePoint do try (update ownerNode) catch()
        local afterLive = liveTopologyCounts()
        local topologyChanged = beforeLive[1] != afterLive[1] or beforeLive[2] != afterLive[2] or beforeLive[3] != afterLive[3]

        if topologyChanged do swiftLoopCommits += 1
        if eventValue == #freeMove or eventValue == #mouseMove do swiftLoopPreviewActive = true
        if topologyChanged do
        (
            swiftLoopPreviewActive = false
            swiftLoopSessionArmed = false
        )
        statusText = if topologyChanged then "Native Swift Loop inserted" else "Ctrl: Native Swift Loop preview"

        if eventValue != #freeMove do
        (
            local line = "SwiftLoop event=" + (eventValue as string)
            line += " before=" + (beforeLive as string) + " after=" + (afterLive as string)
            line += " changed=" + (topologyChanged as string)
            line += " result=" + (nativeResult as string)
            line += " exception=" + exceptionText
            appendLog line
        )

        if topologyChanged do
        (
            MayaQuadDrawR3.clearCandidate "Native Swift Loop inserted"
            try (MayaQuadDrawR1.resetHover #none false) catch()
        )
        redrawViews()
        nativeResult
    ),

    fn gentleSwiftLoopHandoff reasonText =
    (
        if not swiftLoopPreviewActive then false
        else
        (
            local nativeResult = #continue
            local exceptionText = "none"
            -- An Alt free-move takes Autodesk Swift Loop out of its Insert
            -- preview without terminating the shared PBStartTrack session.
            try (nativeResult = PolyBPolyDrawSwiftLoop #freeMove false false true)
            catch (exceptionText = getCurrentException())
            swiftLoopPreviewActive = false
            swiftLoopSessionArmed = false
            swiftLoopHandoffs += 1
            appendLog ("SwiftLoop gentle handoff=" + (swiftLoopHandoffs as string) + " reason=" + reasonText + " result=" + (nativeResult as string) + " exception=" + exceptionText)
            completeRedraw()
            true
        )
    ),

    fn routePureCtrlToSwiftLoop eventValue shiftValue ctrlValue altValue =
    (
        refreshRecognition shiftValue ctrlValue altValue recordFree:(eventValue == #freeMove)

        -- Maya-style order: Ctrl may be held anywhere.  Autodesk Swift Loop
        -- receives its first event only after the cursor reaches an edge, so
        -- it always has a valid edge ring from which to build the preview.
        if not swiftLoopSessionArmed and swiftLoopHoverIsEdge() do
        (
            swiftLoopSessionArmed = true
            appendLog ("SwiftLoop armed edge=" + (MayaQuadDrawR1.hoverIndex as string) + " event=" + (eventValue as string))
        )

        if swiftLoopSessionArmed then nativeSwiftLoopEvent eventValue
        else
        (
            statusText = "Ctrl held: move onto an edge to start Swift Loop"
            #continue
        )
    ),

    fn contextDeleteHovered =
    (
        local levelValue = MayaQuadDrawR1.hoverLevel
        local indexValue = MayaQuadDrawR1.hoverIndex
        local supported = levelValue == #vertex or levelValue == #boundaryEdge or levelValue == #interiorEdge or levelValue == #face
        if not supported or indexValue <= 0 or not isValidNode ownerNode then
        (
            statusText = "Delete blocked: cursor is not on a vertex, edge, or face"
            appendLog statusText
            false
        )
        else
        (
            local beforeLive = liveTopologyCounts()
            local operationName = "Unknown"
            local nativeResult = undefined
            local exceptionText = "none"

            try
            (
                undo "MQD R16 Context Delete" on
                (
                    case levelValue of
                    (
                        #vertex:
                        (
                            operationName = "Vertex"
                            nativeResult = polyOp.deleteVerts ownerNode.baseObject (makeBits #(indexValue))
                        )
                        #boundaryEdge:
                        (
                            operationName = "Edge"
                            nativeResult = polyOp.deleteEdges ownerNode.baseObject (makeBits #(indexValue)) delIsoVerts:true
                        )
                        #interiorEdge:
                        (
                            operationName = "Edge"
                            nativeResult = polyOp.deleteEdges ownerNode.baseObject (makeBits #(indexValue)) delIsoVerts:true
                        )
                        #face:
                        (
                            operationName = "Face"
                            nativeResult = polyOp.deleteFaces ownerNode.baseObject (makeBits #(indexValue)) delIsoVerts:true
                        )
                    )
                    update ownerNode
                )
            )
            catch (exceptionText = getCurrentException())

            local afterLive = liveTopologyCounts()
            local successValue = case operationName of
            (
                "Vertex": afterLive[1] < beforeLive[1]
                "Edge": afterLive[2] < beforeLive[2]
                "Face": afterLive[3] < beforeLive[3]
                default: false
            )

            if successValue do
            (
                if operationName == "Vertex" do vertexDeleteCommits += 1
                if operationName == "Edge" do edgeDeleteCommits += 1
                if operationName == "Face" do faceDeleteCommits += 1
            )

            statusText = if successValue then (operationName + " delete committed") else (operationName + " delete made no topology change")
            local line = statusText + " index=" + (indexValue as string) + " result=" + (nativeResult as string)
            line += " liveBefore=" + (beforeLive as string) + " liveAfter=" + (afterLive as string)
            line += " exception=" + exceptionText
            appendLog line
            format "MQD R16: %\n" line

            MayaQuadDrawR3.clearCandidate "Context delete completed"
            try (MayaQuadDrawR1.resetHover #none false) catch()
            completeRedraw()
            successValue
        )
    ),

    fn directFaceCommit clickPoint:undefined =
    (
        local candidateCount = MayaQuadDrawR3.candidateVerts.count
        if not MayaQuadDrawR3.candidateValid or not (candidateCount == 3 or candidateCount == 4) then
        (
            statusText = "Direct face blocked: no candidate"
            appendLog statusText
            false
        )
        else
        (
            -- Re-run the same final geometry + visible-surface gate used by
            -- Shift preview so a stale/cross-layer candidate cannot commit.
            local pointValue = if clickPoint == undefined then currentPoint() else clickPoint
            local validationResult = MayaQuadDrawR3.validateCandidateForCommit ownerNode (deepCopy MayaQuadDrawR3.candidateVerts) pointValue
            if not validationResult[1] do
            (
                statusText = "Direct face blocked: " + MayaQuadDrawR3.lastValidationReason
                appendLog statusText
                MayaQuadDrawR3.clearCandidate MayaQuadDrawR3.lastValidationReason
                redrawViews()
                return false
            )

            local orderedIds = deepCopy validationResult[3]
            local candidateBits = makeBits orderedIds
            local safeCreateFn = try (globalVars.get #MQDNativeV16CommitStepBuildFace) catch (undefined)
            if safeCreateFn == undefined then
            (
                appendLog "Direct face blocked: safe native creation unavailable"
                return false
            )
            local beforeVerts = polyOp.getNumVerts ownerNode.baseObject
            local beforeEdges = polyOp.getNumEdges ownerNode.baseObject
            local beforeFaces = polyOp.getNumFaces ownerNode.baseObject
            local nativeResult = undefined
            local exceptionText = "none"

            try
            (
                if candidateCount == 3 then
                (
                    undo "MQD Fill Triangle Hole" on
                    (
                        nativeResult = safeCreateFn ownerNode orderedIds
                    )
                )
                else
                (
                    undo "MQD Direct Face" on
                    (
                        nativeResult = safeCreateFn ownerNode orderedIds
                    )
                )
                update ownerNode
            )
            catch (exceptionText = getCurrentException())

            local afterVerts = polyOp.getNumVerts ownerNode.baseObject
            local afterEdges = polyOp.getNumEdges ownerNode.baseObject
            local afterFaces = polyOp.getNumFaces ownerNode.baseObject
            local successValue = nativeResult != undefined and afterVerts == beforeVerts and afterFaces == beforeFaces+1
            if successValue do
            (
                directFaceCommits += 1
                if candidateCount == 3 do triangleFillCommits += 1
            )

            local faceName = if candidateCount == 3 then "Triangle hole fill" else "Direct quad"
            statusText = if successValue then (faceName + " committed " + (candidateBits as string)) else (faceName + " rejected " + (candidateBits as string))
            local line = statusText + " result=" + (nativeResult as string)
            line += " before=V=" + (beforeVerts as string) + " E=" + (beforeEdges as string) + " F=" + (beforeFaces as string)
            line += " after=" + countsText()
            line += " faceDelta=" + ((afterFaces-beforeFaces) as string) + " edgeDelta=" + ((afterEdges-beforeEdges) as string)
            line += " exception=" + exceptionText
            line += " orderedIds=" + (orderedIds as string) + " commitPath=stepbuild-exact-preview"
            if successValue do line += " actualIds=" + ((polyOp.getFaceVerts ownerNode.baseObject nativeResult) as string)
            line += " time=" + (localTime as string)
            appendLog line
            format "MQD R16: %\n" line

            MayaQuadDrawR3.clearCandidate (if successValue then (faceName + " committed") else ("Native CreateFace rejected " + faceName))
            redrawViews()
            successValue
        )
    ),

    fn nativePointCommit eventValue shiftValue ctrlValue altValue =
    (
        local beforeVerts = polyOp.getNumVerts ownerNode.baseObject
        local beforeEdges = polyOp.getNumEdges ownerNode.baseObject
        local beforeFaces = polyOp.getNumFaces ownerNode.baseObject
        local nativeResult = #continue
        local exceptionText = "none"

        try (nativeResult = PolyBPolyDrawBuild eventValue shiftValue ctrlValue altValue)
        catch
        (
            exceptionText = getCurrentException()
            nativeResult = #continue
        )
        update ownerNode

        local afterVerts = polyOp.getNumVerts ownerNode.baseObject
        local afterEdges = polyOp.getNumEdges ownerNode.baseObject
        local afterFaces = polyOp.getNumFaces ownerNode.baseObject
        local successValue = afterVerts == beforeVerts+1 and afterEdges == beforeEdges and afterFaces == beforeFaces
        if successValue then pointCommits += 1

        statusText = if successValue then "Native point created" else "Native point click produced no single point"
        local line = statusText + " result=" + (nativeResult as string)
        line += " deltas=V" + ((afterVerts-beforeVerts) as string) + "/E" + ((afterEdges-beforeEdges) as string) + "/F" + ((afterFaces-beforeFaces) as string)
        line += " after=" + countsText() + " exception=" + exceptionText
        appendLog line
        format "MQD R16: %\n" line

        MayaQuadDrawR3.clearCandidate (if successValue then "Point created" else "Point creation returned no change")
        redrawViews()
        nativeResult
    ),

    fn canArmMove =
    (
        local elapsed = timeStamp()-lastFreeTick
        local p = currentPoint()
        local dx = p.x-lastFreePoint.x
        local dy = p.y-lastFreePoint.y
        local distanceSq = dx*dx+dy*dy
        (lastFreeHoverLevel == #vertex or lastFreeHoverLevel == #boundaryEdge or lastFreeHoverLevel == #interiorEdge or lastFreeHoverLevel == #face) and lastFreeHoverIndex > 0 and
        elapsed >= 0 and elapsed <= 10000 and distanceSq <= 6400.0
    ),

    fn moveLevelName levelValue =
    (
        case levelValue of
        (
            #vertex: "Vertex"
            #boundaryEdge: "Edge"
            #interiorEdge: "Edge"
            #face: "Face"
            default: "None"
        )
    ),

    fn moveLevelIsSupported levelValue =
    (
        levelValue == #vertex or levelValue == #boundaryEdge or levelValue == #interiorEdge or levelValue == #face
    ),

    fn hoverAllowsNativePointBuild levelValue =
    (
        levelValue == #surfaceBlank or moveLevelIsSupported levelValue
    ),

    fn moveNativeShift levelValue =
    (
        levelValue == #boundaryEdge or levelValue == #interiorEdge
    ),

    fn moveNativeCtrl levelValue =
    (
        levelValue == #face
    ),

    fn affectedVertsForMove levelValue indexValue =
    (
        local result = #{}
        if indexValue <= 0 then result
        else
        (
            case levelValue of
            (
                #vertex: result[indexValue] = true
                #boundaryEdge:
                (
                    local edges = #{}
                    edges[indexValue] = true
                    result = try (polyOp.getVertsUsingEdge ownerNode.baseObject edges) catch (#{} )
                )
                #interiorEdge:
                (
                    local edges = #{}
                    edges[indexValue] = true
                    result = try (polyOp.getVertsUsingEdge ownerNode.baseObject edges) catch (#{} )
                )
                #face:
                (
                    local faces = #{}
                    faces[indexValue] = true
                    result = try (polyOp.getVertsUsingFace ownerNode.baseObject faces) catch (#{} )
                )
            )
            result
        )
    ),

    fn centerOfVerts vertices =
    (
        local center = [0,0,0]
        local count = 0
        for vertexIndex in vertices do
        (
            local pointValue = try (polyOp.getVert ownerNode.baseObject vertexIndex node:ownerNode) catch (undefined)
            if pointValue != undefined do
            (
                center += pointValue
                count += 1
            )
        )
        if count > 0 then center / count else center
    ),

    fn clickRecoveryDistance =
    (
        local p = currentPoint()
        distance p lastFreePoint
    ),

    fn canRecoverClick tolerance:32.0 =
    (
        local elapsed = timeStamp()-lastFreeTick
        elapsed >= 0 and elapsed <= 5000 and (clickRecoveryDistance()) <= tolerance
    ),

    fn clickRecoveryDebug =
    (
        local elapsed = timeStamp()-lastFreeTick
        "lastHover=" + (lastFreeHoverLevel as string) + " currentHover=" + (MayaQuadDrawR1.hoverLevel as string) +
        " elapsed=" + (elapsed as string) + " distance=" + (clickRecoveryDistance() as string)
    ),

    fn syncAutoWeldSettings =
    (
        try (autoWeld = PolyToolsUI.PDAutoWeld) catch (autoWeld = true)
        try (weldDistance = PolyToolsUI.PDDistance) catch (weldDistance = 10.0)
        try (distanceType = PolyToolsUI.PDDistanceType) catch (distanceType = 1)
        true
    ),

    fn findAutoWeldTarget movedVertex =
    (
        syncAutoWeldSettings()
        if not autoWeld or movedVertex <= 0 or not isValidNode ownerNode then #(0, 1.0e20)
        else
        (
            local pointer = currentPoint()
            local threshold = if distanceType == 1 then amax 6.0 (amin 14.0 weldDistance) else 10.0
            local thresholdSq = threshold * threshold
            local bestVertex = 0
            local bestDistanceSq = thresholdSq + 0.0001
            local vertexCount = polyOp.getNumVerts ownerNode.baseObject
            local deadVerts = try (polyOp.getDeadVerts ownerNode.baseObject) catch (#{} )
            local liveIds = for i = 1 to vertexCount where i != movedVertex and not deadVerts[i] collect i
            local surfaceIds = MayaQuadDrawR1.surfaceLayerIds liveIds

            gw.setTransform (matrix3 1)
            for vertexIndex = 1 to vertexCount where surfaceIds[vertexIndex] do
            (
                local worldPoint = MayaQuadDrawR1.getWorldVertex ownerNode vertexIndex
                if worldPoint != undefined do
                (
                    local screenPoint3 = gw.wTransPoint worldPoint
                    if screenPoint3 != undefined do
                    (
                        local screenPoint = [screenPoint3.x as float, screenPoint3.y as float]
                        local distanceSq = MayaQuadDrawR1.distanceSq2D pointer screenPoint
                        if distanceSq <= bestDistanceSq do
                        (
                            bestDistanceSq = distanceSq
                            bestVertex = vertexIndex
                        )
                    )
                )
            )
            #(bestVertex, sqrt bestDistanceSq)
        )
    ),

    fn weldUndoState =
    (
        #(theHold.Holding(), theHold.IsSuspended(), theHold.GetBeginDepth(), theHold.SuperLevel(), theHold.GetGlobalPutCount())
    ),

    fn commitAutoWeldTarget movedVertex targetVertex screenDistance =
    (
        local beforeUndo = weldUndoState()
        lastWeldUndoTrace = #(beforeUndo)
        -- Move owns its native record. A released vertex weld owns a separate
        -- record, so Undo first restores topology, then the preceding Move.
        -- Respect another operation's Hold and a caller's suspended history.
        if beforeUndo[1] or beforeUndo[2] or beforeUndo[3] != 0 or beforeUndo[4] != 0 or theHold.IsUndoDisabled() or theHold.RestoreOrRedoing() do
        (
            appendLog ("AutoWeld skipped: native Undo not idle state=" + (beforeUndo as string))
            return #(false, targetVertex, screenDistance, false, "native Undo not idle")
        )
        if not isValidNode ownerNode or classOf ownerNode.baseObject != Editable_Poly do
            return #(false, targetVertex, screenDistance, false, "invalid owner")
        local beforeVerts = polyOp.getNumVerts ownerNode.baseObject
        if movedVertex < 1 or movedVertex > beforeVerts or targetVertex < 1 or targetVertex > beforeVerts or movedVertex == targetVertex do
            return #(false, targetVertex, screenDistance, false, "invalid vertex pair")
        local dead = polyOp.getDeadVerts ownerNode.baseObject
        if dead[movedVertex] or dead[targetVertex] do
            return #(false, targetVertex, screenDistance, false, "dead vertex pair")
        local targetWorld = MayaQuadDrawR1.getWorldVertex ownerNode targetVertex
        local weldResult = false
        local successValue = false
        local exceptionText = "none"
        undo "MQD Auto Weld" on
        (
            -- An outer undo-off context cannot be overridden by an inner undo-on.
            -- Perform topology changes only while native Restore registration works.
            if theHold.Holding() and not theHold.IsSuspended() then
            (
                try
                (
                    in coordsys world
                    (
                        weldResult = polyOp.weldVerts ownerNode.baseObject movedVertex targetVertex targetWorld node:ownerNode
                    )
                    update ownerNode
                    successValue = (polyOp.getNumVerts ownerNode.baseObject) == beforeVerts - 1
                    if not successValue do theHold.Cancel()
                )
                catch
                (
                    exceptionText = getCurrentException()
                    successValue = false
                    if theHold.Holding() do theHold.Cancel()
                )
            )
            else exceptionText = "native Undo recording unavailable"
        )
        local afterVerts = polyOp.getNumVerts ownerNode.baseObject
        append lastWeldUndoTrace (weldUndoState())
        if successValue do
        (
            autoWeldCommits += 1
            lastWeldTarget = targetVertex
        )
        appendLog ("AutoWeld source=" + (movedVertex as string) + " target=" + (targetVertex as string) +
            " screenDistance=" + (screenDistance as string) + " result=" + (weldResult as string) +
            " deltaV=" + ((afterVerts-beforeVerts) as string) + " exception=" + exceptionText +
            " undo=" + (lastWeldUndoTrace as string))
        #(successValue, targetVertex, screenDistance, weldResult, exceptionText)
    ),

    fn tryAutoWeld movedVertex =
    (
        local targetInfo = findAutoWeldTarget movedVertex
        if targetInfo[1] <= 0 then #(false, 0, targetInfo[2], false, "none")
        else commitAutoWeldTarget movedVertex targetInfo[1] targetInfo[2]
    ),

    fn beginMoveGesture =
    (
        moveGestureActive = true
        moveStartLevel = lastFreeHoverLevel
        moveStartIndex = lastFreeHoverIndex
        moveStartVertex = if moveStartLevel == #vertex then moveStartIndex else 0
        moveAffectedVerts = affectedVertsForMove moveStartLevel moveStartIndex
        moveMoveEvents = 0
        moveBeforeVerts = polyOp.getNumVerts ownerNode.baseObject
        moveBeforeEdges = polyOp.getNumEdges ownerNode.baseObject
        moveBeforeFaces = polyOp.getNumFaces ownerNode.baseObject
        moveStartPosition = centerOfVerts moveAffectedVerts
        MayaQuadDrawR3.clearCandidate ((moveLevelName moveStartLevel) + " drag routed to native Move")
        statusText = (moveLevelName moveStartLevel) + " move armed on " + (moveStartIndex as string)
        appendLog (statusText + " start=" + (moveStartPosition as string) + " before=" + countsText())
        true
    ),

    fn finishMoveGesture nativeResult exceptionText =
    (
        local preWeldVerts = polyOp.getNumVerts ownerNode.baseObject
        local preWeldEdges = polyOp.getNumEdges ownerNode.baseObject
        local preWeldFaces = polyOp.getNumFaces ownerNode.baseObject
        local endPosition = centerOfVerts moveAffectedVerts
        local moveDistance = distance moveStartPosition endPosition
        local weldInfo = if moveStartLevel == #vertex and moveDistance > 0.00001 and preWeldVerts == moveBeforeVerts then tryAutoWeld moveStartVertex else #(false, 0, 1.0e20, false, "skipped")
        local welded = weldInfo[1]
        local afterVerts = polyOp.getNumVerts ownerNode.baseObject
        local afterEdges = polyOp.getNumEdges ownerNode.baseObject
        local afterFaces = polyOp.getNumFaces ownerNode.baseObject
        local topologyStable = afterVerts == moveBeforeVerts and afterEdges == moveBeforeEdges and afterFaces == moveBeforeFaces
        local successValue = (topologyStable and moveDistance > 0.00001) or welded
        if successValue do
        (
            moveCommits += 1
            if moveStartLevel == #boundaryEdge or moveStartLevel == #interiorEdge do edgeMoveCommits += 1
            if moveStartLevel == #face do faceMoveCommits += 1
        )

        statusText = if welded then "Vertex move + Auto Weld committed" else if successValue then ("Native " + (moveLevelName moveStartLevel) + " move committed") else ((moveLevelName moveStartLevel) + " drag ended without movement")
        local line = statusText + " level=" + (moveStartLevel as string) + " index=" + (moveStartIndex as string)
        line += " moves=" + (moveMoveEvents as string) + " distance=" + (moveDistance as string) + " result=" + (nativeResult as string)
        line += " welded=" + (welded as string) + " target=" + (weldInfo[2] as string) + " screenDistance=" + (weldInfo[3] as string)
        line += " topologyStable=" + (topologyStable as string) + " after=" + countsText() + " exception=" + exceptionText
        appendLog line
        format "MQD R16: %\n" line

        moveGestureActive = false
        moveStartVertex = 0
        moveStartLevel = #none
        moveStartIndex = 0
        moveAffectedVerts = #{}
        moveMoveEvents = 0
        redrawViews()
        successValue
    ),

    fn canArmBorder =
    (
        local elapsed = timeStamp()-lastFreeTick
        local p = currentPoint()
        local dx = p.x-lastFreePoint.x
        local dy = p.y-lastFreePoint.y
        local distanceSq = dx*dx+dy*dy
        lastFreeHoverLevel == #boundaryEdge and lastFreeHoverIndex > 0 and
        elapsed >= 0 and elapsed <= 10000 and distanceSq <= 6400.0
    ),

    fn beginBorderGesture loopValue =
    (
        borderGestureActive = true
        borderLoopGesture = loopValue
        borderStartEdge = lastFreeHoverIndex
        borderMoveEvents = 0
        borderBeforeVerts = polyOp.getNumVerts ownerNode.baseObject
        borderBeforeEdges = polyOp.getNumEdges ownerNode.baseObject
        borderBeforeFaces = polyOp.getNumFaces ownerNode.baseObject
        MayaQuadDrawR3.clearCandidate (if borderLoopGesture then "Boundary-loop drag routed to native Border" else "Boundary drag routed to native Border")
        statusText = (if borderLoopGesture then "Boundary-loop extension armed on edge " else "Border extension armed on edge ") + (borderStartEdge as string)
        appendLog (statusText + " before=" + countsText())
        true
    ),

    fn finishBorderGesture nativeResult exceptionText =
    (
        local afterVerts = polyOp.getNumVerts ownerNode.baseObject
        local afterEdges = polyOp.getNumEdges ownerNode.baseObject
        local afterFaces = polyOp.getNumFaces ownerNode.baseObject
        local faceDelta = afterFaces-borderBeforeFaces
        local edgeDelta = afterEdges-borderBeforeEdges
        local vertDelta = afterVerts-borderBeforeVerts
        local successValue = faceDelta >= 1
        if successValue do
        (
            borderCommits += 1
            if borderLoopGesture do loopExtensionCommits += 1
        )

        local extensionName = if borderLoopGesture then "Boundary-loop extension" else "Border extension"
        statusText = if successValue then ("Native " + extensionName + " committed") else ("Native " + extensionName + " ended without a face")
        local line = statusText + " edge=" + (borderStartEdge as string)
        line += " moves=" + (borderMoveEvents as string) + " result=" + (nativeResult as string)
        line += " deltas=V" + (vertDelta as string) + "/E" + (edgeDelta as string) + "/F" + (faceDelta as string)
        line += " after=" + countsText() + " exception=" + exceptionText
        appendLog line
        format "MQD R16: %\n" line

        borderGestureActive = false
        borderLoopGesture = false
        borderStartEdge = 0
        borderMoveEvents = 0
        redrawViews()
        successValue
    ),

    fn firstLiveFaceFromSet faceBits =
    (
        local result = 0
        local deadFaces = try (polyOp.getDeadFaces ownerNode.baseObject) catch (#{} )
        for faceIndex in faceBits do
        (
            if result == 0 and faceIndex > 0 and not deadFaces[faceIndex] do result = faceIndex
        )
        result
    ),

    fn firstLiveFaceUsingComponent componentKind componentIndex =
    (
        local result = 0
        local faceCount = try (polyOp.getNumFaces ownerNode.baseObject) catch (0)
        local deadFaces = try (polyOp.getDeadFaces ownerNode.baseObject) catch (#{} )
        for faceIndex = 1 to faceCount while result == 0 do
        (
            if not deadFaces[faceIndex] do
            (
                local components =
                    if componentKind == #edge then
                        (try (polyOp.getFaceEdges ownerNode.baseObject faceIndex) catch (#()))
                    else
                        (try (polyOp.getFaceVerts ownerNode.baseObject faceIndex) catch (#()))
                local containsComponent =
                    if isKindOf components BitArray then
                        components[componentIndex]
                    else
                        ((findItem components componentIndex) > 0)
                if containsComponent do result = faceIndex
            )
        )
        result
    ),

    fn relaxSeedFaceForHover =
    (
        if lastFreeHoverIndex <= 0 then 0
        else
        (
            case lastFreeHoverLevel of
            (
                #face: lastFreeHoverIndex
                #interiorEdge:
                (
                    firstLiveFaceUsingComponent #edge lastFreeHoverIndex
                )
                #vertex:
                (
                    firstLiveFaceUsingComponent #vertex lastFreeHoverIndex
                )
                default: 0
            )
        )
    ),

    fn canArmRelax =
    (
        local elapsed = timeStamp()-lastFreeTick
        local p = currentPoint()
        local dx = p.x-lastFreePoint.x
        local dy = p.y-lastFreePoint.y
        local distanceSq = dx*dx+dy*dy
        (relaxSeedFaceForHover()) > 0 and
        elapsed >= 0 and elapsed <= 10000 and distanceSq <= 6400.0
    ),

    fn hoverIsBoundaryVertex =
    (
        lastFreeHoverLevel == #vertex and lastFreeHoverIndex > 0 and
        (try (MayaQuadDrawR3.vertexKind ownerNode lastFreeHoverIndex == #boundary) catch (true))
    ),

    fn canArmPainterRelax =
    (
        local elapsed = timeStamp()-lastFreeTick
        local p = currentPoint()
        local dx = p.x-lastFreePoint.x
        local dy = p.y-lastFreePoint.y
        local distanceSq = dx*dx+dy*dy
        local internalHover = lastFreeHoverLevel == #face or lastFreeHoverLevel == #interiorEdge or
            (lastFreeHoverLevel == #vertex and not hoverIsBoundaryVertex())
        internalHover and lastFreeHoverIndex > 0 and elapsed >= 0 and elapsed <= 10000 and distanceSq <= 6400.0
    ),

    fn requestPainterHandoff =
    (
        if painterHandoffPending or painterSessionOwned then false
        else if not canArmPainterRelax() then false
        else
        (
            local scheduleFn = globalVars.get #MQDPainterIntegratedV16DScheduleActivation
            if scheduleFn == undefined then false
            else
            (
                painterHandoffPending = true
                statusText = "Native Painter Relax handoff requested"
                appendLog (statusText + " hover=" + (lastFreeHoverLevel as string) + ":" + (lastFreeHoverIndex as string))
                try (scheduleFn()) catch
                (
                    painterHandoffPending = false
                    appendLog ("Painter handoff exception=" + getCurrentException())
                    false
                )
            )
        )
    ),

    fn activatePainterRelax =
    (
        -- The viewport recognizer already proved that Shift is over an internal
        -- vertex, interior edge, or face before it scheduled this callback.
        -- Consume that authorization here instead of sampling mouse.pos and the
        -- keyboard again from the later Windows timer callback.  Those later
        -- samples belong to a different input phase and used to reject every
        -- valid red internal target before Painter could take ownership.
        local authorizedInternalTarget = painterHandoffPending
        painterHandoffPending = false
        if not active or not authorizedInternalTarget then
        (
            appendLog ("Painter activation rejected active=" + (active as string) + " authorized=" + (authorizedInternalTarget as string))
            false
        )
        else
        (
            appendLog ("Painter activation authorized from red internal target hover=" + (lastFreeHoverLevel as string) + ":" + (lastFreeHoverIndex as string))
            local startFn = globalVars.get #MQDPainterIntegratedV16DStart
            if startFn == undefined then false
            else
            (
                local radiusValue = try (MayaQuadDrawUIState.relaxRadius as float) catch (20.0)
                local focusValue = try (MayaQuadDrawUIState.relaxFocus as float) catch (50.0)
                local strengthValue = try (MayaQuadDrawUIState.relaxStrength as float) catch (1.0)
                local offsetValue = try (PolyToolsUI.PDOffset as float) catch (0.0)

                painterHandoffInProgress = true
                try (PBEndTrack()) catch()
                local removeHookFn = globalVars.get #MQDNativeV15InputHookRemove
                if removeHookFn != undefined do try (removeHookFn()) catch()
                try (unregisterRedrawViewsCallback MayaQuadDrawR6_DrawCallback) catch()
                try (MayaQuadDrawR3.onToolStop()) catch()
                try (MayaQuadDrawR1.onToolStop()) catch()

                local started = try (startFn ownerNode targetNode radiusValue focusValue strengthValue offsetValue) catch
                (
                    appendLog ("Painter start exception=" + getCurrentException())
                    false
                )
                painterSessionOwned = started
                painterHandoffInProgress = false
                if started then
                (
                    statusText = "Native Painter Relax active; release Shift to return"
                    appendLog (statusText + " radius=" + (radiusValue as string) + " focus=" + (focusValue as string) + " strength=" + (strengthValue as string))
                )
                else
                (
                    appendLog "Painter start failed; resuming tracker"
                    resumeAfterPainter()
                )
                started
            )
        )
    ),

    fn resumeAfterPainter =
    (
        if not active then false
        else
        (
            local committedFn = globalVars.get #MQDPainterIntegratedV16DCommittedStrokes
            local exitFn = globalVars.get #MQDPainterIntegratedV16DExitRequested
            local committed = try (committedFn()) catch (0)
            painterExitRequested = try (exitFn()) catch (false)
            if committed > 0 do relaxStrokeCommits += committed
            painterHandoffPending = false
            painterHandoffInProgress = false
            painterSessionOwned = false

            if painterExitRequested then
            (
                statusText = "Painter RMB exit requested; MQD stopped"
                appendLog statusText
                stopManual()
                false
            )
            else
            (
                try (PolyToolsUI.PDDrawtype = 2) catch()
                try (PolyToolsUI.PDAutoWeld = true) catch()
                try (PBo_Pickobject = targetNode) catch()
                select ownerNode
                max modify mode
                try (subObjectLevel = 1) catch()
                try (MayaQuadDrawR1.prepare()) catch()
                MayaQuadDrawR1.onToolStart()
                MayaQuadDrawR3.onToolStart()
                try (unregisterRedrawViewsCallback MayaQuadDrawR6_DrawCallback) catch()
                registerRedrawViewsCallback MayaQuadDrawR6_DrawCallback

                local setDelegatesFn = globalVars.get #MQDNativeV15SetDelegates
                local resetFn = globalVars.get #MQDNativeV15TrackReset
                if setDelegatesFn != undefined do try (setDelegatesFn MayaQuadDrawR6_BuildDelegate MayaQuadDrawR6_MoveDelegate MayaQuadDrawR6_BorderDelegate MayaQuadDrawR6_OptimizerDelegate) catch()
                local hookReady = if resetFn != undefined then (try (resetFn()) catch (false)) else false
                if hookReady then
                (
                    PBStartTrack (globalVars.get #MQDNativeV15TrackPrimitive)
                    statusText = "Returned from native Painter Relax"
                    appendLog (statusText + " committed=" + (committed as string))
                    completeRedraw()
                    true
                )
                else
                (
                    statusText = "Could not restore MQD viewport tracker"
                    appendLog statusText
                    false
                )
            )
        )
    ),

    fn beginRelaxGesture =
    (
        local seedFace = relaxSeedFaceForHover()
        if seedFace <= 0 then false
        else
        (
            local radiusValue = try (MayaQuadDrawUIState.relaxRadius) catch (20.0)
            local focusValue = try (MayaQuadDrawUIState.relaxFocus) catch (50.0)
            local strengthValue = try (MayaQuadDrawUIState.relaxStrength) catch (1.0)
            local offsetValue = try (PolyToolsUI.PDOffset) catch (0.0)
            local beginFn = globalVars.get #MQDInternalRelaxV20Begin
            local began = false
            if beginFn != undefined do try (began = beginFn ownerNode targetNode radiusValue focusValue strengthValue offsetValue) catch (appendLog ("Relax begin exception=" + getCurrentException()))
            if began do
            (
                relaxGestureActive = true
                relaxReleasePending = true
                relaxStartFace = seedFace
                relaxMoveEvents = 0
                relaxChangedSteps = 0
                MayaQuadDrawR3.clearCandidate "Internal component drag routed to native Relax"
                statusText = "SDK Paint Deform buffered Relax armed from " + (lastFreeHoverLevel as string) + " on seed face " + (relaxStartFace as string)
                appendLog statusText
            )
            began
        )
    ),

    fn physicalShiftDown =
    (
        local shiftFn = globalVars.get #MQDNativeV15ShiftDown
        if shiftFn == undefined then true else (try (shiftFn()) catch (true))
    ),

    fn performRelaxStep =
    (
        if not relaxGestureActive then false
        else if not physicalShiftDown() then
        (
            finishRelaxGesture false "Shift released"
            false
        )
        else
        (
            relaxMoveEvents += 1
            local stepFn = globalVars.get #MQDInternalRelaxV20Step
            local changed = false
            if stepFn != undefined do
            (
                try
                (
                    local nativePoint = currentPoint()
                    changed = stepFn nativePoint.x nativePoint.y
                )
                catch (appendLog ("Relax step exception=" + getCurrentException()))
            )
            if changed do relaxChangedSteps += 1
            changed
        )
    ),

    fn finishRelaxGesture cancelValue reasonText =
    (
        if not relaxGestureActive then false
        else
        (
            local endSymbol = if cancelValue then #MQDInternalRelaxV20Cancel else #MQDInternalRelaxV20End
            local endFn = globalVars.get endSymbol
            local nativeResult = false
            if endFn != undefined do try (nativeResult = endFn()) catch (appendLog ("Relax finish exception=" + getCurrentException()))
            local successValue = not cancelValue and relaxChangedSteps > 0
            if successValue do relaxStrokeCommits += 1
            statusText = if cancelValue then "SDK Paint Deform Relax cancelled" else if successValue then "SDK Paint Deform buffered Relax committed" else "SDK Paint Deform Relax ended without movement"
            appendLog (statusText + " face=" + (relaxStartFace as string) + " moves=" + (relaxMoveEvents as string) + " changedSteps=" + (relaxChangedSteps as string) + " reason=" + reasonText + " native=" + (nativeResult as string))
            relaxGestureActive = false
            relaxStartFace = 0
            relaxMoveEvents = 0
            relaxChangedSteps = 0
            update ownerNode
            redrawViews()
            successValue
        )
    ),

    fn handleBuild eventValue shiftValue ctrlValue altValue =
    (
        if not (canDispatch eventValue) do return #continue
        if swiftLoopPreviewActive and not (isSwiftLoopChord shiftValue ctrlValue altValue) do
            gentleSwiftLoopHandoff ("Build route shift=" + (shiftValue as string) + " ctrl=" + (ctrlValue as string) + " alt=" + (altValue as string))
        if not (isSwiftLoopChord shiftValue ctrlValue altValue) do swiftLoopSessionArmed = false

        if eventValue == #mouseAbort then
        (
            abortSession eventValue shiftValue ctrlValue altValue
            false
        )
        else if isSwiftLoopChord shiftValue ctrlValue altValue then
        (
            routePureCtrlToSwiftLoop eventValue shiftValue ctrlValue altValue
        )
        else if eventValue == #freeMove then
        (
            refreshRecognition shiftValue ctrlValue altValue recordFree:true
            #continue
        )
        else if eventValue == #mousePoint then
        (
            refreshRecognition shiftValue ctrlValue altValue preservePreview:(shiftValue and not ctrlValue and not altValue)
            local modifiersClear = not ctrlValue and not altValue
            local canContextDelete = not shiftValue and ctrlValue and altValue
            canContextDelete = canContextDelete and (MayaQuadDrawR1.hoverLevel == #vertex or MayaQuadDrawR1.hoverLevel == #boundaryEdge or MayaQuadDrawR1.hoverLevel == #interiorEdge or MayaQuadDrawR1.hoverLevel == #face)
            local canCommitFace = shiftValue and modifiersClear
            canCommitFace = canCommitFace and (MayaQuadDrawR1.hoverLevel == #surfaceBlank or MayaQuadDrawR1.hoverLevel == #vertex or MayaQuadDrawR1.hoverLevel == #boundaryEdge)
            canCommitFace = canCommitFace and MayaQuadDrawR3.candidateValid
            local canCreatePoint = not shiftValue and modifiersClear and (hoverAllowsNativePointBuild MayaQuadDrawR1.hoverLevel)
            local delegateResult = #continue

            if canContextDelete then contextDeleteHovered()
            else if canCommitFace then directFaceCommit()
            else if canCreatePoint then delegateResult = nativePointCommit eventValue shiftValue ctrlValue altValue
            else
            (
                statusText = "Click blocked: " + (MayaQuadDrawR1.hoverLevel as string)
                appendLog (statusText + " shift=" + (shiftValue as string) + " candidate=" + (MayaQuadDrawR3.candidateValid as string))
                if shiftValue and modifiersClear do MayaQuadDrawR3.clearCandidate "Shift click did not validate the displayed preview"
            )
            delegateResult
        )
        else #continue
    ),

    fn handleMove eventValue shiftValue ctrlValue altValue =
    (
        if not (canDispatch eventValue) do return #continue
        if swiftLoopPreviewActive and not (isSwiftLoopChord shiftValue ctrlValue altValue) do
            gentleSwiftLoopHandoff ("Move route shift=" + (shiftValue as string) + " ctrl=" + (ctrlValue as string) + " alt=" + (altValue as string))
        if not (isSwiftLoopChord shiftValue ctrlValue altValue) do swiftLoopSessionArmed = false

        if eventValue == #mouseAbort then
        (
            local nativeResult = #continue
            if moveGestureActive do try (nativeResult = PolyBPolyDrawMove eventValue (moveNativeShift moveStartLevel) (moveNativeCtrl moveStartLevel) altValue) catch()
            abortSession eventValue shiftValue ctrlValue altValue
            nativeResult
        )
        else if isSwiftLoopChord shiftValue ctrlValue altValue then
        (
            routePureCtrlToSwiftLoop eventValue shiftValue ctrlValue altValue
        )
        else if eventValue == #freeMove then
        (
            refreshRecognition shiftValue ctrlValue altValue recordFree:true
            if not ctrlValue and not altValue and moveLevelIsSupported MayaQuadDrawR1.hoverLevel then
                try (PolyBPolyDrawMove eventValue (moveNativeShift MayaQuadDrawR1.hoverLevel) (moveNativeCtrl MayaQuadDrawR1.hoverLevel) altValue) catch (#continue)
            else #continue
        )
        else if eventValue == #mouseMove then
        (
            if not moveGestureActive and not shiftValue and not ctrlValue and not altValue and canArmMove() do beginMoveGesture()
            if moveGestureActive then
            (
                moveMoveEvents += 1
                local nativeResult = #continue
                try (nativeResult = PolyBPolyDrawMove eventValue (moveNativeShift moveStartLevel) (moveNativeCtrl moveStartLevel) altValue)
                catch
                (
                    appendLog ("Move mouseMove exception=" + getCurrentException())
                    nativeResult = #continue
                )
                nativeResult
            )
            else
            (
                statusText = "Drag blocked: press did not begin on a vertex, edge, or face"
                #continue
            )
        )
        else if eventValue == #mousePoint then
        (
            if moveGestureActive then
            (
                local nativeResult = #continue
                local exceptionText = "none"
                local releasedMoveLevel = moveStartLevel
                local releasedMoveIndex = moveStartIndex
                try (nativeResult = PolyBPolyDrawMove eventValue (moveNativeShift moveStartLevel) (moveNativeCtrl moveStartLevel) altValue)
                catch (exceptionText = getCurrentException())
                local moveSucceeded = finishMoveGesture nativeResult exceptionText
                refreshRecognition shiftValue ctrlValue altValue recordFree:true
                if not moveSucceeded and not shiftValue and not ctrlValue and not altValue then
                (
                    appendLog ("Zero-distance component click offered to native Build level=" + (releasedMoveLevel as string) + " index=" + (releasedMoveIndex as string))
                    local beforePointCommits = pointCommits
                    local recoveredResult = nativePointCommit eventValue false false false
                    if pointCommits > beforePointCommits do recoveredPointClicks += 1
                    recoveredResult
                )
                else nativeResult
            )
            else
            (
                local recoverAsPoint = not shiftValue and not ctrlValue and not altValue
                recoverAsPoint = recoverAsPoint and (canRecoverClick())
                if recoverAsPoint then
                (
                    appendLog ("Move-route mousePoint offered to point click " + (clickRecoveryDebug()))
                    local beforePointCommits = pointCommits
                    local recoveredResult = handleBuild eventValue shiftValue ctrlValue altValue
                    if pointCommits > beforePointCommits do recoveredPointClicks += 1
                    recoveredResult
                )
                else
                (
                    refreshRecognition shiftValue ctrlValue altValue
                    appendLog ("Move-route mousePoint blocked: no armed vertex drag; " + (clickRecoveryDebug()))
                    #continue
                )
            )
        )
        else #continue
    ),

    fn handleBorder eventValue shiftValue ctrlValue altValue =
    (
        if not (canDispatch eventValue) do return #continue
        if swiftLoopPreviewActive do
            gentleSwiftLoopHandoff ("Border route shift=" + (shiftValue as string) + " ctrl=" + (ctrlValue as string) + " alt=" + (altValue as string))
        swiftLoopSessionArmed = false

        if eventValue == #mouseAbort then
        (
            local nativeResult = #continue
            if borderGestureActive do try (nativeResult = PolyBPolyDrawBorder eventValue shiftValue ctrlValue altValue) catch()
            if relaxGestureActive do finishRelaxGesture true "mouseAbort"
            abortSession eventValue shiftValue ctrlValue altValue
            nativeResult
        )
        else if eventValue == #freeMove then
        (
            refreshRecognition shiftValue ctrlValue altValue recordFree:true
            if MayaQuadDrawR1.hoverLevel == #boundaryEdge then
                try (PolyBPolyDrawBorder eventValue shiftValue ctrlValue altValue) catch (#continue)
            else #continue
        )
        else if eventValue == #mouseMove then
        (
            if relaxGestureActive then
            (
                performRelaxStep()
                #continue
            )
            else
            (
            if not borderGestureActive and shiftValue and not altValue and physicalShiftDown() do
            (
                if canArmBorder() then beginBorderGesture ctrlValue
                else if not ctrlValue and canArmPainterRelax() do
                (
                    if beginRelaxGesture() do performRelaxStep()
                )
            )
            if borderGestureActive then
            (
                borderMoveEvents += 1
                local nativeResult = #continue
                try (nativeResult = PolyBPolyDrawBorder eventValue shiftValue ctrlValue altValue)
                catch
                (
                    appendLog ("Border mouseMove exception=" + getCurrentException())
                    nativeResult = #continue
                )
                nativeResult
            )
            else
            (
                statusText = "Shift drag blocked: start on an internal face for Relax or a boundary edge for Extend"
                #continue
            )
            )
        )
        else if eventValue == #mousePoint then
        (
            if relaxGestureActive then
            (
                finishRelaxGesture false "mouse release"
                relaxReleasePending = false
                refreshRecognition shiftValue ctrlValue altValue recordFree:true
                #continue
            )
            else if relaxReleasePending then
            (
                -- Shift may be released before LMB.  The physical-key check
                -- already ended Relax; consume the later mouse release so it
                -- cannot be reinterpreted as a face-build click.
                relaxReleasePending = false
                refreshRecognition shiftValue ctrlValue altValue recordFree:true
                #continue
            )
            else if borderGestureActive then
            (
                local nativeResult = #continue
                local exceptionText = "none"
                try (nativeResult = PolyBPolyDrawBorder eventValue shiftValue ctrlValue altValue)
                catch
                (
                    exceptionText = getCurrentException()
                )
                finishBorderGesture nativeResult exceptionText
                refreshRecognition shiftValue ctrlValue altValue recordFree:true
                nativeResult
            )
            else
            (
                local recoverAsFace = shiftValue and not ctrlValue and not altValue
                recoverAsFace = recoverAsFace and (canRecoverClick())
                if recoverAsFace then
                (
                    appendLog ("Border-route mousePoint offered to face click " + (clickRecoveryDebug()))
                    local beforeFaceCommits = directFaceCommits
                    local recoveredResult = handleBuild eventValue shiftValue ctrlValue altValue
                    if directFaceCommits > beforeFaceCommits do recoveredFaceClicks += 1
                    recoveredResult
                )
                else
                (
                    refreshRecognition shiftValue ctrlValue altValue preservePreview:true
                    MayaQuadDrawR3.clearCandidate "No valid face click or boundary drag"
                    appendLog ("Border-route mousePoint blocked: no armed boundary drag; " + (clickRecoveryDebug()))
                    #continue
                )
            )
        )
        else #continue
    ),

    fn captureLaunchState =
    (
        savedSelection = for currentNode in selection collect currentNode
        savedCommandPanelMode = try (getCommandPanelTaskMode()) catch (undefined)
        savedSubObjectLevel = try (subObjectLevel) catch (undefined)
        savedStackObject = if savedCommandPanelMode == #modify then (try (modPanel.getCurrentObject()) catch (undefined)) else undefined
        savedShowEndResult = try (showEndResult) catch (undefined)
        savedOwnerVertexTicks = try (ownerNode.vertexTicks) catch (undefined)
        savedPDDrawtype = try (PolyToolsUI.PDDrawtype) catch (undefined)
        savedPDAutoWeld = try (PolyToolsUI.PDAutoWeld) catch (undefined)
        savedPickObject = try (PBo_Pickobject) catch (undefined)
        savedPDTool = try (PolyToolsUI.PDTool) catch (0)
        launchStateCaptured = true
        appendLog ("launchState captured panel=" + (savedCommandPanelMode as string) +
            " subObject=" + (savedSubObjectLevel as string) + " vertexTicks=" + (savedOwnerVertexTicks as string) +
            " pdTool=" + (savedPDTool as string) + " drawType=" + (savedPDDrawtype as string))
        true
    ),

    fn restoreLaunchState reasonText restoreContext:true =
    (
        if not launchStateCaptured then false
        else
        (
            if restoreContext do
            (
                if savedPDDrawtype != undefined do try (PolyToolsUI.PDDrawtype = savedPDDrawtype) catch()
                if savedPDAutoWeld != undefined do try (PolyToolsUI.PDAutoWeld = savedPDAutoWeld) catch()
                try (PBo_Pickobject = savedPickObject) catch()
            )
            if isValidNode ownerNode and savedOwnerVertexTicks != undefined do try (ownerNode.vertexTicks = savedOwnerVertexTicks) catch()

            if restoreContext do
            (
            local validSavedSelection = #()
            for savedNode in savedSelection where isValidNode savedNode do append validSavedSelection savedNode
            try
            (
                local sameSelection = selection.count == validSavedSelection.count
                if sameSelection do for i=1 to validSavedSelection.count where selection[i] != validSavedSelection[i] do sameSelection=false
                if not sameSelection do
                    (if validSavedSelection.count > 0 then select validSavedSelection else clearSelection())
            )
            catch()

            if savedCommandPanelMode != undefined and getCommandPanelTaskMode() != savedCommandPanelMode do try (setCommandPanelTaskMode mode:savedCommandPanelMode) catch()
            if savedCommandPanelMode == #modify and savedStackObject != undefined and isValidNode ownerNode do
                try (if modPanel.getCurrentObject() != savedStackObject do modPanel.setCurrentObject savedStackObject node:ownerNode) catch()
            if savedCommandPanelMode == #modify and savedSubObjectLevel != undefined do try (if subObjectLevel != savedSubObjectLevel do subObjectLevel = savedSubObjectLevel) catch()
            if savedShowEndResult != undefined do try (if showEndResult != savedShowEndResult do showEndResult = savedShowEndResult) catch()
            )

            appendLog ("launchState restored reason=" + reasonText + " panel=" + (savedCommandPanelMode as string) +
                " subObject=" + (savedSubObjectLevel as string) + " vertexTicks=" + (savedOwnerVertexTicks as string))
            launchStateCaptured = false
            savedSelection = #()
            true
        )
    ),

    fn completeExit reasonText endNativeTrack:true restoreContext:true =
    (
        if exitInProgress do return false
        local ownedSession = active or trackerExpected or launchStateCaptured or painterSessionOwned
        if not ownedSession do return lastExitSucceeded
        exitInProgress = true
        lastExitErrors = #()
        lastExitReason = reasonText
        local wasActive = active
        local commandOwned = ownsNativeCommand()
        -- Explicit stop restores launch UI only while we still own that edit
        -- context. Passive cleanup preserves the user's new stack/selection.
        local restoreOwnedContext = restoreContext and (sessionToken == 0 or (commandOwned and hasSessionContext()))
        local shouldEndNative = endNativeTrack and (sessionToken == 0 or commandOwned)
        -- Detach our session before invoking anything that can send host
        -- notifications. Mesh statistics and logging are optional diagnostics.
        active = false
        trackerExpected = false
        try (removeSessionCallbacks()) catch (recordExitError "session callbacks" (getCurrentException()))
        if relaxGestureActive do try (finishRelaxGesture true reasonText) catch (recordExitError "finishRelaxGesture" (getCurrentException()))
        local beforeExitCounts = countsText()
        borderGestureActive = false
        borderLoopGesture = false
        borderStartEdge = 0
        moveGestureActive = false
        moveStartVertex = 0
        moveStartLevel = #none
        moveStartIndex = 0
        moveAffectedVerts = #{}
        swiftLoopSessionArmed = false
        swiftLoopPreviewActive = false
        relaxGestureActive = false
        relaxReleasePending = false
        painterHandoffPending = false
        painterHandoffInProgress = false
        painterSessionOwned = false
        painterExitRequested = false

        try (unregisterRedrawViewsCallback MayaQuadDrawR6_DrawCallback) catch (recordExitError "redraw callback" (getCurrentException()))
        try (MayaQuadDrawR3.onToolStop refresh:false) catch (recordExitError "candidate stop" (getCurrentException()))
        try (MayaQuadDrawR1.onToolStop refresh:false) catch (recordExitError "recognizer stop" (getCurrentException()))

        local cancelRelaxFn = globalVars.get #MQDInternalRelaxV20Cancel
        if cancelRelaxFn != undefined do try (cancelRelaxFn()) catch (recordExitError "native Relax stop" (getCurrentException()))

        if shouldEndNative do
        (
            try
            (
                if restoreOwnedContext and PolyToolsUI.PDTool == 1 then PolyBoost.ToolToggle 1 1 false else PBEndTrack()
            )
            catch
            (
                recordExitError "native tool stop" (getCurrentException())
                try (PBEndTrack()) catch (recordExitError "native tracker fallback" (getCurrentException()))
                try (PolyToolsUI.PDTool = 0) catch()
            )
        )

        -- Clear the owned PolyDraw button state without issuing another Max
        -- command. A replacement PolyDraw session retains its own UI state.
        if commandOwned or not (try (PBTrackGetToolActive()) catch (false)) do try
        (
            if PolyToolsUI.PDTool == 1 do
            (
                PolyToolsUI.PDTool = 0
                for i=1 to 12 do PolyToolsUI.PDButtons[i] = false
            )
        ) catch (recordExitError "PolyDraw button state" (getCurrentException()))

        local removeHookFn = globalVars.get #MQDNativeV15InputHookRemove
        if removeHookFn != undefined do try
        (
            if not removeHookFn() do recordExitError "input hook" "Removal returned false"
        )
        catch (recordExitError "input hook" (getCurrentException()))
        local invalidateVisibilityFn = globalVars.get #MQDNativeV16InvalidateVisibilityCache
        if invalidateVisibilityFn != undefined do try (invalidateVisibilityFn()) catch (recordExitError "visibility cache" (getCurrentException()))
        -- The explicitly opened settings window has its own lifetime. Ending
        -- a drawing session keeps its handle/position/parameters ready to use.
        try (restoreLaunchState reasonText restoreContext:restoreOwnedContext) catch (recordExitError "launch state" (getCurrentException()))

        statusText = "Exited"
        appendLog ("exit.complete reason=" + reasonText + " wasActive=" + (wasActive as string) +
            " nativeTrack=" + (if endNativeTrack then "ended" else "native-deferred") + " " + beforeExitCounts)
        ownerNode = undefined
        targetNode = undefined
        sessionBaseObject = undefined
        sessionToken = 0
        historyPending = false
        contextPending = false
        launchStateCaptured = false
        savedSelection = #()
        local localStateStopped = (try (not MayaQuadDrawR1.active and not MayaQuadDrawR3.active) catch (false))
        local nativeStopped = if shouldEndNative then (try (not PBTrackGetToolActive()) catch (false)) else true
        lastExitSucceeded = localStateStopped and nativeStopped and lastExitErrors.count == 0
        exitInProgress = false
        appendLog ("exit.result=" + (lastExitSucceeded as string) + " errors=" + (lastExitErrors.count as string))
        try (completeRedraw()) catch()
        lastExitSucceeded
    ),

    fn abortSession eventValue shiftValue ctrlValue altValue =
    (
        if painterHandoffInProgress then
        (
            borderGestureActive = false
            borderLoopGesture = false
            moveGestureActive = false
            swiftLoopSessionArmed = false
            swiftLoopPreviewActive = false
            appendLog "Tracker abort consumed by native Painter handoff"
            true
        )
        else if not active then false
        else
        (
            appendLog ("abort points=" + (pointCommits as string) + " moves=" + (moveCommits as string) + " relax=" + (relaxStrokeCommits as string) + " directFaces=" + (directFaceCommits as string) + " triangleFills=" + (triangleFillCommits as string) + " extensions=" + (borderCommits as string) + " loopExtensions=" + (loopExtensionCommits as string) + " swiftLoops=" + (swiftLoopCommits as string) + " deletesV/E/F=" + (vertexDeleteCommits as string) + "/" + (edgeDeleteCommits as string) + "/" + (faceDeleteCommits as string) + " " + countsText())
            -- The native bridge ends PBStartTrack just after this delegate
            -- returns, avoiding re-entry into Max's current mouse dispatch.
            completeExit "mouseAbort" endNativeTrack:false
        )
    ),

    fn drawHud =
    (
        -- This callback is intentionally text-free.  It also closes the
        -- wrapper when another Max command has already ended PBStartTrack
        -- without sending a mouseAbort delegate back to Core.
        if active and trackerExpected and not painterHandoffPending and not painterHandoffInProgress and not painterSessionOwned do
        (
            local trackerStillActive = try (PBTrackGetToolActive()) catch (true)
            if not trackerStillActive do
            (
                appendLog "Tracker ended externally; completing MQD exit"
                onHostEvent sessionToken #context
            )
        )
        true
    ),

    fn prepare =
    (
        ownerNode = if selection.count == 1 then selection[1] else undefined
        targetNode = try (PBo_Pickobject) catch (undefined)
        isValidNode ownerNode and isValidNode targetNode and ownerNode != targetNode and
        (try (classOf ownerNode.baseObject == Editable_Poly) catch (false))
    ),

    fn start =
    (
        if not prepare() then
        (
            messageBox "Select one Editable Poly work mesh and keep a valid PolyDraw target surface picked." title:"MQD"
            false
        )
        else if not doesFileExist pluginPath then
        (
            messageBox "The MQD input bridge is missing. Reinstall the package." title:"MQD"
            false
        )
        else if not doesFileExist internalRelaxPluginPath then
        (
            messageBox "The MQD Relax module is missing. Reinstall the package." title:"MQD"
            false
        )
        else
        (
            initializeLog()
            local v16AlreadyRegistered = try ((globalVars.get #MQDNativeV16BridgeVersion) != undefined) catch (false)
            local legacyV15Registered = try ((globalVars.get #MQDNativeV15BridgeVersion) != undefined) catch (false)
            local internalRelaxAlreadyRegistered = try ((globalVars.get #MQDInternalRelaxV20Version) != undefined) catch (false)
            local loadResult = if v16AlreadyRegistered then true else if legacyV15Registered then false else (loadDllsFromDir (getFilenamePath pluginPath) (filenameFromPath pluginPath) forceLoad:true)
            local internalRelaxLoadResult = if internalRelaxAlreadyRegistered then true else (loadDllsFromDir (getFilenamePath internalRelaxPluginPath) (filenameFromPath internalRelaxPluginPath) forceLoad:true)
            local v16VersionFn = try (globalVars.get #MQDNativeV16BridgeVersion) catch (undefined)
            local surfaceHitFn = try (globalVars.get #MQDNativeV16SurfaceHit) catch (undefined)
            local visibilityFilterFn = try (globalVars.get #MQDNativeV16FilterVisibleCandidateIds) catch (undefined)
            local surfaceIdsFn = try (globalVars.get #MQDNativeV16FilterSurfaceIds) catch (undefined)
            local stepBuildIdsFn = try (globalVars.get #MQDNativeV16FilterStepBuildIds) catch (undefined)
            local prepareFaceFn = try (globalVars.get #MQDNativeV16PrepareStepBuildFace) catch (undefined)
            local strictCommitFn = try (globalVars.get #MQDNativeV16CommitStepBuildFace) catch (undefined)
            local stepBuildSourceFn = try (globalVars.get #MQDNativeV16FilterStepBuildSourceIds) catch (undefined)
            local safeCreateFn = try (globalVars.get #MQDNativeV16CreateFaceSafe) catch (undefined)
            local invalidateVisibilityFn = try (globalVars.get #MQDNativeV16InvalidateVisibilityCache) catch (undefined)
            local versionFn = try (globalVars.get #MQDNativeV15BridgeVersion) catch (undefined)
            local setDelegatesFn = try (globalVars.get #MQDNativeV15SetDelegates) catch (undefined)
            local trackFn = try (globalVars.get #MQDNativeV15TrackPrimitive) catch (undefined)
            local countFn = try (globalVars.get #MQDNativeV15TrackCount) catch (undefined)
            local resetFn = try (globalVars.get #MQDNativeV15TrackReset) catch (undefined)
            local removeHookFn = try (globalVars.get #MQDNativeV15InputHookRemove) catch (undefined)
            local setMoveHintFn = try (globalVars.get #MQDNativeV15SetMoveHint) catch (undefined)
            local shiftDownFn = try (globalVars.get #MQDNativeV15ShiftDown) catch (undefined)
            local internalRelaxVersionFn = try (globalVars.get #MQDInternalRelaxV20Version) catch (undefined)
            local relaxBeginFn = try (globalVars.get #MQDInternalRelaxV20Begin) catch (undefined)
            local relaxStepFn = try (globalVars.get #MQDInternalRelaxV20Step) catch (undefined)
            local relaxEndFn = try (globalVars.get #MQDInternalRelaxV20End) catch (undefined)
            local relaxCancelFn = try (globalVars.get #MQDInternalRelaxV20Cancel) catch (undefined)
            local relaxStatusFn = try (globalVars.get #MQDInternalRelaxV20Status) catch (undefined)
            local registrationReady = v16VersionFn != undefined and surfaceHitFn != undefined and visibilityFilterFn != undefined and invalidateVisibilityFn != undefined
            registrationReady = registrationReady and surfaceIdsFn != undefined and safeCreateFn != undefined and stepBuildIdsFn != undefined and prepareFaceFn != undefined
            registrationReady = registrationReady and strictCommitFn != undefined and stepBuildSourceFn != undefined
            registrationReady = registrationReady and versionFn != undefined and setDelegatesFn != undefined and trackFn != undefined and countFn != undefined and resetFn != undefined and removeHookFn != undefined and setMoveHintFn != undefined and shiftDownFn != undefined
            registrationReady = registrationReady and internalRelaxVersionFn != undefined and relaxBeginFn != undefined and relaxStepFn != undefined and relaxEndFn != undefined and relaxCancelFn != undefined and relaxStatusFn != undefined
            -- A session with old loaded DLLs must not mix evaluated-mesh and
            -- base-object adapters. Restart is required to activate new DLLs.
            registrationReady = registrationReady and (try (v16VersionFn() == "0.17.9-max2024-v16-settings-tab") catch (false))
            registrationReady = registrationReady and (try (internalRelaxVersionFn() == "0.20.1-max2024-sdk-paint-deform-base-object") catch (false))

            appendLog ("plugin.load=" + (loadResult as string))
            appendLog ("internalRelax.plugin.load=" + (internalRelaxLoadResult as string))
            appendLog ("plugin.reused=" + (v16AlreadyRegistered as string) + " legacyV15.present=" + (legacyV15Registered as string) + " internalRelax.reused=" + (internalRelaxAlreadyRegistered as string))
            appendLog ("registry.v16 version=" + (v16VersionFn as string) + " surface=" + (surfaceHitFn as string) + " visibility=" + (visibilityFilterFn as string) + " invalidate=" + (invalidateVisibilityFn as string))
            appendLog ("registry.v15.compat version=" + (versionFn as string) + " set=" + (setDelegatesFn as string) + " track=" + (trackFn as string) + " count=" + (countFn as string) + " reset=" + (resetFn as string) + " remove=" + (removeHookFn as string) + " moveHint=" + (setMoveHintFn as string))
            appendLog ("registry.v20 nativeStrokeRelax=" + (relaxStepFn as string) + " status=" + (relaxStatusFn as string))

            if not registrationReady then
            (
                local registrationMessage = if legacyV15Registered and not v16AlreadyRegistered then
                    "NativeBridge V15 is already loaded in this Max session.\n\nRestart this same Max installation once so V16 can replace it safely. No viewport action was started."
                else
                    "The MQD native modules could not be registered.\n\nNo viewport action was started.\nReinstall the package or inspect the MQD log."
                messageBox registrationMessage title:"MQD registration"
                false
            )
            else
            (
            captureLaunchState()
            local versionText = v16VersionFn()
            local internalRelaxVersionText = internalRelaxVersionFn()
            appendLog ("plugin.version=" + versionText)
            appendLog ("internalRelax.plugin.version=" + internalRelaxVersionText)
            try (invalidateVisibilityFn()) catch (appendLog ("visibility.cache.invalidate.exception=" + getCurrentException()))

            try (if PBTrackGetToolActive() do PBEndTrack()) catch()
            try (PolyToolsUI.PolyDrawSettings()) catch()
            if PolyToolsUI.PDTool != 0 do try (PolyBoost.ToolToggle 1 PolyToolsUI.PDTool false) catch (try (PBEndTrack()) catch())

            try (PolyToolsUI.PDDrawtype = 2) catch()
            try (PolyToolsUI.PDAutoWeld = true) catch()
            try (PBo_Pickobject = targetNode) catch()
            -- prepare() already binds the sole selected object. Avoid a
            -- redundant select/rebuild of the same modifier-panel UI.
            if getCommandPanelTaskMode() != #modify do max modify mode
            if modPanel.getCurrentObject() != ownerNode.baseObject do modPanel.setCurrentObject ownerNode.baseObject node:ownerNode
            try (if subObjectLevel != 0 do subObjectLevel = 0) catch()
            if ownerNode.modifiers.count > 0 and not showEndResult do showEndResult = true
            try (PolyBoost.PolyDrawStart 1) catch (appendLog ("official.start.exception=" + getCurrentException()))
            try (PBEndTrack()) catch()
            try (PolyBDrawNodeInit targetNode) catch (appendLog ("surface.reinit.exception=" + getCurrentException()))
            try (subObjectLevel = 1) catch()
            -- At vertex level Max draws the editable control cage itself.
            -- Node-level ticks would additionally mark the subdivided output.
            try (ownerNode.vertexTicks = (ownerNode.modifiers.count == 0)) catch()
            try (PolyToolsUI.PDTool = 1) catch()

            if not MayaQuadDrawR1.prepare() then
            (
                appendLog "R1.prepare=false"
                completeExit "recognizer prepare failed" endNativeTrack:true
                false
            )
            else
            (
                pointCommits = 0
                moveCommits = 0
                edgeMoveCommits = 0
                faceMoveCommits = 0
                autoWeldCommits = 0
                lastWeldTarget = 0
                syncAutoWeldSettings()
                recoveredPointClicks = 0
                recoveredFaceClicks = 0
                directFaceCommits = 0
                triangleFillCommits = 0
                borderCommits = 0
                loopExtensionCommits = 0
                swiftLoopCommits = 0
                swiftLoopSessionArmed = false
                swiftLoopPreviewActive = false
                swiftLoopHandoffs = 0
                vertexDeleteCommits = 0
                edgeDeleteCommits = 0
                faceDeleteCommits = 0
                relaxGestureActive = false
                relaxReleasePending = false
                painterHandoffPending = false
                painterHandoffInProgress = false
                painterSessionOwned = false
                painterExitRequested = false
                relaxStartFace = 0
                relaxMoveEvents = 0
                relaxChangedSteps = 0
                relaxStrokeCommits = 0
                moveGestureActive = false
                moveStartVertex = 0
                moveStartLevel = #none
                moveStartIndex = 0
                moveAffectedVerts = #{}
                borderGestureActive = false
                borderLoopGesture = false
                borderStartEdge = 0
                trackerExpected = false
                lastFreeHoverLevel = #none
                lastFreeHoverIndex = 0
                statusText = "Ready"
                MayaQuadDrawR1.onToolStart refresh:false
                MayaQuadDrawR3.onToolStart refresh:false
                try (unregisterRedrawViewsCallback MayaQuadDrawR6_DrawCallback) catch()
                registerRedrawViewsCallback MayaQuadDrawR6_DrawCallback

                local delegatesReady = setDelegatesFn MayaQuadDrawR6_BuildDelegate MayaQuadDrawR6_MoveDelegate MayaQuadDrawR6_BorderDelegate MayaQuadDrawR6_OptimizerDelegate
                local hookReady = resetFn()
                appendLog ("v15.inputHook.ready=" + (hookReady as string))
                if not hookReady then
                (
                    completeExit "input hook unavailable" endNativeTrack:true
                    messageBox "MQD could not attach its input listener to the active viewport. No modeling tool was started." title:"MQD"
                    return false
                )
                active = true
                appendLog ("started delegates=" + (delegatesReady as string) + " " + countsText())
                PBStartTrack trackFn
                trackerExpected = true
                sessionBaseObject = ownerNode.baseObject
                local beginSessionFn = globalVars.get #MQDNativeV16SessionBegin
                sessionToken = beginSessionFn()
                historyPending = false
                contextPending = false
                if sessionToken == 0 do
                (
                    completeExit "session observer unavailable" endNativeTrack:true
                    return false
                )
                try (installSessionCallbacks()) catch
                (
                    recordExitError "session observer install" (getCurrentException())
                    completeExit "session observer install failed" endNativeTrack:true
                    return false
                )
                appendLog ("tracker.active=" + (PBTrackGetToolActive() as string))
                -- Settings are opened explicitly through the MQD Settings action.
                completeRedraw()
                    format "MQD 1.1.0 is active. Tab toggles settings in the drawing viewport.\n"
                true
            )
            )
        )
    ),

    fn stopManual =
    (
        completeExit "manualStop" endNativeTrack:true
    )
)

MayaQuadDrawR6 = MayaQuadDrawR6State()

fn MayaQuadDrawR6_DrawCallback =
(
    global MayaQuadDrawR6
    if MayaQuadDrawR6 != undefined do MayaQuadDrawR6.drawHud()
)

fn MayaQuadDrawR6_BuildDelegate eventValue shiftValue ctrlValue altValue =
(
    global MayaQuadDrawR6
    MayaQuadDrawR6.handleBuild eventValue shiftValue ctrlValue altValue
)

fn MayaQuadDrawR6_MoveDelegate eventValue shiftValue ctrlValue altValue =
(
    global MayaQuadDrawR6
    MayaQuadDrawR6.handleMove eventValue shiftValue ctrlValue altValue
)

fn MayaQuadDrawR6_BorderDelegate eventValue shiftValue ctrlValue altValue =
(
    global MayaQuadDrawR6
    MayaQuadDrawR6.handleBorder eventValue shiftValue ctrlValue altValue
)

fn MayaQuadDrawR6_OptimizerDelegate eventValue shiftValue ctrlValue altValue =
(
    global MayaQuadDrawR6
    if eventValue == #mouseAbort then
    (
        MayaQuadDrawR6.abortSession eventValue shiftValue ctrlValue altValue
        false
    )
    else #continue
)

fn MayaQuadDrawR16_PainterActivate =
(
    global MayaQuadDrawR6
    if MayaQuadDrawR6 != undefined do MayaQuadDrawR6.activatePainterRelax()
)

fn MayaQuadDrawR16_PainterResume =
(
    global MayaQuadDrawR6
    if MayaQuadDrawR6 != undefined do MayaQuadDrawR6.resumeAfterPainter()
)

fn MayaQuadDrawR6_Start =
(
    global MayaQuadDrawR6
    if MayaQuadDrawR6.active then true else MayaQuadDrawR6.start()
)

fn MayaQuadDrawR6_Stop =
(
    global MayaQuadDrawR6
    if MayaQuadDrawR6 != undefined then MayaQuadDrawR6.stopManual() else true
)

format "MQD 1.1.0 runtime loaded. Run MayaQuadDrawR6_Start().\n"


