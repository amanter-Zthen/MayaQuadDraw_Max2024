/*
    Maya Quad Draw - Round 1 read-only recognition lab for 3ds Max 2024.

    Positive contract:
    - Classify work-mesh vertex, boundary edge, interior edge, face,
      blank picked-surface area, and outside-surface area.
    - Draw a viewport-only preview and write compact state-change logs.
    - Preserve geometry and component selections exactly as they are.
*/

global MayaQuadDrawR1
global MayaQuadDrawR1Tool
global MayaQuadDrawR1_DrawCallback
global MayaQuadDrawR1_Start
global MayaQuadDrawR1_Stop
global MayaQuadDrawR1_Toggle
global PolyToolsUI
global PBo_Pickobject
global MayaQuadDrawRootPath

try
(
    if MayaQuadDrawR1 != undefined and MayaQuadDrawR1.active do stopTool MayaQuadDrawR1Tool
)
catch()

try (unregisterRedrawViewsCallback MayaQuadDrawR1_DrawCallback) catch()

struct MayaQuadDrawR1State
(
    active = false,
    ownerNode = undefined,
    targetNode = undefined,

    drawType = 2,
    offset = 0.0,
    distanceType = 1,
    weldDistance = 10.0,

    hoverLevel = #none,
    hoverIndex = 0,
    hoverWorld = [0,0,0],
    hoverWorldPoints = #(),
    hoverViewPoint = [0,0],
    shiftDown = false,

    lastTick = 0,
    hoverIntervalMs = 24,
    lastStateKey = "",
    statusText = "Not started",
    logPath = MayaQuadDrawRootPath + "logs\\MayaQuadDraw_Recognizer.log",

    fn isSupportedNode n =
    (
        isValidNode n and (try (classOf n.baseObject == Editable_Poly) catch (false))
    ),

    fn stateName level =
    (
        case level of
        (
            #vertex: "VERTEX"
            #boundaryEdge: "BOUNDARY EDGE"
            #interiorEdge: "INTERIOR EDGE"
            #face: "FACE"
            #surfaceBlank: "SURFACE BLANK"
            #outsideSurface: "OUTSIDE SURFACE"
            default: "NONE"
        )
    ),

    fn initializeLog =
    (
        local stream = undefined
        try (stream = createFile logPath) catch (stream = undefined)
        if stream != undefined do
        (
            format "MQD R1 READ-ONLY RECOGNITION\r\n" to:stream
            format "State changes only. Geometry commands are disabled.\r\n" to:stream
            close stream
        )
        true
    ),

    fn appendLog textValue =
    (
        local stream = undefined
        try (stream = openFile logPath mode:"a") catch (stream = undefined)
        if stream != undefined do
        (
            format "%\r\n" textValue to:stream
            close stream
        )
        true
    ),

    fn recordStateIfChanged =
    (
        local key = (hoverLevel as string) + ":" + (hoverIndex as string) + ":shift=" + (shiftDown as string)
        if key != lastStateKey do
        (
            lastStateKey = key
            local line = "state=" + (stateName hoverLevel) + " index=" + (hoverIndex as string) + " shift=" + (shiftDown as string)
            appendLog line
            format "MQD R1: %\n" line
        )
        true
    ),

    fn resetHover levelValue shiftValue =
    (
        hoverLevel = levelValue
        hoverIndex = 0
        hoverWorld = [0,0,0]
        hoverWorldPoints = #()
        shiftDown = shiftValue
        statusText = stateName levelValue
        recordStateIfChanged()
        true
    ),

    fn setHover levelValue indexValue worldPoint worldPoints shiftValue =
    (
        hoverLevel = levelValue
        hoverIndex = indexValue
        hoverWorld = worldPoint
        hoverWorldPoints = deepCopy worldPoints
        shiftDown = shiftValue
        statusText = (stateName levelValue) + (if indexValue > 0 then (" " + indexValue as string) else "")
        recordStateIfChanged()
        true
    ),

    fn syncSharedState =
    (
        try (drawType = PolyToolsUI.PDDrawtype) catch (drawType = 2)
        try (offset = PolyToolsUI.PDOffset) catch (offset = 0.0)
        try (distanceType = PolyToolsUI.PDDistanceType) catch (distanceType = 1)
        try (weldDistance = PolyToolsUI.PDDistance) catch (weldDistance = 10.0)
        try
        (
            targetNode = if isValidNode PBo_Pickobject then PBo_Pickobject else undefined
        )
        catch (targetNode = undefined)
        true
    ),

    fn prepare =
    (
        lastStateKey = ""
        syncSharedState()

        if selection.count != 1 then
        (
            ownerNode = undefined
            statusText = "Select exactly one Editable Poly work mesh"
            format "MQD R1: %\n" statusText
            false
        )
        else
        (
            ownerNode = selection[1]
            if not isSupportedNode ownerNode then
            (
                ownerNode = undefined
                statusText = "Selected work object must be Editable Poly"
                format "MQD R1: %\n" statusText
                false
            )
            else if not isValidNode targetNode then
            (
                statusText = "The picked PolyDraw surface is missing"
                format "MQD R1: %\n" statusText
                false
            )
            else if targetNode == ownerNode then
            (
                statusText = "Work mesh and picked surface must be separate nodes"
                format "MQD R1: %\n" statusText
                false
            )
            else
            (
                statusText = "Ready"
                true
            )
        )
    ),

    fn getWorldVertex nodeValue vertexIndex =
    (
        local result = undefined
        try (in coordsys world (result = polyOp.getVert nodeValue.baseObject vertexIndex node:nodeValue)) catch (result = undefined)
        result
    ),

    fn surfaceHitAt p =
    (
        if not isValidNode targetNode then undefined
        else
        (
            local hitFn = try (globalVars.get #MQDNativeV16SurfaceHit) catch (undefined)
            local hit = if hitFn == undefined then undefined else (try (hitFn targetNode p.x p.y offset) catch (undefined))
            if hit == undefined then undefined else ray hit[1] hit[2]
        )
    ),

    fn surfaceLayerIds ids =
    (
        local filterFn = try (globalVars.get #MQDNativeV16FilterSurfaceIds) catch (undefined)
        if filterFn == undefined or not isValidNode ownerNode or not isValidNode targetNode then #{}
        else
        (
            local layerTolerance = amax 0.001 ((abs offset) * 1.5)
            local result = try (filterFn ownerNode targetNode ids layerTolerance) catch (undefined)
            if result == undefined then #{} else result as bitarray
        )
    ),

    fn distanceSq2D a b =
    (
        local dx = a.x - b.x
        local dy = a.y - b.y
        dx*dx + dy*dy
    ),

    fn segmentDistanceSq2D p a b =
    (
        local abx = b.x - a.x
        local aby = b.y - a.y
        local lengthSq = abx*abx + aby*aby
        if lengthSq < 0.000001 then distanceSq2D p a
        else
        (
            local t = ((p.x-a.x)*abx + (p.y-a.y)*aby) / lengthSq
            if t < 0.0 then t = 0.0
            if t > 1.0 then t = 1.0
            local q = [a.x + abx*t, a.y + aby*t]
            distanceSq2D p q
        )
    ),

    fn pointInPolygon2D p points =
    (
        if points.count < 3 then false
        else
        (
            local inside = false
            local j = points.count
            for i = 1 to points.count do
            (
                local pi = points[i]
                local pj = points[j]
                if ((pi.y > p.y) != (pj.y > p.y)) do
                (
                    local denom = pj.y - pi.y
                    if abs denom < 0.000001 then denom = 0.000001
                    local crossingX = (pj.x-pi.x) * (p.y-pi.y) / denom + pi.x
                    if p.x < crossingX do inside = not inside
                )
                j = i
            )
            inside
        )
    ),

    fn classifyEdge edgeIndex =
    (
        local edgeSet = #{}
        edgeSet[edgeIndex] = true
        local usingFaces = try (polyOp.getFacesUsingEdge ownerNode.baseObject edgeSet) catch (#{} )
        if usingFaces.numberSet == 1 then #boundaryEdge
        else if usingFaces.numberSet >= 2 then #interiorEdge
        else #boundaryEdge
    ),

    fn updateHover p shiftValue ctrlDown altDown middleDown force:false =
    (
        if not active then false
        else if middleDown or altDown then true
        else
        (
            local nowTick = timeStamp()
            local elapsed = nowTick - lastTick
            if not force and elapsed >= 0 and elapsed < hoverIntervalMs then true
            else
            (
                lastTick = nowTick
                hoverViewPoint = p
                syncSharedState()

                if not isSupportedNode ownerNode then
                (
                    resetHover #none shiftValue
                    statusText = "Work object is no longer valid"
                    redrawViews()
                    false
                )
                else
                (
                    local vertexCount = polyOp.getNumVerts ownerNode.baseObject
                    local worldCache = for i = 1 to vertexCount collect undefined
                    local screenCache = for i = 1 to vertexCount collect undefined
                    local deadVerts = try (polyOp.getDeadVerts ownerNode.baseObject) catch (#{} )
                    local liveIds = for i = 1 to vertexCount where not deadVerts[i] collect i
                    local surfaceIds = surfaceLayerIds liveIds

                    gw.setTransform (matrix3 1)
                    local winX = gw.getWinSizeX()
                    local winY = gw.getWinSizeY()

                    local bestVertex = 0
                    local bestVertexDist = 1.0e20

                    for i = 1 to vertexCount where surfaceIds[i] do
                    (
                        local wp = getWorldVertex ownerNode i
                        if wp != undefined do
                        (
                            local sp = gw.wTransPoint wp
                            if sp != undefined and sp.x >= 0 and sp.x < winX and sp.y >= 0 and sp.y < winY do
                            (
                                local sp2 = [sp.x as float, sp.y as float]
                                worldCache[i] = wp
                                screenCache[i] = sp2
                                local d2 = distanceSq2D p sp2
                                if d2 < bestVertexDist do
                                (
                                    bestVertexDist = d2
                                    bestVertex = i
                                )
                            )
                        )
                    )

                    local vertexThreshold = if distanceType == 1 then amax 6.0 (amin 14.0 weldDistance) else 10.0
                    local edgeThreshold = amax 5.0 (vertexThreshold * 0.65)

                    if bestVertex > 0 and bestVertexDist <= vertexThreshold*vertexThreshold then
                    (
                        setHover #vertex bestVertex worldCache[bestVertex] #(worldCache[bestVertex]) shiftValue
                    )
                    else
                    (
                        local edgeCount = polyOp.getNumEdges ownerNode.baseObject
                        local deadEdges = try (polyOp.getDeadEdges ownerNode.baseObject) catch (#{} )
                        local bestEdge = 0
                        local bestEdgeDist = 1.0e20
                        local bestEdgeWorld = #()

                        for edgeIndex = 1 to edgeCount where not deadEdges[edgeIndex] do
                        (
                            local edgeVerts = try (polyOp.getEdgeVerts ownerNode.baseObject edgeIndex) catch (undefined)
                            if edgeVerts != undefined do
                            (
                                local aIndex = edgeVerts[1] as integer
                                local bIndex = edgeVerts[2] as integer
                                if aIndex > 0 and bIndex > 0 and screenCache[aIndex] != undefined and screenCache[bIndex] != undefined do
                                (
                                    local d2 = segmentDistanceSq2D p screenCache[aIndex] screenCache[bIndex]
                                    if d2 < bestEdgeDist do
                                    (
                                        bestEdgeDist = d2
                                        bestEdge = edgeIndex
                                        bestEdgeWorld = #(worldCache[aIndex], worldCache[bIndex])
                                    )
                                )
                            )
                        )

                        if bestEdge > 0 and bestEdgeDist <= edgeThreshold*edgeThreshold then
                        (
                            local edgeLevel = classifyEdge bestEdge
                            setHover edgeLevel bestEdge ((bestEdgeWorld[1]+bestEdgeWorld[2])*0.5) bestEdgeWorld shiftValue
                        )
                        else
                        (
                            local faceCount = polyOp.getNumFaces ownerNode.baseObject
                            local deadFaces = try (polyOp.getDeadFaces ownerNode.baseObject) catch (#{} )
                            local bestFace = 0
                            local bestFaceDepth = 1.0e20
                            local bestFaceWorld = #()

                            for faceIndex = 1 to faceCount where not deadFaces[faceIndex] do
                            (
                                local faceVerts = try (polyOp.getFaceVerts ownerNode.baseObject faceIndex) catch (undefined)
                                if faceVerts != undefined and faceVerts.count >= 3 do
                                (
                                    local polygon2D = #()
                                    local polygonWorld = #()
                                    local depthTotal = 0.0
                                    local validFace = true

                                    for vertexIndex in faceVerts while validFace do
                                    (
                                        if screenCache[vertexIndex] == undefined then validFace = false
                                        else
                                        (
                                            append polygon2D screenCache[vertexIndex]
                                            append polygonWorld worldCache[vertexIndex]
                                            local sp = gw.wTransPoint worldCache[vertexIndex]
                                            depthTotal += sp.z
                                        )
                                    )

                                    if validFace and pointInPolygon2D p polygon2D do
                                    (
                                        local averageDepth = depthTotal / polygon2D.count
                                        if averageDepth < bestFaceDepth do
                                        (
                                            bestFaceDepth = averageDepth
                                            bestFace = faceIndex
                                            bestFaceWorld = polygonWorld
                                        )
                                    )
                                )
                            )

                            if bestFace > 0 then
                            (
                                local center = [0,0,0]
                                for wp in bestFaceWorld do center += wp
                                center /= bestFaceWorld.count
                                setHover #face bestFace center bestFaceWorld shiftValue
                            )
                            else
                            (
                                local surfaceHit = surfaceHitAt p
                                if surfaceHit != undefined then
                                    setHover #surfaceBlank 0 surfaceHit.pos #(surfaceHit.pos) shiftValue
                                else
                                    resetHover #outsideSurface shiftValue
                            )
                        )
                    )

                    redrawViews()
                    true
                )
            )
        )
    ),

    fn recordMousePoint clickNo p shiftValue ctrlDown altDown =
    (
        hoverViewPoint = p
        local line = "mousePoint=" + (clickNo as string) + " shift=" + (shiftValue as string) + " readOnly=true"
        appendLog line
        format "MQD R1: %\n" line
        redrawViews()
        true
    ),

    fn drawViewport =
    (
        if active do
        (
            gw.setTransform (matrix3 1)

            case hoverLevel of
            (
                #vertex:
                (
                    gw.marker hoverWorld #bigBox color:(color 40 220 255)
                )
                #boundaryEdge:
                (
                    if hoverWorldPoints.count == 2 do
                    (
                        gw.setColor #line (color 255 155 35)
                        gw.polyline hoverWorldPoints false
                        gw.marker hoverWorldPoints[1] #bigBox color:(color 255 155 35)
                        gw.marker hoverWorldPoints[2] #bigBox color:(color 255 155 35)
                    )
                )
                #interiorEdge:
                (
                    if hoverWorldPoints.count == 2 do
                    (
                        gw.setColor #line (color 220 80 255)
                        gw.polyline hoverWorldPoints false
                        gw.marker hoverWorldPoints[1] #bigBox color:(color 220 80 255)
                        gw.marker hoverWorldPoints[2] #bigBox color:(color 220 80 255)
                    )
                )
                #face:
                (
                    if hoverWorldPoints.count >= 3 do
                    (
                        gw.setColor #line (color 60 130 255)
                        gw.polyline hoverWorldPoints true
                    )
                )
                #surfaceBlank:
                (
                    gw.marker hoverWorld #circle color:(color 80 255 120)
                )
            )

            gw.enlargeUpdateRect #whole
        )
        true
    ),

    fn onToolStart =
    (
        active = true
        lastTick = 0
        lastStateKey = ""
        initializeLog()
        resetHover #none false
        statusText = "Active - read-only recognition"
        try (unregisterRedrawViewsCallback MayaQuadDrawR1_DrawCallback) catch()
        registerRedrawViewsCallback MayaQuadDrawR1_DrawCallback
        completeRedraw()
        appendLog ("started work=" + ownerNode.name + " target=" + targetNode.name)
        format "MQD R1 started. Work: %, Target: %\n" ownerNode targetNode
        true
    ),

    fn onToolStop =
    (
        active = false
        try (unregisterRedrawViewsCallback MayaQuadDrawR1_DrawCallback) catch()
        hoverLevel = #none
        hoverIndex = 0
        hoverWorldPoints = #()
        statusText = "Stopped"
        appendLog "stopped=true"
        completeRedraw()
        format "MQD R1 stopped. Geometry was not modified.\n"
        true
    )
)

MayaQuadDrawR1 = MayaQuadDrawR1State()

fn MayaQuadDrawR1_DrawCallback =
(
    if MayaQuadDrawR1 != undefined do MayaQuadDrawR1.drawViewport()
)

tool MayaQuadDrawR1Tool prompt:"MQD R1 read-only recognition; RMB or Esc exits"
(
    on start do
    (
        global MayaQuadDrawR1
        MayaQuadDrawR1.onToolStart()
    )

    on freeMove do
    (
        global MayaQuadDrawR1
        MayaQuadDrawR1.updateHover viewPoint shiftKey ctrlKey altKey mButton
    )

    on mouseMove clickNo do
    (
        global MayaQuadDrawR1
        MayaQuadDrawR1.updateHover viewPoint shiftKey ctrlKey altKey mButton
    )

    on mousePoint clickNo do
    (
        global MayaQuadDrawR1
        MayaQuadDrawR1.recordMousePoint clickNo viewPoint shiftKey ctrlKey altKey
    )

    on mouseAbort clickNo do
    (
        #stop
    )

    on stop do
    (
        global MayaQuadDrawR1
        MayaQuadDrawR1.onToolStop()
    )
)

fn MayaQuadDrawR1_Start =
(
    if MayaQuadDrawR1.active then true
    else if MayaQuadDrawR1.prepare() then
    (
        startTool MayaQuadDrawR1Tool prompt:"MQD R1 read-only recognition; RMB or Esc exits"
        true
    )
    else false
)

fn MayaQuadDrawR1_Stop =
(
    if MayaQuadDrawR1 != undefined and MayaQuadDrawR1.active do
    (
        try (stopTool MayaQuadDrawR1Tool) catch (MayaQuadDrawR1.onToolStop())
    )
    true
)

fn MayaQuadDrawR1_Toggle =
(
    if MayaQuadDrawR1.active then MayaQuadDrawR1_Stop() else MayaQuadDrawR1_Start()
)

format "MQD R1 read-only recognizer loaded. Run MayaQuadDrawR1_Start().\n"
