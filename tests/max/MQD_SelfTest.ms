/* Self-test v4. Each phase runs in a separate rollout timer event.
   No scene reset, undo-buffer clearing, or viewport changes. Empty scene only. */
global MQDLayerSafetyTestDialog
global MQDLayerSafetyTestReportPath
global MQDLayerSafetyTestQuiet
global MQDLayerSafetyTestResult
global MQDLayerSafetyTestAllowedNodes
global MQDLayerSafetyTestRootPath
global MQDLayerSafetyTestReportOverride
global MayaQuadDrawRootPath
global MayaQuadDrawR6
global MayaQuadDrawR1
global MayaQuadDrawR3

try (destroyDialog MQDLayerSafetyTestDialog) catch()
MQDLayerSafetyTestReportPath = if MQDLayerSafetyTestReportOverride != undefined then MQDLayerSafetyTestReportOverride else (getFilenamePath (getSourceFileName())) + "MQD_自检结果_2026-09-16.txt"

rollout MQDLayerSafetyTestDialog "MQD 分步自检" width:360 height:65
(
    local lines = #()
    local checks = 0
    local failures = 0
    local phase = 1
    local done = false
    local n = undefined
    local unrelated = undefined
    local original = #()
    local unrelatedBefore = #()
    local result = undefined
    local safeCreate = undefined
    local filter = undefined
    local invalidate = undefined
    local stepFilter = undefined
    local prepareFace = undefined
    local strictCommit = undefined
    local sourceFilter = undefined
    local pipelineOwner = undefined
    local pipelineBefore = #()
    local pipelineCycle = #()
    local pipelinePoint = [0,0]
    local pipelineFarPoint = [0,0]
    local guardOwner = undefined
    local guardBefore = #()
    local guardCycle = #()
    local guardFace = undefined
    local facingOwner = undefined
    local facingTarget = undefined
    local testOrigin = [0,0,0]
    local testRight = [1,0,0]
    local testUp = [0,1,0]
    local testToward = [0,0,1]
    local testUnit = 1.0
    label progressLabel "正在检查，请稍候……" pos:[12,16] width:336
    timer phaseTimer interval:250 active:false

    fn checkTest condition label =
    (
        checks += 1
        if not condition do failures += 1
        local entry = (if condition then "PASS " else "FAIL ") + label
        append lines entry
        format "%\n" entry
        if not condition do throw ("Check failed: " + label)
    )
    fn captureVerts n = for i = 1 to (polyOp.getNumVerts n) collect (polyOp.getVert n i)
    fn sameVerts n snapshot =
    (
        if not isValidNode n do return false
        local same = (polyOp.getNumVerts n) == snapshot.count
        for i = 1 to snapshot.count while same do same = (polyOp.getVert n i) == snapshot[i]
        same
    )
    fn faceCycle n f = if f == undefined then #() else polyOp.getFaceVerts n f
    fn testPoint x y z = testOrigin + (testRight*x + testUp*y + testToward*z)*testUnit
    fn sameIds result expected = result != undefined and ((result as bitArray) == expected)
    fn cycleNormal nodeValue ids =
    (
        if ids == undefined or ids.count < 3 do return [0,0,0]
        local points = for id in ids collect (polyOp.getVert nodeValue id)
        local value = [0,0,0]
        for corner = 2 to points.count-1 do value += cross (points[corner]-points[1]) (points[corner+1]-points[1])
        if length value == 0.0 then value else normalize value
    )
    fn testScreen pointValue =
    (
        gw.setTransform (matrix3 1)
        local p = gw.wTransPoint pointValue
        [p.x as float,p.y as float]
    )
    fn setPreviewOwner nodeValue =
    (
        MayaQuadDrawR1.ownerNode = nodeValue
        MayaQuadDrawR1.targetNode = facingTarget
        MayaQuadDrawR1.offset = 0.0
        MayaQuadDrawR1.hoverLevel = #surfaceBlank
        MayaQuadDrawR1.hoverIndex = 0
        MayaQuadDrawR3.refreshVisibleCaches()
    )
    fn liveFaceCount n = if not isValidNode n then -1 else (polyOp.getNumFaces n) - (polyOp.getDeadFaces n).numberSet
    fn newPoly label points polygons =
    (
        local n = editable_mesh name:label
        convertTo n Editable_Poly
        for p in points do polyOp.createVert n p
        for ids in polygons do polyOp.createPolygon n ids
        update n
        n
    )

    fn saveReport =
    (
        local stream = createFile MQDLayerSafetyTestReportPath encoding:#utf8
        format "MQD self-test v4 unified: native source/nearest-four/preview/exact-commit/Undo chain\r\n" to:stream
        for line in lines do format "%\r\n" line to:stream
        format "checks=% failures=% phase=% done=%\r\n" checks failures phase done to:stream
        close stream
    )

    fn checkUndoBoundary =
    (
        checkTest (not theHold.Holding() and not theHold.IsSuspended()) "Undo executes outside an active construction transaction"
        append lines ("Undo stack: " + ((theHold.getUndoNames()) as string))
        append lines ("Redo stack: " + ((theHold.getRedoNames()) as string))
    )

    fn advance =
    (
        local priorFailures = failures
        try
        (
            append lines ("PHASE " + phase as string)
            if theHold.Holding() or theHold.IsSuspended() do throw "Test event inherits an unfinished undo scope; stopped before modifying anything."
            case phase of
            (
                1:
                (
                    -- Default remains empty-scene only. Integration runners
                    -- may retain an explicit list of their own earlier fixtures.
                    local allowedNodes = if MQDLayerSafetyTestAllowedNodes == undefined then #() else MQDLayerSafetyTestAllowedNodes
                    for node in objects where (findItem allowedNodes node)==0 do throw "Scene contains a node not owned by this test run."
                    MayaQuadDrawRootPath = if MQDLayerSafetyTestRootPath != undefined then MQDLayerSafetyTestRootPath else (getDir #userScripts) + "\\MayaQuadDraw_Max2024\\"
            safeCreate = try (globalVars.get #MQDNativeV16CreateFaceSafe) catch (undefined)
            if safeCreate == undefined do
                loadDllsFromDir (MayaQuadDrawRootPath + "plugins\\") "MayaQuadDrawNativeBridge_v16.dlx" forceLoad:true
            safeCreate = try (globalVars.get #MQDNativeV16CreateFaceSafe) catch (undefined)
            filter = try (globalVars.get #MQDNativeV16FilterSurfaceIds) catch (undefined)
            stepFilter = try (globalVars.get #MQDNativeV16FilterStepBuildIds) catch (undefined)
            prepareFace = try (globalVars.get #MQDNativeV16PrepareStepBuildFace) catch (undefined)
            strictCommit = try (globalVars.get #MQDNativeV16CommitStepBuildFace) catch (undefined)
            sourceFilter = try (globalVars.get #MQDNativeV16FilterStepBuildSourceIds) catch (undefined)
            invalidate = try (globalVars.get #MQDNativeV16InvalidateVisibilityCache) catch (undefined)
            if safeCreate == undefined or filter == undefined or stepFilter == undefined or prepareFace == undefined or strictCommit == undefined or sourceFilter == undefined do throw "New native bridge not loaded. Restart Max before this test."
            local bridgeVersionFn = globalVars.get #MQDNativeV16BridgeVersion
            append lines ("Native bridge version: " + (bridgeVersionFn()))
            fileIn (MayaQuadDrawRootPath + "runtime\\MayaQuadDraw_Core.ms") quiet:true
            checkTest true "Runtime scripts loaded"

            n = undefined
            unrelated = undefined
            undo "MQD Test Setup" on
            (
                n = newPoly "MQD_TEST_FaceUndo" #([0,0,0],[10,0,0],[10,10,0],[0,10,0],[20,0,0],[20,10,0]) #()
                unrelated = newPoly "MQD_TEST_Unrelated" #([100,0,0],[110,0,0],[110,10,0],[100,10,0]) #(#(1,2,3,4))
                select unrelated
            )
            original = captureVerts n
            unrelatedBefore = captureVerts unrelated
                )
                2:
                (
                    undo "MQD Test Face" on (result = safeCreate n #(3,4,1,2))
            checkTest (result != undefined and liveFaceCount n == 1) "One face created on explicit owner"
            checkTest (((faceCycle n result) as string) == "#(3, 4, 1, 2)") "Ordered cycle preserved"
            checkTest (sameVerts n original) "All old vertices unchanged"
            checkTest (sameVerts unrelated unrelatedBefore and liveFaceCount unrelated == 1) "Unrelated selected node unchanged"
                )
                3:
                (
                    checkUndoBoundary()
                    max undo
                    checkTest (isValidNode n and isValidNode unrelated) "Undo preserves both test nodes"
                    checkTest (liveFaceCount n == 0 and sameVerts n original) "Undo returns exact original geometry"
                )
                4:
                (
                    checkUndoBoundary()
                    max redo
                    checkTest (liveFaceCount n == 1 and sameVerts n original) "Redo returns one face only"
                )
                5:
                (
                    local duplicate = safeCreate n #(1,2,3,4)
            checkTest (duplicate == undefined and liveFaceCount n == 1) "Duplicate face rejected without mutation"
            local invalid = safeCreate n #(1,2,999,4)
            checkTest (invalid == undefined and sameVerts n original) "Stale vertex ID rejected without mutation"
            local repeat = safeCreate n #(1,2,2,4)
            checkTest (repeat == undefined and liveFaceCount n == 1) "Repeated vertex rejected"
            undo "MQD Test Adjacent Face" on (result = safeCreate n #(2,3,6,5))
            checkTest (result != undefined and liveFaceCount n == 2 and sameVerts n original) "Adjacent quad accepted with native winding correction"
                )
                6:
                (
                    checkUndoBoundary()
                    max undo
                    checkTest (liveFaceCount n == 1 and sameVerts n original) "Adjacent face Undo preserves previous face"
                )
                7:
                (
                    checkUndoBoundary()
                    max redo
                    checkTest (liveFaceCount n == 2 and sameVerts n original) "Adjacent face Redo"
                    checkTest (MayaQuadDrawR3.sideCutsExistingFace n 1 3) "Existing-face diagonal guard retained"
                )
                8:
                (
                    -- Use the current camera rays; no viewport navigation is performed.
            local viewSize = getViewSize()
            local cameraRay = mapScreenToWorldRay (viewSize * 0.5)
            local forward = normalize cameraRay.dir
            local right = cross forward [0,0,1]
            if length right < 0.001 do right = cross forward [0,1,0]
            right = normalize right
            local up = normalize (cross right forward)
            local origin = cameraRay.pos + forward * 100.0
            for gap in #(20.0,0.0005) do
            (
                local target = undefined
                local dots = undefined
                undo "MQD Test Layers" on
                (
                    local points = #()
                    for depth in #(0.0,gap,gap*2.0) do
                    (
                        local c = origin + forward * depth
                        append points (c-right*25.0-up*25.0)
                        append points (c+right*25.0-up*25.0)
                        append points (c+right*25.0+up*25.0)
                        append points (c-right*25.0+up*25.0)
                    )
                    target = newPoly ("MQD_TEST_LayerTarget_" + gap as string) points #(#(1,2,3,4),#(5,6,7,8),#(9,10,11,12))
                    dots = newPoly ("MQD_TEST_LayerDots_" + gap as string) #(origin,origin+forward*gap,origin+forward*(gap*2.0)) #()
                )
                invalidate()
                local visible = filter dots target #(1,2,3) 0.001
                append lines ("Layer result gap=" + gap as string + " ids=" + visible as string)
                append lines ("Actual layer spacing=" + ((distance (polyOp.getVert dots 1) (polyOp.getVert dots 2)) as string))
                checkTest (visible != undefined and visible.count == 1 and visible[1] == 1) ("Only front layer visible; gap=" + gap as string)
                if gap == 20.0 do
                (
                    local openTarget = undefined
                    undo "MQD Test Open Surface" on
                    (
                        openTarget = newPoly "MQD_TEST_OpenTarget" #(origin-right*25.0-up*25.0,origin+right*25.0-up*25.0,origin+right*25.0+up*25.0,origin-right*25.0+up*25.0) #(#(1,2,3,4))
                    )
                    invalidate()
                    visible = filter dots openTarget #(1,2,3) 0.001
                    append lines ("Open target result ids=" + visible as string)
                    checkTest (visible != undefined and visible.count == 1 and visible[1] == 1) "Open target still hides points behind its only hit"
                )
            )
                )
                9:
                (
                    -- Front and reverse-wound patches share one target layer.
                    -- Basic layer visibility must still accept both; only the
                    -- Shift candidate query removes the reverse-wound patch.
                    local viewSize = getViewSize()
                    local centerRay = mapScreenToWorldRay (viewSize*0.5)
                    local viewBasis = inverse (viewport.getTM())
                    testToward = normalize viewBasis.row3
                    testRight = normalize viewBasis.row1
                    testUp = normalize (cross testToward testRight)
                    testOrigin = centerRay.pos + normalize(centerRay.dir)*100.0
                    local sideRay = mapScreenToWorldRay [viewSize.x*0.6,viewSize.y*0.5]
                    local sideT = (dot (testOrigin-sideRay.pos) testToward)/(dot sideRay.dir testToward)
                    testUnit = (distance testOrigin (sideRay.pos+sideRay.dir*sideT))/12.0
                    if testUnit <= 0.0 do throw "Cannot size view-relative fixture."
                    undo "MQD Test Step Build Domain" on
                    (
                        facingOwner = newPoly "MQD_TEST_StepBuildFrontBack" #((testPoint -4 -1 0),(testPoint -2 -1 0),(testPoint -2 1 0),(testPoint -4 1 0),(testPoint 2 -1 0),(testPoint 4 -1 0),(testPoint 4 1 0),(testPoint 2 1 0),(testPoint 0 -3 0)) #(#(1,2,3,4),#(5,8,7,6))
                        facingTarget = newPoly "MQD_TEST_StepBuildTarget" #((testPoint -10 -10 0),(testPoint 10 -10 0),(testPoint 10 10 0),(testPoint -10 10 0)) #(#(1,2,3,4))
                    )
                    local before = captureVerts facingOwner
                    local facesBefore = for f=1 to (polyOp.getNumFaces facingOwner) collect (polyOp.getFaceVerts facingOwner f)
                    local ids = for i=1 to 9 collect i
                    local stepIds = stepFilter facingOwner ids
                    append lines ("Step Build front/back ids=" + stepIds as string)
                    checkTest (sameIds stepIds #{1..4,9}) "Step Build accepts front boundary and loose point; rejects back boundary"
                    invalidate()
                    checkTest (sameIds (filter facingOwner facingTarget ids 0.001) #{1..9}) "Ordinary layer visibility still admits both windings on the front target"
                    MayaQuadDrawR1.ownerNode = facingOwner
                    MayaQuadDrawR1.targetNode = facingTarget
                    MayaQuadDrawR1.offset = 0.0
                    MayaQuadDrawR3.refreshVisibleCaches()
                    checkTest ((MayaQuadDrawR3.visibleIds as bitArray) == #{1..9}) "Obstacle cache retains visible rear-facing geometry"
                    checkTest ((MayaQuadDrawR3.eligibleIds as bitArray) == #{1..4,9}) "Preview shortlist uses Step Build domain before ranking"
                    checkTest (MayaQuadDrawR3.candidatePassesVisibleSurface facingOwner #(1,2,3,4) (viewSize*0.5)) "Final candidate domain accepts front boundary"
                    checkTest (not (MayaQuadDrawR3.candidatePassesVisibleSurface facingOwner #(5,6,7,8) (viewSize*0.5))) "Final candidate domain rejects back boundary"
                    checkTest (((stepFilter facingOwner #(9,4,1,999,0)) as string) == "#(9, 4, 1)") "Read-only query preserves input order and ignores stale IDs"
                    checkTest ((stepFilter facingOwner #()).count == 0) "Empty candidate input stays empty"
                    local facesAfter = for f=1 to (polyOp.getNumFaces facingOwner) collect (polyOp.getFaceVerts facingOwner f)
                    checkTest (sameVerts facingOwner before and ((facesAfter as string) == (facesBefore as string))) "Candidate queries leave all geometry and face cycles unchanged"
                )
                10:
                (
                    local folded = undefined
                    local patch = undefined
                    local distant = undefined
                    undo "MQD Test Boundary Folds" on
                    (
                        folded = newPoly "MQD_TEST_FoldedBoundary" #((testPoint 0 0 0),(testPoint 2 0 0),(testPoint 0 2 0),(testPoint -6 0 0),(testPoint 0 6 0)) #(#(1,2,3),#(1,4,5))
                        local pts = #()
                        for y in #(-2,0,2) do for x in #(-2,0,2) do append pts (testPoint x y 0)
                        patch = newPoly "MQD_TEST_InternalVertex" pts #(#(1,2,5,4),#(2,3,6,5),#(4,5,8,7),#(5,6,9,8))
                        distant = newPoly "MQD_TEST_DistantBackPatch" #((testPoint 0 0 0),(testPoint 2 0 0),(testPoint 0 2 0),(testPoint -1 -1 -100),(testPoint 1 -1 -100),(testPoint 1 1 -100),(testPoint -1 1 -100)) #(#(4,7,6,5))
                    )
                    checkTest (sameIds (stepFilter folded #(1,2,3,4,5)) #{1,2,3}) "Fold joint survives a larger rear face; no averaged-normal rejection"
                    checkTest (sameIds (stepFilter patch #(1,2,3,4,5,6,7,8,9)) #{1..4,6..9}) "Fully internal vertex remains ineligible even on front boundary faces"
                    checkTest (sameIds (stepFilter distant #(1,2,3,4,5,6,7)) #{1..3}) "Three front dots cannot borrow a fourth point from a distant back-facing patch"
                    checkTest (sameIds (stepFilter unrelated #(1,2,3,4)) (MayaQuadDrawR3.stepBuildCandidateIds unrelated #(1,2,3,4))) "Script wrapper queries the explicit owner, not the global selected node"
                )
                11:
                (
                    undo "MQD Test Hidden And Transformed Candidates" on (polyOp.setHiddenVerts facingOwner #{1})
                    checkTest (sameIds (stepFilter facingOwner #(1,2,3,4,5,6,7,8,9)) #{2..4,9}) "Hidden vertex cannot seed a Shift candidate"
                    undo "MQD Test Rotated Candidate Owner" on (facingOwner.transform = (angleaxis 180 testRight) as matrix3)
                    checkTest (sameIds (stepFilter facingOwner #(1,2,3,4,5,6,7,8,9)) #{5..9}) "Object rotation updates boundary facing without changing the viewport"
                    undo "MQD Test Scaled Candidate Owner" on (facingOwner.transform = scaleMatrix [2,0.5,3])
                    checkTest (sameIds (stepFilter facingOwner #(1,2,3,4,5,6,7,8,9)) #{2..4,9}) "Nonuniform object scale uses the native object-space view direction"
                    undo "MQD Test Singular Candidate Owner" on (facingOwner.transform = scaleMatrix [1,1,0])
                    checkTest ((stepFilter facingOwner #(1,2,3,4)) == undefined) "Singular object transform fails closed"
                    checkTest (sameVerts n original and liveFaceCount n == 2) "Candidate-domain tests preserve the prior Undo/Redo fixture"
                )
                12:
                (
                    local sharedThree = undefined
                    local rawOracle = undefined
                    local twoPointOverlap = undefined
                    local loose = undefined
                    local triHole = undefined
                    local basePoints = #((testPoint -2 -2 0),(testPoint 2 -2 0),(testPoint 2 2 0),(testPoint -2 2 0))
                    undo "MQD Test Face Guard Fixtures" on
                    (
                        local pts = deepCopy basePoints
                        append pts (testPoint -3 3 1)
                        sharedThree = newPoly "MQD_TEST_IncidentTriple" pts #(#(1,2,3,4))
                        rawOracle = newPoly "MQD_TEST_GenericAPIReproduction" pts #(#(1,2,3,4))
                        pts = deepCopy basePoints
                        append pts (testPoint 0 1 0)
                        append pts (testPoint 0 -1 0)
                        twoPointOverlap = newPoly "MQD_TEST_TwoPointReverseOverlap" pts #(#(1,2,3,4))
                        loose = newPoly "MQD_TEST_LooseWinding" basePoints #()
                        triHole = newPoly "MQD_TEST_ValidTriangleHole" #((testPoint 0 0 0),(testPoint 2 0 0),(testPoint 1 2 0),(testPoint 1 -2 0),(testPoint 4 2 0),(testPoint -2 2 0)) #(#(2,1,4),#(3,2,5),#(1,3,6))
                        pts = deepCopy basePoints
                        append pts (testPoint 4 -2 0)
                        append pts (testPoint 4 2 0)
                        guardOwner = newPoly "MQD_TEST_GuardedAdjacentFace" pts #(#(1,2,3,4))
                    )
                    -- Reproduce the previously reachable route only on a
                    -- disposable fixture, never on the user's model.
                    local rawFace = undefined
                    undo "MQD Test Old Generic API" on (rawFace = safeCreate rawOracle #(1,2,3,5))
                    checkTest (rawFace != undefined and liveFaceCount rawOracle == 2) "Reproduced: generic safe creation alone permits three-shared-vertex face"
                    checkTest ((dot (cycleNormal rawOracle (polyOp.getFaceVerts rawOracle rawFace)) testToward) < 0.0) "Reproduced: shared-edge correction turns that old candidate backwards"
                    local before = captureVerts sharedThree
                    checkTest ((prepareFace sharedThree #(1,2,3,5)) == undefined) "New native preparation rejects the incident triple before mutation"
                    local points = for v in #(1,2,3,5) collect (polyOp.getVert sharedThree v)
                    local previewResult = MayaQuadDrawR3.validateCandidateGeometry sharedThree #(1,2,3,5) points #([0,0],[40,0],[40,40],[-20,40]) runLocalChecks:false
                    checkTest (not previewResult[1]) "Preview geometry rejects shared triple before any candidate can display"
                    checkTest (sameVerts sharedThree before and liveFaceCount sharedThree == 1) "Rejected preparation leaves old vertices and face untouched"
                    checkTest ((prepareFace twoPointOverlap #(2,3,5,6)) == undefined) "Final facing gate rejects reverse-only result even with only two shared vertices"
                    checkTest (not (MayaQuadDrawR3.candidateReusesFaceTriple guardOwner #{2,3,5,6})) "Normal adjacent extension sharing only one edge remains allowed"
                    local preparedLoose = prepareFace loose #(4,3,2,1)
                    checkTest (preparedLoose != undefined and (dot (cycleNormal loose preparedLoose) testToward) > 0.0) "Loose quad gets a front-facing cycle rather than being blocked"
                    local preparedTriangle = prepareFace triHole #(1,2,3)
                    checkTest (preparedTriangle != undefined and (dot (cycleNormal triHole preparedTriangle) testToward) > 0.0) "Genuine closed triangle hole still has a valid front-facing cycle"
                    guardBefore = captureVerts guardOwner
                    guardCycle = prepareFace guardOwner #(2,3,6,5)
                    checkTest (guardCycle != undefined and (dot (cycleNormal guardOwner guardCycle) testToward) > 0.0) "Adjacent face preparation resolves winding without losing front-facing result"
                    undo "MQD Test Guarded Face" on (guardFace = strictCommit guardOwner guardCycle)
                    checkTest (guardFace != undefined and ((polyOp.getFaceVerts guardOwner guardFace) as string) == (guardCycle as string)) "Committed face uses the exact prepared preview cycle"
                    checkTest (sameVerts guardOwner guardBefore and liveFaceCount guardOwner == 2) "Guarded commit only adds the requested face"
                )
                13:
                (
                    checkUndoBoundary()
                    max undo
                    checkTest (liveFaceCount guardOwner == 1 and sameVerts guardOwner guardBefore) "Guarded face Undo preserves its original neighbor and all vertices"
                )
                14:
                (
                    checkUndoBoundary()
                    max redo
                    checkTest (liveFaceCount guardOwner == 2 and sameVerts guardOwner guardBefore and ((polyOp.getFaceVerts guardOwner guardFace) as string) == (guardCycle as string)) "Guarded face Redo restores the exact prepared cycle"
                )
                15:
                (
                    local fallback = undefined
                    local interior = undefined
                    local loose = undefined
                    undo "MQD Test Unified Source Policy" on
                    (
                        local pts = #((testPoint -1 -1 0),(testPoint 1 -1 0),(testPoint 1 1 0),(testPoint -1 1 0),(testPoint 3 -1 0),(testPoint 5 -1 0),(testPoint 5 1 0),(testPoint 3 1 0))
                        fallback = newPoly "MQD_TEST_NoFarSubstitution" pts #(#(1,2,3,4))
                        pts = #()
                        for y in #(-2,0,2) do for x in #(-2,0,2) do append pts (testPoint x y 0)
                        interior = newPoly "MQD_TEST_SourceThenBoundary" pts #(#(1,2,5,4),#(2,3,6,5),#(4,5,8,7),#(5,6,9,8))
                        loose = newPoly "MQD_TEST_ExactCycleReject" #((testPoint -2 -2 0),(testPoint 2 -2 0),(testPoint 2 2 0),(testPoint -2 2 0)) #()
                        pipelineOwner = newPoly "MQD_TEST_PreviewToCommit" #((testPoint -2 -2 0),(testPoint 2 -2 0),(testPoint 2 2 0),(testPoint -2 2 0),(testPoint 5 -2 0),(testPoint 9 -2 0),(testPoint 9 2 0),(testPoint 5 2 0)) #()
                    )
                    pipelinePoint = testScreen testOrigin
                    pipelineFarPoint = testScreen (testPoint 7 0 0)
                    setPreviewOwner fallback
                    checkTest (sameIds (MayaQuadDrawR3.nearestQuadIds pipelinePoint) #{1..4}) "Exactly nearest four chosen before topology checks"
                    checkTest (not (MayaQuadDrawR3.buildQuadCandidate pipelinePoint) and not MayaQuadDrawR3.candidateValid) "Invalid nearest face does not fall back to distant valid loose points"
                    checkTest ((prepareFace fallback #(5,6,7,8)) != undefined) "Distant alternative really is valid, but was not substituted"
                    setPreviewOwner interior
                    checkTest ((findItem (sourceFilter interior #(1,2,3,4,5,6,7,8,9)) 5) > 0 and (findItem (stepFilter interior #(1,2,3,4,5,6,7,8,9)) 5) == 0) "Source membership and post-selection boundary eligibility are separate"
                    checkTest (not (MayaQuadDrawR3.buildQuadCandidate pipelinePoint)) "Internal point among nearest four causes no preview, not replacement"
                    local before = captureVerts loose
                    checkTest ((strictCommit loose #(4,3,2,1)) == undefined and liveFaceCount loose == 0 and sameVerts loose before) "Strict commit refuses an unprepared backwards cycle without auto-flipping"
                    checkTest ((strictCommit guardOwner #(1,2,3,5)) == undefined and liveFaceCount guardOwner == 2) "Native strict entry also rejects triple-overlap without relying on script guard"
                )
                16:
                (
                    setPreviewOwner pipelineOwner
                    checkTest (MayaQuadDrawR3.buildQuadCandidate pipelinePoint) "Real preview builder accepts a normal nearest-four loose quad"
                    pipelineCycle = deepCopy MayaQuadDrawR3.candidateVerts
                    pipelineBefore = captureVerts pipelineOwner
                    local checked = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (checked[1] and ((checked[3] as string) == (pipelineCycle as string))) "Displayed cycle survives full commit revalidation unchanged"
                    MayaQuadDrawR1.hoverLevel = #vertex
                    MayaQuadDrawR1.hoverIndex = 5
                    local staleHover = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (not staleHover[1]) "A hover component outside the displayed four points invalidates the click"
                    MayaQuadDrawR1.hoverLevel = #surfaceBlank
                    MayaQuadDrawR1.hoverIndex = 0
                    local changed = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelineFarPoint
                    checkTest (not changed[1] and ((MayaQuadDrawR3.candidateVerts as string) == (pipelineCycle as string))) "Moving to another quartet expires preview without replacing its IDs"
                    MayaQuadDrawR6.ownerNode = pipelineOwner
                    MayaQuadDrawR6.targetNode = facingTarget
                    checkTest (not (MayaQuadDrawR6.directFaceCommit clickPoint:pipelineFarPoint) and liveFaceCount pipelineOwner == 0) "Core rejects stale preview instead of building at the new cursor quartet"
                    setPreviewOwner pipelineOwner
                    if not (MayaQuadDrawR3.buildQuadCandidate pipelinePoint) do throw "Cannot restore pipeline preview"
                    pipelineCycle = deepCopy MayaQuadDrawR3.candidateVerts
                    undo "MQD Test Stale Point" on (polyOp.setVert pipelineOwner 1 ((polyOp.getVert pipelineOwner 1)+testToward*testUnit))
                    changed = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (not changed[1]) "Candidate coordinate change invalidates displayed preview"
                    undo "MQD Test Restore Point" on (polyOp.setVert pipelineOwner 1 pipelineBefore[1])
                    MayaQuadDrawR1.targetNode = unrelated
                    changed = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (not changed[1]) "Target switch invalidates preview ownership"
                    MayaQuadDrawR1.targetNode = facingTarget
                    local oldView = MayaQuadDrawR3.candidateViewTM
                    MayaQuadDrawR3.candidateViewTM = oldView*(transMatrix [1,0,0])
                    changed = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (not changed[1]) "Stale view snapshot rejected without navigating the viewport"
                    MayaQuadDrawR3.candidateViewTM = oldView
                    local oldTime = MayaQuadDrawR3.candidateTime
                    MayaQuadDrawR3.candidateTime = oldTime + 1t
                    changed = MayaQuadDrawR3.validateCandidateForCommit pipelineOwner pipelineCycle pipelinePoint
                    checkTest (not changed[1]) "Stale time snapshot rejected without changing scene time"
                    MayaQuadDrawR3.candidateTime = oldTime
                )
                17:
                (
                    setPreviewOwner pipelineOwner
                    checkTest (MayaQuadDrawR3.buildQuadCandidate pipelinePoint) "Preview rebuild restores a valid deterministic candidate"
                    pipelineCycle = deepCopy MayaQuadDrawR3.candidateVerts
                    local committed = MayaQuadDrawR6.directFaceCommit clickPoint:pipelinePoint
                    checkTest (committed and liveFaceCount pipelineOwner == 1) "Actual Core preview-to-native-strict commit succeeds"
                    checkTest (((polyOp.getFaceVerts pipelineOwner 1) as string) == (pipelineCycle as string)) "Actual committed IDs and order equal the displayed preview"
                    checkTest ((dot (cycleNormal pipelineOwner pipelineCycle) testToward) > 0.0 and sameVerts pipelineOwner pipelineBefore) "Pipeline face faces forward and preserves every old vertex"
                    checkTest (not (MayaQuadDrawR6.directFaceCommit clickPoint:pipelinePoint) and liveFaceCount pipelineOwner == 1) "Consumed preview cannot commit twice"
                )
                18:
                (
                    checkUndoBoundary()
                    max undo
                    checkTest (liveFaceCount pipelineOwner == 0 and sameVerts pipelineOwner pipelineBefore) "One Undo reverses the full Core pipeline commit"
                )
                19:
                (
                    checkUndoBoundary()
                    max redo
                    checkTest (liveFaceCount pipelineOwner == 1 and sameVerts pipelineOwner pipelineBefore and ((polyOp.getFaceVerts pipelineOwner 1) as string) == (pipelineCycle as string)) "Redo restores the same full-pipeline face cycle"
                    done = true
                )
            )
            if not done do phase += 1
        )
        catch
        (
            if failures == priorFailures do failures += 1
            append lines ("ERROR phase=" + phase as string + " " + getCurrentException())
            done = true
        )
        saveReport()
    )

    on MQDLayerSafetyTestDialog open do phaseTimer.active = true
    on phaseTimer tick do
    (
        phaseTimer.active = false
        advance()
        if done then
        (
            local summary = "checks=" + checks as string + " failures=" + failures as string
            MQDLayerSafetyTestResult = #(checks,failures,phase)
            destroyDialog MQDLayerSafetyTestDialog
            if MQDLayerSafetyTestQuiet != true do messageBox ((if failures == 0 then "自动检查通过。" else "检查发现问题，结果日志已保存。") + "\n\n" + summary + "\n\n" + MQDLayerSafetyTestReportPath) title:"MQD 自检结果 v4"
        )
        else
        (
            progressLabel.text = "正在检查第 " + phase as string + " / 19 步，请稍候……"
            phaseTimer.active = true
        )
    )
    on MQDLayerSafetyTestDialog close do
    (
        phaseTimer.active = false
        if not done do
        (
            done = true
            failures += 1
            append lines "CANCELLED: test dialog closed before completion"
            saveReport()
        )
    )
)

(
    local active = try (MayaQuadDrawR6 != undefined and MayaQuadDrawR6.active) catch (false)
    local allowedNodes = if MQDLayerSafetyTestAllowedNodes == undefined then #() else MQDLayerSafetyTestAllowedNodes
    local unexpected = for node in objects where (findItem allowedNodes node)==0 collect node
    if unexpected.count != 0 or active then
        messageBox "请先保存自己的模型，并切到空场景后再运行本自检。当前场景未修改。" title:"MQD 自检"
    else createDialog MQDLayerSafetyTestDialog
)
