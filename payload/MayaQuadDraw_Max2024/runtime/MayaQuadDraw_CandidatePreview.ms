/*
    Maya Quad Draw - Round 16 candidate preview with native Painter handoff.

    Native Step Build rules plus MQD's read-only preview/occlusion adapter:
    - Select one nearest-four set from facing boundary faces and loose points.
    - Validate boundary eligibility after selection. Invalid means no preview.
    - Shift candidates use Max Step Build's facing boundary-face domain plus
      loose points. Basic picking and obstacle geometry remain independent.
    - Existing faces and candidate cycles using an already two-sided edge are rejected.
    - Candidate geometry remains viewport-only; no face command is called.
    - Shift-hover on a dot, open edge, or blank area selects a possible face.
    - Preview prepares the exact final cycle; click revalidates that same cycle.
    - The quad path has no combination scoring, sticky override or substitution.
    - A closed three-edge boundary hole previews as a purple triangle.
    - General loose three-point triangle creation remains disabled.
    - A possible quad remains simple, convex and locally coherent.
    - Folded, lamina-like, diagonal-spanning, edge-crossing and inconsistent
      winding candidates are rejected before preview and again before commit.
*/

global MayaQuadDrawR1
global MayaQuadDrawR1Tool
global MayaQuadDrawR1_DrawCallback
global MayaQuadDrawR3
global MayaQuadDrawR3Tool
global MayaQuadDrawR3_DrawCallback
global MayaQuadDrawR3_Start
global MayaQuadDrawR3_Stop

try
(
    if MayaQuadDrawR3 != undefined and MayaQuadDrawR3.active do stopTool MayaQuadDrawR3Tool
)
catch()
try (unregisterRedrawViewsCallback MayaQuadDrawR3_DrawCallback) catch()

global MayaQuadDrawRootPath

fileIn (MayaQuadDrawRootPath + "runtime\\MayaQuadDraw_Recognizer.ms")

struct MayaQuadDrawR3State
(
    active = false,
    shiftHeld = false,
    candidateValid = false,
    candidateKind = #none,
    candidateVerts = #(),
    candidateWorld = #(),
    candidateScreen = #(),
    candidateOwner = undefined,
    candidateTarget = undefined,
    candidateViewTM = undefined,
    candidateViewSize = undefined,
    candidateTime = undefined,
    quadSourceIds = #(),
    quadSourceScreen = #(),
    visibleIds = #(),
    visibleWorld = #(),
    visibleScreen = #(),
    eligibleIds = #(),
    eligibleWorld = #(),
    eligibleScreen = #(),
    eligibleKinds = #(),
    blockedIds = #(),
    blockedWorld = #(),
    previewStatus = "Shift is up",
    lastPreviewKey = "",
    candidateRadiusFactor = 0.20,
    candidatePoolLimit = 10,
    candidateOutlineTolerance = 42.0,
    lastValidationReason = "Not checked",
    logPath = MayaQuadDrawRootPath + "logs\\MayaQuadDraw_Current.log",

    fn initializeLog =
    (
        local stream = createFile logPath
        format "MQD R16 NATIVE PAINTER\r\n" to:stream
        format "Shift hover accepts loose/boundary vertices, open edges, and blank surface.\r\n" to:stream
        format "Quad policy: one nearest-four set; invalid means no candidate, with no fallback substitution.\r\n" to:stream
        format "Preview owns the prepared cycle; click revalidates without replacing it.\r\n" to:stream
        format "Purple triangle requires one closed three-edge boundary hole; arbitrary three-dot triangles stay disabled.\r\n" to:stream
        format "Guard: valid local face, no swallowed vertex, no crossing edge, no occupied diagonal, consistent winding.\r\n" to:stream
        close stream
        true
    ),

    fn appendLog textValue =
    (
        local stream = openFile logPath mode:"a"
        format "%\r\n" textValue to:stream
        close stream
        true
    ),

    fn idArrayText values =
    (
        local result = ""
        for arrayIndex = 1 to values.count do
        (
            if arrayIndex > 1 do result += ","
            result += values[arrayIndex] as string
        )
        result
    ),

    fn candidateIdText = idArrayText candidateVerts,

    fn recordPreviewIfChanged =
    (
        local key = if candidateValid then ("candidate=" + (candidateKind as string) + ":" + candidateIdText()) else ("clear=" + previewStatus)
        key += " blocked=" + idArrayText blockedIds
        if key != lastPreviewKey do
        (
            lastPreviewKey = key
            appendLog key
            format "MQD R16: %\n" key
        )
        true
    ),

    fn clearCandidate reasonValue =
    (
        candidateValid = false
        candidateKind = #none
        candidateVerts = #()
        candidateWorld = #()
        candidateScreen = #()
        candidateOwner = undefined
        candidateTarget = undefined
        candidateViewTM = undefined
        candidateViewSize = undefined
        candidateTime = undefined
        previewStatus = reasonValue
        recordPreviewIfChanged()
        true
    ),

    fn getWorldVertex nodeValue vertexIndex =
    (
        local result = undefined
        try (in coordsys world (result = polyOp.getVert nodeValue vertexIndex)) catch (result = undefined)
        result
    ),

    fn rememberCandidate =
    (
        candidateOwner = MayaQuadDrawR1.ownerNode
        candidateTarget = MayaQuadDrawR1.targetNode
        candidateViewTM = copy (viewport.getTM())
        candidateViewSize = getViewSize()
        candidateTime = currentTime
        true
    ),

    fn sameViewTransform snapshotValue =
    (
        if snapshotValue == undefined then false
        else
        (
            local currentValue = viewport.getTM()
            snapshotValue.row1 == currentValue.row1 and snapshotValue.row2 == currentValue.row2 and
                snapshotValue.row3 == currentValue.row3 and snapshotValue.row4 == currentValue.row4
        )
    ),

    fn distanceSq2D a b =
    (
        local dx = a.x-b.x
        local dy = a.y-b.y
        dx*dx + dy*dy
    ),

    fn segmentDistanceSq2D p a b =
    (
        local abx = b.x-a.x
        local aby = b.y-a.y
        local lengthSq = abx*abx + aby*aby
        if lengthSq < 0.000001 then distanceSq2D p a
        else
        (
            local t = ((p.x-a.x)*abx + (p.y-a.y)*aby)/lengthSq
            if t < 0.0 then t = 0.0
            if t > 1.0 then t = 1.0
            local q = [a.x+abx*t,a.y+aby*t]
            distanceSq2D p q
        )
    ),

    fn pointInPolygon2D p points =
    (
        if points.count < 3 then false
        else
        (
            local inside = false
            local previousIndex = points.count
            for currentIndex = 1 to points.count do
            (
                local currentPoint = points[currentIndex]
                local previousPoint = points[previousIndex]
                if ((currentPoint.y > p.y) != (previousPoint.y > p.y)) do
                (
                    local denominator = previousPoint.y-currentPoint.y
                    if abs denominator < 0.000001 then denominator = 0.000001
                    local crossingX = (previousPoint.x-currentPoint.x)*(p.y-currentPoint.y)/denominator + currentPoint.x
                    if p.x < crossingX do inside = not inside
                )
                previousIndex = currentIndex
            )
            inside
        )
    ),

    fn cross2D a b c =
    (
        (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x)
    ),

    fn pointInTriangleStrict2D p a b c epsilonValue =
    (
        local c1 = cross2D a b p
        local c2 = cross2D b c p
        local c3 = cross2D c a p
        local allPositive = c1 > epsilonValue and c2 > epsilonValue and c3 > epsilonValue
        local allNegative = c1 < -epsilonValue and c2 < -epsilonValue and c3 < -epsilonValue
        allPositive or allNegative
    ),

    fn quadHasInteriorVertex2D points =
    (
        if points.count != 4 then true
        else
        (
            local inside = false
            for pointIndex = 1 to 4 while not inside do
            (
                local otherPoints = #()
                for otherIndex = 1 to 4 where otherIndex != pointIndex do append otherPoints points[otherIndex]
                if pointInTriangleStrict2D points[pointIndex] otherPoints[1] otherPoints[2] otherPoints[3] 0.01 do inside = true
            )
            inside
        )
    ),

    fn strictConvexQuad2D points =
    (
        if points.count != 4 then false
        else
        (
            local valid = true
            local windingSign = 0
            for pointIndex = 1 to 4 while valid do
            (
                local nextIndex = if pointIndex == 4 then 1 else pointIndex+1
                local nextNextIndex = if nextIndex == 4 then 1 else nextIndex+1
                local turnValue = cross2D points[pointIndex] points[nextIndex] points[nextNextIndex]
                if abs turnValue < 10.0 then valid = false
                else
                (
                    local currentSign = if turnValue > 0.0 then 1 else -1
                    if windingSign == 0 then windingSign = currentSign
                    else if currentSign != windingSign do valid = false
                )
            )
            valid
        )
    ),

    fn segmentsProperlyIntersect2D a b c d epsilonValue =
    (
        local abC = cross2D a b c
        local abD = cross2D a b d
        local cdA = cross2D c d a
        local cdB = cross2D c d b
        (((abC > epsilonValue and abD < -epsilonValue) or (abC < -epsilonValue and abD > epsilonValue)) and
         ((cdA > epsilonValue and cdB < -epsilonValue) or (cdA < -epsilonValue and cdB > epsilonValue)))
    ),

    fn coherentQuad3D points =
    (
        if points.count != 4 then false
        else
        (
            local normalA = cross (points[2]-points[1]) (points[3]-points[1])
            local normalB = cross (points[3]-points[1]) (points[4]-points[1])
            local lengthA = length normalA
            local lengthB = length normalB
            if lengthA < 0.000001 or lengthB < 0.000001 then false
            else (dot (normalA/lengthA) (normalB/lengthB)) > 0.05
        )
    ),

    fn vertexKind ownerNode vertexIndex =
    (
        local vertexBits = #{}
        vertexBits[vertexIndex] = true
        local usingFaces = try (polyOp.getFacesUsingVert ownerNode vertexBits) catch (#{} )
        if usingFaces.numberSet == 0 then #loose
        else
        (
            local usingEdges = try (polyOp.getEdgesUsingVert ownerNode vertexBits) catch (#{} )
            local boundaryCount = 0
            for edgeIndex in usingEdges do
            (
                local edgeBits = #{}
                edgeBits[edgeIndex] = true
                local edgeFaces = try (polyOp.getFacesUsingEdge ownerNode edgeBits) catch (#{} )
                if edgeFaces.numberSet == 1 do boundaryCount += 1
            )
            if boundaryCount > 0 then #boundary else #internalBlocked
        )
    ),

    fn stepBuildCandidateIds ownerNode ids sourceOnly:false =
    (
        local filterName = if sourceOnly then #MQDNativeV16FilterStepBuildSourceIds else #MQDNativeV16FilterStepBuildIds
        local filterFn = try (globalVars.get filterName) catch (undefined)
        local filtered = if filterFn == undefined then undefined else (try (filterFn ownerNode ids) catch (undefined))
        if filtered == undefined then #{} else (filtered as bitArray)
    ),

    fn refreshVisibleCaches =
    (
        visibleIds = #()
        visibleWorld = #()
        visibleScreen = #()
        eligibleIds = #()
        eligibleWorld = #()
        eligibleScreen = #()
        eligibleKinds = #()
        quadSourceIds = #()
        quadSourceScreen = #()
        blockedIds = #()
        blockedWorld = #()

        local ownerNode = MayaQuadDrawR1.ownerNode
        if not isValidNode ownerNode then false
        else
        (
            gw.setTransform (matrix3 1)
            local winX = gw.getWinSizeX()
            local winY = gw.getWinSizeY()
            local deadVerts = try (polyOp.getDeadVerts ownerNode) catch (#{} )
            local liveIds = for i = 1 to (polyOp.getNumVerts ownerNode) where not deadVerts[i] collect i
            local surfaceIds = MayaQuadDrawR1.surfaceLayerIds liveIds
            local facingIds = stepBuildCandidateIds ownerNode (surfaceIds as array)
            local sourceIds = stepBuildCandidateIds ownerNode (surfaceIds as array) sourceOnly:true

            for vertexIndex = 1 to (polyOp.getNumVerts ownerNode) where surfaceIds[vertexIndex] do
            (
                local worldPoint = getWorldVertex ownerNode vertexIndex
                if worldPoint != undefined do
                (
                    local screenPoint3 = gw.wTransPoint worldPoint
                    if screenPoint3 != undefined and screenPoint3.x >= 0 and screenPoint3.x < winX and screenPoint3.y >= 0 and screenPoint3.y < winY do
                    (
                        local screenPoint = [screenPoint3.x as float,screenPoint3.y as float]
                        append visibleIds vertexIndex
                        append visibleWorld worldPoint
                        append visibleScreen screenPoint
                        if sourceIds[vertexIndex] do
                        (
                            append quadSourceIds vertexIndex
                            append quadSourceScreen screenPoint
                        )

                        local kindValue = vertexKind ownerNode vertexIndex
                        if kindValue == #internalBlocked then
                        (
                            append blockedIds vertexIndex
                            append blockedWorld worldPoint
                        )
                        else if facingIds[vertexIndex] then
                        (
                            append eligibleIds vertexIndex
                            append eligibleWorld worldPoint
                            append eligibleScreen screenPoint
                            append eligibleKinds kindValue
                        )
                    )
                )
            )
            true
        )
    ),

    fn faceAlreadyExists ownerNode candidateBits =
    (
        local found = false
        local deadFaces = try (polyOp.getDeadFaces ownerNode) catch (#{} )
        for faceIndex = 1 to (polyOp.getNumFaces ownerNode) while not found do
        (
            if not deadFaces[faceIndex] do
            (
                local faceBits = #{}
                local faceVerts = try (polyOp.getFaceVerts ownerNode faceIndex) catch (#())
                for vertexIndex in faceVerts do faceBits[vertexIndex] = true
                if faceBits == candidateBits do found = true
            )
        )
        found
    ),

    fn edgeFaceCount ownerNode vertexA vertexB =
    (
        local bitsA = #{}
        local bitsB = #{}
        bitsA[vertexA] = true
        bitsB[vertexB] = true
        local edgesA = try (polyOp.getEdgesUsingVert ownerNode bitsA) catch (#{} )
        local edgesB = try (polyOp.getEdgesUsingVert ownerNode bitsB) catch (#{} )
        local sharedEdges = edgesA*edgesB
        if sharedEdges.numberSet == 0 then 0
        else
        (
            local usingFaces = try (polyOp.getFacesUsingEdge ownerNode sharedEdges) catch (#{} )
            usingFaces.numberSet
        )
    ),

    fn candidateReusesFaceTriple ownerNode candidateBits =
    (
        -- Native Step Build rejects three or more proposed vertices on one
        -- existing face, even when the two shared sides are boundary edges.
        local adjacentFaces = try (polyOp.getFacesUsingVert ownerNode candidateBits) catch (#{} )
        local deadFaces = try (polyOp.getDeadFaces ownerNode) catch (#{} )
        local found = false
        for faceIndex in adjacentFaces while not found where not deadFaces[faceIndex] do
        (
            local faceBits = #{}
            for vertexIndex in (polyOp.getFaceVerts ownerNode faceIndex) do faceBits[vertexIndex] = true
            if (faceBits*candidateBits).numberSet >= 3 do found = true
        )
        found
    ),

    fn edgeIndexBetween ownerNode vertexA vertexB =
    (
        local bitsA = #{}
        local bitsB = #{}
        bitsA[vertexA] = true
        bitsB[vertexB] = true
        local edgesA = try (polyOp.getEdgesUsingVert ownerNode bitsA) catch (#{} )
        local edgesB = try (polyOp.getEdgesUsingVert ownerNode bitsB) catch (#{} )
        local sharedEdges = edgesA*edgesB
        local result = 0
        for edgeIndex in sharedEdges while result == 0 do result = edgeIndex
        result
    ),

    fn edgeExists ownerNode vertexA vertexB =
    (
        (edgeIndexBetween ownerNode vertexA vertexB) > 0
    ),

    fn faceDirectedEdgeSign ownerNode faceIndex vertexA vertexB =
    (
        local faceVerts = try (polyOp.getFaceVerts ownerNode faceIndex) catch (#())
        local result = 0
        for vertexPosition = 1 to faceVerts.count while result == 0 do
        (
            local nextPosition = if vertexPosition == faceVerts.count then 1 else vertexPosition+1
            if faceVerts[vertexPosition] == vertexA and faceVerts[nextPosition] == vertexB then result = 1
            else if faceVerts[vertexPosition] == vertexB and faceVerts[nextPosition] == vertexA then result = -1
        )
        result
    ),

    fn sideCutsExistingFace ownerNode vertexA vertexB =
    (
        -- A proposed boundary side must not use two non-neighboring vertices
        -- of an existing polygon.  Such a side is that face's internal
        -- diagonal and would lay the new face through/over the old one.
        if edgeExists ownerNode vertexA vertexB then false
        else
        (
            local bitsA = #{}
            local bitsB = #{}
            bitsA[vertexA] = true
            bitsB[vertexB] = true
            local facesA = try (polyOp.getFacesUsingVert ownerNode bitsA) catch (#{} )
            local facesB = try (polyOp.getFacesUsingVert ownerNode bitsB) catch (#{} )
            local sharedFaces = facesA*facesB
            local cutsFace = false

            for faceIndex in sharedFaces while not cutsFace do
            (
                if (faceDirectedEdgeSign ownerNode faceIndex vertexA vertexB) == 0 do cutsFace = true
            )
            cutsFace
        )
    ),

    fn candidateWindingConsistent ownerNode orderedIds =
    (
        local valid = true
        local sharedDirection = 0
        local pointCount = orderedIds.count
        for pointIndex = 1 to pointCount while valid do
        (
            local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
            local edgeIndex = edgeIndexBetween ownerNode orderedIds[pointIndex] orderedIds[nextIndex]
            if edgeIndex > 0 do
            (
                local edgeBits = #{}
                edgeBits[edgeIndex] = true
                local edgeFaces = try (polyOp.getFacesUsingEdge ownerNode edgeBits) catch (#{} )
                if edgeFaces.numberSet == 1 do
                (
                    local faceIndex = 0
                    for value in edgeFaces while faceIndex == 0 do faceIndex = value
                    local directionValue = faceDirectedEdgeSign ownerNode faceIndex orderedIds[pointIndex] orderedIds[nextIndex]
                    if directionValue != 0 do
                    (
                        if sharedDirection == 0 then sharedDirection = directionValue
                        else if directionValue != sharedDirection do valid = false
                    )
                )
            )
        )
        valid
    ),

    fn localCandidateFrame orderedWorld =
    (
        if orderedWorld.count < 3 then undefined
        else
        (
        local edgeU = orderedWorld[2]-orderedWorld[1]
        local normalValue = cross (orderedWorld[2]-orderedWorld[1]) (orderedWorld[3]-orderedWorld[1])
        if orderedWorld.count == 4 do normalValue += cross (orderedWorld[3]-orderedWorld[1]) (orderedWorld[4]-orderedWorld[1])
        if length edgeU < 0.000001 or length normalValue < 0.000001 then undefined
        else
        (
            edgeU = normalize edgeU
            normalValue = normalize normalValue
            local edgeV = normalize (cross normalValue edgeU)
            #(orderedWorld[1],edgeU,edgeV,normalValue)
        )
        )
    ),

    fn projectToCandidateFrame worldPoint frameValue =
    (
        local deltaValue = worldPoint-frameValue[1]
        [dot deltaValue frameValue[2],dot deltaValue frameValue[3]]
    ),

    fn candidateAverageEdgeLength orderedWorld =
    (
        local pointCount = orderedWorld.count
        if pointCount < 3 then 0.0
        else
        (
        local result = 0.0
        for pointIndex = 1 to pointCount do
        (
            local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
            result += distance orderedWorld[pointIndex] orderedWorld[nextIndex]
        )
        result/(pointCount as float)
        )
    ),

    fn candidateSwallowsLocalVertex ownerNode orderedIds orderedWorld =
    (
        local frameValue = localCandidateFrame orderedWorld
        if frameValue == undefined then true
        else
        (
            local candidateScale = candidateAverageEdgeLength orderedWorld
            local planeTolerance = amax 0.0001 (candidateScale*0.035)
            local localPolygon = for worldPoint in orderedWorld collect (projectToCandidateFrame worldPoint frameValue)
            local candidateBits = #{}
            for vertexIndex in orderedIds do candidateBits[vertexIndex] = true
            local found = false

            for visibleIndex = 1 to visibleIds.count while not found where not candidateBits[visibleIds[visibleIndex]] do
            (
                local worldPoint = visibleWorld[visibleIndex]
                if worldPoint != undefined do
                (
                    local planeDistance = abs (dot (worldPoint-frameValue[1]) frameValue[4])
                    if planeDistance <= planeTolerance do
                    (
                        local localPoint = projectToCandidateFrame worldPoint frameValue
                        if pointInPolygon2D localPoint localPolygon do found = true
                    )
                )
            )
            found
        )
    ),

    fn candidateCrossesExistingEdge ownerNode orderedIds orderedWorld =
    (
        local frameValue = localCandidateFrame orderedWorld
        if frameValue == undefined then true
        else
        (
            local candidateScale = candidateAverageEdgeLength orderedWorld
            local planeTolerance = amax 0.0001 (candidateScale*0.035)
            local crossTolerance = amax 0.000001 (candidateScale*candidateScale*0.00001)
            local localCandidate = for worldPoint in orderedWorld collect (projectToCandidateFrame worldPoint frameValue)
            local deadEdges = try (polyOp.getDeadEdges ownerNode) catch (#{} )
            local found = false
            local pointCount = orderedIds.count

            for sideIndex = 1 to pointCount while not found do
            (
                local nextSideIndex = if sideIndex == pointCount then 1 else sideIndex+1
                local sideAId = orderedIds[sideIndex]
                local sideBId = orderedIds[nextSideIndex]
                if not edgeExists ownerNode sideAId sideBId do
                (
                    for edgeIndex = 1 to (polyOp.getNumEdges ownerNode) while not found where not deadEdges[edgeIndex] do
                    (
                        local edgeVerts = try (polyOp.getEdgeVerts ownerNode edgeIndex) catch (#())
                        if edgeVerts.count == 2 and edgeVerts[1] != sideAId and edgeVerts[2] != sideAId and edgeVerts[1] != sideBId and edgeVerts[2] != sideBId do
                        (
                            local edgeWorldA = getWorldVertex ownerNode edgeVerts[1]
                            local edgeWorldB = getWorldVertex ownerNode edgeVerts[2]
                            if edgeWorldA != undefined and edgeWorldB != undefined do
                            (
                                local planeDistanceA = abs (dot (edgeWorldA-frameValue[1]) frameValue[4])
                                local planeDistanceB = abs (dot (edgeWorldB-frameValue[1]) frameValue[4])
                                if planeDistanceA <= planeTolerance and planeDistanceB <= planeTolerance do
                                (
                                    local edgeLocalA = projectToCandidateFrame edgeWorldA frameValue
                                    local edgeLocalB = projectToCandidateFrame edgeWorldB frameValue
                                    if segmentsProperlyIntersect2D localCandidate[sideIndex] localCandidate[nextSideIndex] edgeLocalA edgeLocalB crossTolerance do found = true
                                )
                            )
                        )
                    )
                )
            )
            found
        )
    ),

    fn orderSourcesByAngle sourceIndices =
    (
        local center = [0.0,0.0]
        for sourceIndex in sourceIndices do center += eligibleScreen[sourceIndex]
        center /= (sourceIndices.count as float)

        local angles = for sourceIndex in sourceIndices collect
        (
            local pointValue = eligibleScreen[sourceIndex]
            atan2 (pointValue.y-center.y) (pointValue.x-center.x)
        )

        local used = #{}
        local ordered = #()
        for orderIndex = 1 to sourceIndices.count do
        (
            local bestPosition = 0
            local bestAngle = 1.0e20
            for positionIndex = 1 to sourceIndices.count where not used[positionIndex] do
            (
                if angles[positionIndex] < bestAngle do
                (
                    bestAngle = angles[positionIndex]
                    bestPosition = positionIndex
                )
            )
            used[bestPosition] = true
            append ordered sourceIndices[bestPosition]
        )
        ordered
    ),

    fn nearestQuadIds p =
    (
        local radius = amax 120.0 (amin 640.0 ((gw.getWinSizeX() as float)*candidateRadiusFactor))
        local ids = #()
        local distances = #()
        for i = 1 to quadSourceIds.count do
        (
            local d2 = distanceSq2D p quadSourceScreen[i]
            if d2 <= radius*radius do
            (
                local slot = 1
                while slot <= ids.count and (distances[slot] < d2 or (distances[slot] == d2 and ids[slot] < quadSourceIds[i])) do slot += 1
                insertItem quadSourceIds[i] ids slot
                insertItem d2 distances slot
                if ids.count > 4 do (ids.count = 4; distances.count = 4)
            )
        )
        ids
    ),

    fn validateCandidateGeometry ownerNode orderedIds orderedWorld orderedScreen runLocalChecks:true =
    (
        lastValidationReason = "Valid Step Build candidate with MQD geometry guards"
        local pointCount = orderedIds.count
        local isTriangle = pointCount == 3
        local isQuad = pointCount == 4
        local valid = (isTriangle or isQuad) and orderedWorld.count == pointCount and orderedScreen.count == pointCount
        local existingBoundaryEdges = 0
        local candidateBits = #{}
        if valid do for vertexIndex in orderedIds do candidateBits[vertexIndex] = true

        if valid and candidateBits.numberSet != pointCount do
        (
            valid = false
            lastValidationReason = "Repeated vertex"
        )

        if valid and faceAlreadyExists ownerNode candidateBits do
        (
            valid = false
            lastValidationReason = "Face already exists"
        )

        if valid and candidateReusesFaceTriple ownerNode candidateBits do
        (
            valid = false
            lastValidationReason = "Step Build rejects three candidate vertices belonging to one existing face"
        )

        local twiceArea = 0.0
        if valid do
        (
            for pointIndex = 1 to pointCount do
            (
                local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
                twiceArea += orderedScreen[pointIndex].x*orderedScreen[nextIndex].y - orderedScreen[nextIndex].x*orderedScreen[pointIndex].y
            )
            if abs twiceArea < (if isTriangle then 200.0 else 400.0) do
            (
                valid = false
                lastValidationReason = "Projected face is too small or degenerate"
            )
        )

        if valid and isQuad and quadHasInteriorVertex2D orderedScreen do
        (
            valid = false
            lastValidationReason = "One candidate point lies inside the other three"
        )

        if valid and isQuad and not (strictConvexQuad2D orderedScreen) do
        (
            valid = false
            lastValidationReason = "Concave or self-folded projected quad"
        )

        if valid and isQuad and not (coherentQuad3D orderedWorld) do
        (
            valid = false
            lastValidationReason = "Quad triangles fold through each other in 3D"
        )

        if valid and isQuad and (edgeExists ownerNode orderedIds[1] orderedIds[3] or edgeExists ownerNode orderedIds[2] orderedIds[4]) do
        (
            valid = false
            lastValidationReason = "Existing diagonal already divides this region"
        )

        if valid do
        (
            for pointIndex = 1 to pointCount while valid do
            (
                local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
                local sideAId = orderedIds[pointIndex]
                local sideBId = orderedIds[nextIndex]
                local faceUseCount = edgeFaceCount ownerNode sideAId sideBId
                if sideCutsExistingFace ownerNode sideAId sideBId then
                (
                    valid = false
                    lastValidationReason = "A new side would cut across an existing face"
                )
                else if isTriangle and faceUseCount != 1 then
                (
                    valid = false
                    lastValidationReason = "Triangle is not one closed three-edge boundary hole"
                )
                else if faceUseCount >= 2 then
                (
                    valid = false
                    lastValidationReason = "A side is already used by two faces"
                )
                else if faceUseCount == 1 do existingBoundaryEdges += 1
            )
        )

        if valid and not (candidateWindingConsistent ownerNode orderedIds) do
        (
            valid = false
            lastValidationReason = "Neighboring boundary winding is inconsistent"
        )

        if valid and runLocalChecks and candidateSwallowsLocalVertex ownerNode orderedIds orderedWorld do
        (
            valid = false
            lastValidationReason = "Candidate would cover an existing local vertex"
        )

        if valid and runLocalChecks and candidateCrossesExistingEdge ownerNode orderedIds orderedWorld do
        (
            valid = false
            lastValidationReason = "A new side would cross an existing local edge"
        )

        if valid and runLocalChecks do
        (
            for visibleIndex = 1 to visibleIds.count while valid where candidateBits[visibleIds[visibleIndex]] == false do
            (
                for pointIndex = 1 to pointCount while valid do
                (
                    local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
                    if segmentDistanceSq2D visibleScreen[visibleIndex] orderedScreen[pointIndex] orderedScreen[nextIndex] < 25.0 do
                    (
                        valid = false
                        lastValidationReason = "A new side passes through an existing vertex"
                    )
                )
            )
        )

        #(valid,existingBoundaryEdges)
    ),

    fn validateCandidateIds ownerNode orderedIds =
    (
        local orderedWorld = #()
        local orderedScreen = #()
        if orderedIds.count == 3 or orderedIds.count == 4 do
        (
            gw.setTransform (matrix3 1)
            for vertexIndex in orderedIds do
            (
                local worldPoint = getWorldVertex ownerNode vertexIndex
                if worldPoint != undefined do
                (
                    local screenPoint3 = gw.wTransPoint worldPoint
                    if screenPoint3 != undefined do
                    (
                        append orderedWorld worldPoint
                        append orderedScreen [screenPoint3.x as float,screenPoint3.y as float]
                    )
                )
            )
        )
        validateCandidateGeometry ownerNode orderedIds orderedWorld orderedScreen runLocalChecks:true
    ),

    fn candidatePassesGeometry ownerNode orderedSources =
    (
        local orderedIds = for sourceIndex in orderedSources collect eligibleIds[sourceIndex]
        local orderedWorld = for sourceIndex in orderedSources collect eligibleWorld[sourceIndex]
        local orderedScreen = for sourceIndex in orderedSources collect eligibleScreen[sourceIndex]
        validateCandidateGeometry ownerNode orderedIds orderedWorld orderedScreen runLocalChecks:false
    ),

    fn candidatePassesVisibleSurface ownerNode orderedIds p =
    (
        -- Preview shortlist and commit use the same Step Build domain. Keep
        -- layer visibility separate so ordinary hover and obstacle geometry
        -- retain their tested semantics at folds and front-layer holes.
        local visibleBits = MayaQuadDrawR1.surfaceLayerIds orderedIds
        local facingBits = stepBuildCandidateIds ownerNode orderedIds
        visibleBits = visibleBits * facingBits
        local allVisible = visibleBits.numberSet == orderedIds.count
        for vertexIndex in orderedIds while allVisible where not visibleBits[vertexIndex] do allVisible = false
        allVisible
    ),

    fn prepareCandidateCycle ownerNode orderedIds =
    (
        local prepareFn = try (globalVars.get #MQDNativeV16PrepareStepBuildFace) catch (undefined)
        local prepared = if prepareFn == undefined then undefined else (try (prepareFn ownerNode orderedIds) catch (undefined))
        if prepared == undefined do lastValidationReason = "Native Step Build rejects overlapping or reverse-facing result"
        prepared
    ),

    fn prepareCandidateSources ownerNode orderedSources =
    (
        local ids = for sourceIndex in orderedSources collect eligibleIds[sourceIndex]
        local prepared = prepareCandidateCycle ownerNode ids
        if prepared == undefined then #() else (for vertexIndex in prepared collect (findItem eligibleIds vertexIndex))
    ),

    fn candidateContainsEdge ownerNode orderedIds edgeIndex =
    (
        local edgeVerts = try (polyOp.getEdgeVerts ownerNode edgeIndex) catch (#())
        if edgeVerts.count != 2 then false
        else
        (
            local found = false
            local pointCount = orderedIds.count
            for pointIndex = 1 to pointCount while not found do
            (
                local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
                if (orderedIds[pointIndex] == edgeVerts[1] and orderedIds[nextIndex] == edgeVerts[2]) or
                   (orderedIds[pointIndex] == edgeVerts[2] and orderedIds[nextIndex] == edgeVerts[1]) do found = true
            )
            found
        )
    ),

    fn polygonOutlineDistanceSq p polygonPoints =
    (
        if pointInPolygon2D p polygonPoints then 0.0
        else
        (
            local best = 1.0e20
            local pointCount = polygonPoints.count
            for pointIndex = 1 to pointCount do
            (
                local nextIndex = if pointIndex == pointCount then 1 else pointIndex+1
                local value = segmentDistanceSq2D p polygonPoints[pointIndex] polygonPoints[nextIndex]
                if value < best do best = value
            )
            best
        )
    ),

    fn quadCursorMatches ownerNode orderedIds orderedScreen p =
    (
        local bits = orderedIds as bitArray
        local hoverMatch = case MayaQuadDrawR1.hoverLevel of
        (
            #vertex: bits[MayaQuadDrawR1.hoverIndex]
            #boundaryEdge: candidateContainsEdge ownerNode orderedIds MayaQuadDrawR1.hoverIndex
            #surfaceBlank: true
            default: false
        )
        if not hoverMatch then false
        else
        (
            local farthest = 400.0
            local minSide = 1.0e20
            for i = 1 to 4 do
            (
                farthest = amax farthest (distanceSq2D p orderedScreen[i])
                minSide = amin minSide (distanceSq2D orderedScreen[i] orderedScreen[(mod i 4)+1])
            )
            local tolerance = amax 14.0 (amin candidateOutlineTolerance ((sqrt farthest)*0.55))
            minSide >= 25.0 and (MayaQuadDrawR1.hoverLevel != #surfaceBlank or
                pointInPolygon2D p orderedScreen or (polygonOutlineDistanceSq p orderedScreen) <= tolerance*tolerance)
        )
    ),

    fn triangleHoverMatches orderedScreen p =
    (
        MayaQuadDrawR1.hoverLevel == #surfaceBlank and pointInPolygon2D p orderedScreen
    ),

    fn validateCandidateForCommit ownerNode orderedIds p =
    (
        if not candidateValid or candidateOwner != ownerNode or candidateTarget != MayaQuadDrawR1.targetNode or
            candidateTime != currentTime or not (sameViewTransform candidateViewTM) or candidateViewSize != getViewSize() or
            (orderedIds as string) != (candidateVerts as string) do
        (
            lastValidationReason = "Displayed preview expired: owner, target, view, time or cycle changed"
            return #(false,0,undefined)
        )
        for i = 1 to orderedIds.count do
        (
            if (getWorldVertex ownerNode orderedIds[i]) != candidateWorld[i] do
            (
                lastValidationReason = "Displayed preview expired: candidate position changed"
                return #(false,0,undefined)
            )
        )
        -- Rebuild only the read-only input/obstacle caches, not the displayed
        -- candidate. A new nearest-four set invalidates this click.
        refreshVisibleCaches()
        if candidateKind == #quad and ((nearestQuadIds p) as bitArray) != (orderedIds as bitArray) do
        (
            lastValidationReason = "Displayed preview expired: nearest four changed"
            return #(false,0,undefined)
        )
        local geometryResult = validateCandidateIds ownerNode orderedIds
        if not geometryResult[1] then geometryResult
        else if not (candidatePassesVisibleSurface ownerNode orderedIds p) then
        (
            lastValidationReason = "Candidate is outside the visible layer or native Step Build boundary domain"
            #(false,geometryResult[2])
        )
        else
        (
            local currentSources = for id in orderedIds collect (findItem eligibleIds id)
            if (findItem currentSources 0) != 0 do
            (
                lastValidationReason = "Displayed preview expired: candidate is outside the current viewport cache"
                return #(false,geometryResult[2],undefined)
            )
            local currentScreen = for i in currentSources collect eligibleScreen[i]
            local cursorMatches = if candidateKind == #quad then (quadCursorMatches ownerNode orderedIds currentScreen p) else
                (triangleHoverMatches currentScreen p)
            if not cursorMatches do
            (
                lastValidationReason = "Displayed preview expired: cursor no longer belongs to this face region"
                return #(false,geometryResult[2],undefined)
            )
            local prepared = prepareCandidateCycle ownerNode orderedIds
            local sameCycle = prepared != undefined and (prepared as string) == (orderedIds as string)
            if not sameCycle do lastValidationReason = "Displayed preview expired: final winding changed"
            #(sameCycle,geometryResult[2],prepared)
        )
    ),

    fn buildClosedTriangleHoleCandidate p =
    (
        local ownerNode = MayaQuadDrawR1.ownerNode
        if not isValidNode ownerNode or eligibleIds.count < 3 then false
        else
        (
            gw.setTransform (matrix3 1)
            local winX = gw.getWinSizeX()
            local candidateRadius = amax 120.0 (amin 640.0 ((winX as float)*candidateRadiusFactor))
            local radiusSq = candidateRadius*candidateRadius
            local poolSources = #()
            local poolDistances = #()

            for sourceIndex = 1 to eligibleIds.count do
            (
                local d2 = distanceSq2D p eligibleScreen[sourceIndex]
                if d2 <= radiusSq do
                (
                    append poolSources sourceIndex
                    append poolDistances d2
                )
            )

            for sortIndex = 1 to poolSources.count do
            (
                local bestIndex = sortIndex
                for compareIndex = sortIndex+1 to poolSources.count do
                    if poolDistances[compareIndex] < poolDistances[bestIndex] do bestIndex = compareIndex
                if bestIndex != sortIndex do
                (
                    local tempSource = poolSources[sortIndex]
                    local tempDistance = poolDistances[sortIndex]
                    poolSources[sortIndex] = poolSources[bestIndex]
                    poolDistances[sortIndex] = poolDistances[bestIndex]
                    poolSources[bestIndex] = tempSource
                    poolDistances[bestIndex] = tempDistance
                )
            )

            if poolSources.count > candidatePoolLimit do
            (
                poolSources.count = candidatePoolLimit
                poolDistances.count = candidatePoolLimit
            )

            local bestOrdered = #()
            local bestScore = 1.0e30
            local poolCount = poolSources.count
            if poolCount >= 3 do
            (
                for a = 1 to poolCount-2 do
                for b = a+1 to poolCount-1 do
                for c = b+1 to poolCount do
                (
                    local orderedSources = orderSourcesByAngle #(poolSources[a],poolSources[b],poolSources[c])
                    local orderedIds = for sourceIndex in orderedSources collect eligibleIds[sourceIndex]
                    local orderedWorld = for sourceIndex in orderedSources collect eligibleWorld[sourceIndex]
                    local orderedScreen = for sourceIndex in orderedSources collect eligibleScreen[sourceIndex]
                    local passResult = validateCandidateGeometry ownerNode orderedIds orderedWorld orderedScreen runLocalChecks:true
                    if passResult[1] and passResult[2] == 3 and triangleHoverMatches orderedScreen p and candidatePassesVisibleSurface ownerNode orderedIds p do
                    (
                        local center = (orderedScreen[1]+orderedScreen[2]+orderedScreen[3])/3.0
                        local score = distanceSq2D p center
                        if score < bestScore do
                        (
                            local preparedSources = prepareCandidateSources ownerNode orderedSources
                            if preparedSources.count == 3 do
                            (
                                bestScore = score
                                bestOrdered = preparedSources
                            )
                        )
                    )
                )
            )

            if bestOrdered.count != 3 then false
            else
            (
                candidateVerts = for sourceIndex in bestOrdered collect eligibleIds[sourceIndex]
                candidateWorld = for sourceIndex in bestOrdered collect eligibleWorld[sourceIndex]
                candidateScreen = for sourceIndex in bestOrdered collect eligibleScreen[sourceIndex]
                candidateKind = #triangleHole
                candidateValid = true
                rememberCandidate()
                previewStatus = "Closed triangular hole - Shift-click to fill"
                recordPreviewIfChanged()
                true
            )
        )
    ),

    fn buildQuadCandidate p =
    (
        local ownerNode = MayaQuadDrawR1.ownerNode
        if not isValidNode ownerNode do (clearCandidate "Work mesh is invalid"; return false)
        local nearestIds = nearestQuadIds p
        if nearestIds.count != 4 do (clearCandidate "Fewer than four local Step Build source points"; return false)

        -- Select ONCE from the native facing source domain. An internal point
        -- in that set invalidates it; a fifth point cannot silently replace it.
        if not (candidatePassesVisibleSurface ownerNode nearestIds p) do
        (
            clearCandidate "Nearest four fail Step Build boundary/layer eligibility"
            return false
        )
        local sources = for id in nearestIds collect (findItem eligibleIds id)
        if (findItem sources 0) != 0 do (clearCandidate "Nearest four not available"; return false)
        local orderedSources = orderSourcesByAngle sources
        local orderedIds = for i in orderedSources collect eligibleIds[i]
        local orderedWorld = for i in orderedSources collect eligibleWorld[i]
        local orderedScreen = for i in orderedSources collect eligibleScreen[i]
        local fullPass = validateCandidateGeometry ownerNode orderedIds orderedWorld orderedScreen runLocalChecks:true
        if not fullPass[1] do (clearCandidate ("Nearest four rejected: " + lastValidationReason); return false)
        if not (quadCursorMatches ownerNode orderedIds orderedScreen p) do
        (
            clearCandidate "Nearest four do not own this cursor region"
            return false
        )
        local prepared = prepareCandidateSources ownerNode orderedSources
        if prepared.count != 4 do (clearCandidate lastValidationReason; return false)
        candidateVerts = for i in prepared collect eligibleIds[i]
        candidateWorld = for i in prepared collect eligibleWorld[i]
        candidateScreen = for i in prepared collect eligibleScreen[i]
        candidateKind = #quad
        candidateValid = true
        rememberCandidate()
        previewStatus = "Native Step Build nearest-four preview"
        recordPreviewIfChanged()
        true
    ),

    fn buildCandidate p =
    (
        if buildClosedTriangleHoleCandidate p then true else buildQuadCandidate p
    ),

    fn updatePreview p shiftValue =
    (
        if not active then false
        else
        (
            shiftHeld = shiftValue
            if not shiftValue then
            (
                visibleIds = #()
                eligibleIds = #()
                quadSourceIds = #()
                quadSourceScreen = #()
                blockedIds = #()
                blockedWorld = #()
                clearCandidate "Shift is up"
            )
            else
            (
                refreshVisibleCaches()
                case MayaQuadDrawR1.hoverLevel of
                (
                    #surfaceBlank: buildCandidate p
                    #boundaryEdge: buildCandidate p
                    #interiorEdge: clearCandidate "Two-sided interior edge cannot extend"
                    #vertex: buildCandidate p
                    #face: clearCandidate "Existing face owns the cursor"
                    #outsideSurface: clearCandidate "Cursor is outside the picked surface"
                    default: clearCandidate "No valid preview target"
                )
            )
            redrawViews()
            true
        )
    ),

    fn drawGhostPreview =
    (
        if active and shiftHeld do
        (
            gw.setTransform (matrix3 1)
            for worldPoint in eligibleWorld do gw.marker worldPoint #circle color:(color 70 220 135)
            for worldPoint in blockedWorld do gw.marker worldPoint #bigBox color:(color 255 70 90)
        )

        if active and candidateValid and (candidateWorld.count == 3 or candidateWorld.count == 4) do
        (
            gw.setTransform (matrix3 1)
            local fillColor = if candidateKind == #triangleHole then (color 120 45 160) else (color 25 100 120)
            local triangleColors = #(fillColor,fillColor,fillColor)
            local triangleUVW = #([0,0,0],[0,0,0],[0,0,0])
            try (gw.polygon #(candidateWorld[1],candidateWorld[2],candidateWorld[3]) triangleColors triangleUVW) catch()
            if candidateWorld.count == 4 do try (gw.polygon #(candidateWorld[1],candidateWorld[3],candidateWorld[4]) triangleColors triangleUVW) catch()
            gw.setColor #line (if candidateKind == #triangleHole then (color 215 105 255) else (color 80 255 225))
            gw.polyline candidateWorld true
            for worldPoint in candidateWorld do gw.marker worldPoint #bigBox color:(if candidateKind == #triangleHole then (color 230 125 255) else (color 115 255 225))
        )

        true
    ),

    fn onToolStart =
    (
        active = true
        shiftHeld = false
        candidateValid = false
        candidateKind = #none
        candidateVerts = #()
        blockedIds = #()
        blockedWorld = #()
        previewStatus = "Shift is up"
        lastPreviewKey = ""
        if not doesFileExist logPath do initializeLog()
        try (unregisterRedrawViewsCallback MayaQuadDrawR3_DrawCallback) catch()
        registerRedrawViewsCallback MayaQuadDrawR3_DrawCallback
        recordPreviewIfChanged()
        completeRedraw()
        format "MQD R16 triangle-hole and quad preview started. Geometry commands are disabled.\n"
        true
    ),

    fn onToolStop =
    (
        active = false
        shiftHeld = false
        candidateValid = false
        candidateKind = #none
        candidateVerts = #()
        candidateWorld = #()
        candidateScreen = #()
        blockedIds = #()
        blockedWorld = #()
        try (unregisterRedrawViewsCallback MayaQuadDrawR3_DrawCallback) catch()
        appendLog "stopped=true"
        completeRedraw()
        format "MQD R16 preview stopped. Geometry was not modified.\n"
        true
    )
)

MayaQuadDrawR3 = MayaQuadDrawR3State()

fn MayaQuadDrawR3_DrawCallback =
(
    if MayaQuadDrawR3 != undefined do MayaQuadDrawR3.drawGhostPreview()
)

tool MayaQuadDrawR3Tool prompt:"MQD R16 internal Relax; RMB or Esc exits"
(
    on start do
    (
        global MayaQuadDrawR1
        global MayaQuadDrawR3
        MayaQuadDrawR1.onToolStart()
        MayaQuadDrawR3.onToolStart()
    )

    on freeMove do
    (
        global MayaQuadDrawR1
        global MayaQuadDrawR3
        MayaQuadDrawR1.updateHover viewPoint shiftKey ctrlKey altKey mButton
        MayaQuadDrawR3.updatePreview viewPoint shiftKey
    )

    on mouseMove clickNo do
    (
        global MayaQuadDrawR1
        global MayaQuadDrawR3
        MayaQuadDrawR1.updateHover viewPoint shiftKey ctrlKey altKey mButton
        MayaQuadDrawR3.updatePreview viewPoint shiftKey
    )

    on mousePoint clickNo do
    (
        global MayaQuadDrawR1
        global MayaQuadDrawR3
        MayaQuadDrawR1.recordMousePoint clickNo viewPoint shiftKey ctrlKey altKey
        MayaQuadDrawR3.appendLog ("mousePoint=" + (clickNo as string) + " previewOnly=true")
    )

    on mouseAbort clickNo do #stop

    on stop do
    (
        global MayaQuadDrawR1
        global MayaQuadDrawR3
        MayaQuadDrawR3.onToolStop()
        MayaQuadDrawR1.onToolStop()
    )
)

fn MayaQuadDrawR3_Start =
(
    if MayaQuadDrawR3.active then true
    else if MayaQuadDrawR1.prepare() then
    (
        startTool MayaQuadDrawR3Tool prompt:"MQD R16 internal Relax; RMB or Esc exits"
        true
    )
    else false
)

fn MayaQuadDrawR3_Stop =
(
    if MayaQuadDrawR3 != undefined and MayaQuadDrawR3.active do
    (
        try (stopTool MayaQuadDrawR3Tool) catch
        (
            MayaQuadDrawR3.onToolStop()
            try (MayaQuadDrawR1.onToolStop()) catch()
        )
    )
    true
)

format "MQD R16 candidate preview loaded. Run MayaQuadDrawR3_Start().\n"
