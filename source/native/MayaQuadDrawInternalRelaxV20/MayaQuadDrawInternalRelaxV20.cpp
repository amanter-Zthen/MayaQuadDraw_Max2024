#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <limits>
#include <numeric>
#include <string>
#include <vector>
#include <windows.h>

#include <guplib.h>
#include <maxapi.h>
#include <IPainterInterface.h>
#include <GraphicsWindow.h>
#include <hold.h>
#include <iepoly.h>
#include <mnmesh.h>
#include <triobj.h>

#include <maxscript/maxscript.h>
#include <maxscript/foundation/numbers.h>
#include <maxscript/foundation/strings.h>

namespace
{
    HMODULE g_module = nullptr;
    constexpr Class_ID kInternalRelaxGupClassId(0x53c6772b, 0x1ed4469d);

    // [MQD-V20-BLOCK: STROKE SAMPLING]
    // Max Painter receives one brush tick per mouse sample.  Our shared MQD
    // tracker can deliver wider gaps, so fill the same path at a stable screen
    // spacing while retaining Painter's own segment hit-test and falloff.
    constexpr float kPainterSampleSpacingPixels = 2.0f;
    constexpr int kMaximumSamplesPerMouseEvent = 12;

    EPoly* EPolyFromNode(INode* node)
    {
        if (node == nullptr)
        {
            return nullptr;
        }
        Object* object = node->GetObjectRef();
        return object != nullptr
            ? static_cast<EPoly*>(object->GetInterface(EPOLY_INTERFACE))
            : nullptr;
    }

    std::wstring EventLogPath()
    {
        wchar_t modulePath[MAX_PATH]{};
        const DWORD length = GetModuleFileNameW(g_module, modulePath, MAX_PATH);
        std::wstring path(modulePath, length);
        const std::wstring::size_type extension = path.find_last_of(L'.');
        if (extension != std::wstring::npos)
        {
            path.resize(extension);
        }
        path += L".events.log";
        return path;
    }

    void AppendEvent(const char* text)
    {
        FILE* file = nullptr;
        if (_wfopen_s(&file, EventLogPath().c_str(), L"ab") == 0 && file != nullptr)
        {
            std::fprintf(file, "%s\r\n", text);
            std::fclose(file);
        }
    }

    class RelaxStrokeRestore final : public RestoreObj
    {
    public:
        explicit RelaxStrokeRestore(INode* node) : node_(node) { Capture(undo_); }

        void Restore(int isUndo) override
        {
            if (isUndo)
            {
                Capture(redo_);
            }
            Apply(undo_);
        }

        void Redo() override { Apply(redo_); }

        int Size() override
        {
            return static_cast<int>(sizeof(*this) + (undo_.size() + redo_.size()) * sizeof(Point3));
        }

        TSTR Description() override { return TSTR(_T("Maya Quad Draw Native Paint Deform Relax V20")); }

    private:
        void Capture(std::vector<Point3>& points)
        {
            EPoly* epoly = EPolyFromNode(node_);
            MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
            points.clear();
            if (mesh == nullptr)
            {
                return;
            }
            points.reserve(mesh->numv);
            for (int index = 0; index < mesh->numv; ++index)
            {
                points.push_back(mesh->v[index].p);
            }
        }

        void Apply(const std::vector<Point3>& points)
        {
            EPoly* epoly = EPolyFromNode(node_);
            MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
            if (mesh == nullptr || points.size() != static_cast<size_t>(mesh->numv))
            {
                return;
            }
            for (int index = 0; index < mesh->numv; ++index)
            {
                mesh->v[index].p = points[static_cast<size_t>(index)];
            }
            mesh->SetFlag(MN_CACHEINVALID);
            epoly->LocalDataChanged(GEOM_CHANNEL);
            epoly->RefreshScreen();
        }

        INode* node_ = nullptr;
        std::vector<Point3> undo_;
        std::vector<Point3> redo_;
    };

    bool IsBoundaryVertex(const MNMesh& mesh, int vertexIndex)
    {
        if (vertexIndex < 0 || vertexIndex >= mesh.numv || mesh.v[vertexIndex].GetFlag(MN_DEAD))
        {
            return true;
        }
        Tab<int>* vertexEdges = mesh.GetVEdge();
        if (vertexEdges == nullptr)
        {
            return true;
        }
        const Tab<int>& edges = vertexEdges[vertexIndex];
        for (int slot = 0; slot < edges.Count(); ++slot)
        {
            const int edgeIndex = edges[slot];
            if (edgeIndex < 0 || edgeIndex >= mesh.nume)
            {
                continue;
            }
            const MNEdge& edge = mesh.e[edgeIndex];
            if (!edge.GetFlag(MN_DEAD) && (edge.f1 < 0 || edge.f2 < 0))
            {
                return true;
            }
        }
        return false;
    }

    Point3 ClosestPointOnTriangle(
        const Point3& point,
        const Point3& a,
        const Point3& b,
        const Point3& c)
    {
        // Real-Time Collision Detection, Christer Ericson, section 5.1.5.
        // This is view independent: no screen coordinate or DPI conversion is
        // involved in the surface constraint.
        const Point3 ab = b - a;
        const Point3 ac = c - a;
        const Point3 ap = point - a;
        const float d1 = DotProd(ab, ap);
        const float d2 = DotProd(ac, ap);
        if (d1 <= 0.0f && d2 <= 0.0f)
        {
            return a;
        }

        const Point3 bp = point - b;
        const float d3 = DotProd(ab, bp);
        const float d4 = DotProd(ac, bp);
        if (d3 >= 0.0f && d4 <= d3)
        {
            return b;
        }

        const float vc = d1 * d4 - d3 * d2;
        if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f)
        {
            const float v = d1 / (d1 - d3);
            return a + ab * v;
        }

        const Point3 cp = point - c;
        const float d5 = DotProd(ab, cp);
        const float d6 = DotProd(ac, cp);
        if (d6 >= 0.0f && d5 <= d6)
        {
            return c;
        }

        const float vb = d5 * d2 - d1 * d6;
        if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f)
        {
            const float w = d2 / (d2 - d6);
            return a + ac * w;
        }

        const float va = d3 * d6 - d5 * d4;
        if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f)
        {
            const Point3 bc = c - b;
            const float w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
            return b + bc * w;
        }

        const float denominator = 1.0f / (va + vb + vc);
        const float v = vb * denominator;
        const float w = vc * denominator;
        return a + ab * v + ac * w;
    }

    class FrozenSurface
    {
    public:
        bool Capture(INode* node)
        {
            vertices_.clear();
            triangles_.clear();
            if (node == nullptr)
            {
                return false;
            }

            const TimeValue time = GetCOREInterface()->GetTime();
            ObjectState state = node->EvalWorldState(time);
            Object* source = state.obj;
            if (source == nullptr || !source->CanConvertToType(triObjectClassID))
            {
                return false;
            }

            TriObject* triObject = static_cast<TriObject*>(source->ConvertToType(time, triObjectClassID));
            if (triObject == nullptr)
            {
                return false;
            }
            const bool deleteConvertedObject = triObject != source;
            Mesh& mesh = triObject->GetMesh();
            const Matrix3 objectTM = node->GetObjectTM(time);

            vertices_.reserve(static_cast<size_t>(mesh.getNumVerts()));
            for (int vertexIndex = 0; vertexIndex < mesh.getNumVerts(); ++vertexIndex)
            {
                vertices_.push_back(mesh.verts[vertexIndex] * objectTM);
            }
            triangles_.reserve(static_cast<size_t>(mesh.getNumFaces()) * 3U);
            for (int faceIndex = 0; faceIndex < mesh.getNumFaces(); ++faceIndex)
            {
                const Face& face = mesh.faces[faceIndex];
                triangles_.push_back(face.v[0]);
                triangles_.push_back(face.v[1]);
                triangles_.push_back(face.v[2]);
            }

            if (deleteConvertedObject)
            {
                triObject->DeleteThis();
            }
            return !vertices_.empty() && !triangles_.empty();
        }

        bool ClosestPoint(const Point3& worldPoint, float offset, Point3& result) const
        {
            float bestDistanceSquared = (std::numeric_limits<float>::max)();
            Point3 bestPoint = worldPoint;
            Point3 bestNormal(0.0f, 0.0f, 1.0f);
            bool found = false;

            for (size_t triangleIndex = 0; triangleIndex + 2 < triangles_.size(); triangleIndex += 3)
            {
                const Point3& a = vertices_[static_cast<size_t>(triangles_[triangleIndex])];
                const Point3& b = vertices_[static_cast<size_t>(triangles_[triangleIndex + 1])];
                const Point3& c = vertices_[static_cast<size_t>(triangles_[triangleIndex + 2])];
                const Point3 candidate = ClosestPointOnTriangle(worldPoint, a, b, c);
                const Point3 difference = candidate - worldPoint;
                const float distanceSquared = DotProd(difference, difference);
                if (distanceSquared >= bestDistanceSquared)
                {
                    continue;
                }

                Point3 normal = CrossProd(b - a, c - a);
                const float normalLength = Length(normal);
                if (normalLength <= 0.000001f)
                {
                    continue;
                }
                normal /= normalLength;
                bestDistanceSquared = distanceSquared;
                bestPoint = candidate;
                bestNormal = normal;
                found = true;
            }

            if (found)
            {
                result = bestPoint + bestNormal * offset;
            }
            return found;
        }

        void Clear()
        {
            vertices_.clear();
            triangles_.clear();
        }

    private:
        std::vector<Point3> vertices_;
        std::vector<int> triangles_;
    };

    bool ProjectToPickedSurface(
        INode* targetNode,
        const Point3& tentativeWorld,
        float offset,
        Point3& projectedWorld)
    {
        if (targetNode == nullptr)
        {
            return false;
        }
        ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
        if (!viewport.IsAlive())
        {
            return false;
        }
        GraphicsWindow* graphics = viewport.getGW();
        if (graphics == nullptr)
        {
            return false;
        }
        graphics->setTransform(Matrix3());
        IPoint3 screen{};
        graphics->wTransPoint(&tentativeWorld, &screen);

        Ray worldRay;
        viewport.MapScreenToWorldRay(static_cast<float>(screen.x), static_cast<float>(screen.y), worldRay);
        const TimeValue time = GetCOREInterface()->GetTime();
        ObjectState state = targetNode->EvalWorldState(time);
        if (state.obj == nullptr)
        {
            return false;
        }
        const Matrix3 targetTM = targetNode->GetObjectTM(time);
        const Matrix3 inverseTargetTM = Inverse(targetTM);
        Ray objectRay;
        objectRay.p = worldRay.p * inverseTargetTM;
        objectRay.dir = VectorTransform(inverseTargetTM, worldRay.dir);
        const float directionLength = Length(objectRay.dir);
        if (directionLength <= 0.000001f)
        {
            return false;
        }
        objectRay.dir /= directionLength;

        float at = 0.0f;
        Point3 objectNormal(0.0f, 0.0f, 1.0f);
        if (!state.obj->IntersectRay(time, objectRay, at, objectNormal))
        {
            return false;
        }
        const Point3 hitObject = objectRay.p + objectRay.dir * at;
        Point3 worldNormal = VectorTransform(targetTM, objectNormal);
        const float normalLength = Length(worldNormal);
        if (normalLength > 0.000001f)
        {
            worldNormal /= normalLength;
        }
        projectedWorld = hitObject * targetTM + worldNormal * offset;
        return true;
    }

    struct SavedPainterSettings
    {
        BOOL enablePointGather = FALSE;
        BOOL buildNormalData = FALSE;
        BOOL updateOnMouseUp = FALSE;
        int lagRate = 0;
        float minSize = 0.0f;
        float maxSize = 0.0f;
        float minStrength = 0.0f;
        float maxStrength = 0.0f;
        BOOL pressureEnable = FALSE;
        int pressureAffects = 0;
        BOOL predefinedStrength = FALSE;
        BOOL predefinedSize = FALSE;
        BOOL additive = FALSE;
        BOOL drawRing = FALSE;
        BOOL drawNormal = FALSE;
        BOOL drawTrace = FALSE;
    };

    class NativeStrokeRelax
    {
    public:
        bool Begin(
            INode* ownerNode,
            INode* targetNode,
            float radius,
            float focus,
            float strength,
            float offset)
        {
            if (active_)
            {
                return true;
            }
            if (EPolyFromNode(ownerNode) == nullptr || targetNode == nullptr || !EnsurePainter())
            {
                AppendEvent("BEGIN rejected: invalid nodes or Painter unavailable");
                return false;
            }
            if (painter_->InPaintMode())
            {
                AppendEvent("BEGIN rejected: another Painter command mode is active");
                return false;
            }

            SaveSettings();
            ownerNode_ = ownerNode;
            targetNode_ = targetNode;
            radius_ = std::clamp(radius, 1.0f, 1000.0f);
            focus_ = std::clamp(focus, 0.0f, 100.0f);
            strength_ = std::clamp(strength, 0.0f, 1.0f);
            offset_ = offset;
            strokeChanged_ = false;
            sampleCalls_.store(0);
            generatedBrushTicks_.store(0);
            hitSamples_.store(0);
            changedSteps_.store(0);
            lastCoveredVertices_.store(0);
            lastStrokePointCount_.store(0);
            lastCursorX_.store(-1);
            lastCursorY_.store(-1);
            hasLastPainterPoint_ = false;

            painter_->SetEnablePointGather(TRUE);
            painter_->SetBuildNormalData(TRUE);
            painter_->SetUpdateOnMouseUp(FALSE);
            // Zero is Autodesk Painter's native default: update every stroke
            // point.  Save/restore protects the user's global Painter setting.
            painter_->SetLagRate(0);
            painter_->SetMinSize(radius_);
            painter_->SetMaxSize(radius_);
            painter_->SetMinStr(strength_);
            painter_->SetMaxStr(strength_);
            painter_->SetPressureEnable(FALSE);
            painter_->SetPredefinedStrEnable(FALSE);
            painter_->SetPredefinedSizeEnable(FALSE);
            painter_->SetAdditiveMode(FALSE);
            painter_->SetDrawRing(FALSE);
            painter_->SetDrawNormal(FALSE);
            painter_->SetDrawTrace(FALSE);

            Tab<INode*> nodes;
            nodes.Append(1, &ownerNode_);
            if (!painter_->InitializeNodes(0, nodes))
            {
                AppendEvent("BEGIN failed: InitializeNodes returned false");
                RestoreSettings();
                ownerNode_ = nullptr;
                targetNode_ = nullptr;
                return false;
            }
            if (!CaptureStrokeData())
            {
                AppendEvent("BEGIN failed: native Paint Deform stroke snapshot could not be built");
                Tab<INode*> noNodes;
                painter_->InitializeNodes(0, noNodes);
                RestoreSettings();
                ownerNode_ = nullptr;
                targetNode_ = nullptr;
                return false;
            }
            if (!surface_.Capture(targetNode_))
            {
                AppendEvent("BEGIN failed: picked surface snapshot could not be built");
                ClearStrokeData();
                Tab<INode*> noNodes;
                painter_->InitializeNodes(0, noNodes);
                RestoreSettings();
                ownerNode_ = nullptr;
                targetNode_ = nullptr;
                return false;
            }
            painter_->ClearStroke();

            ownsHold_ = theHold.Holding() == 0;
            if (ownsHold_)
            {
                theHold.Begin();
            }
            if (theHold.Holding())
            {
                theHold.Put(new RelaxStrokeRestore(ownerNode_));
            }

            active_ = true;
            AppendEvent("BEGIN SDK Paint Deform buffer path; native lag=0; 2px path samples; no command-mode switch");
            return true;
        }

        bool Step(const IPoint2& logicalCursor)
        {
            if (!active_ || painter_ == nullptr || ownerNode_ == nullptr)
            {
                return false;
            }
            ++sampleCalls_;

            lastLogicalX_.store(logicalCursor.x);
            lastLogicalY_.store(logicalCursor.y);

            IPoint2 cursor = logicalCursor;
            if (!ResolvePainterPoint(cursor))
            {
                AppendEvent("STEP warning: physical viewport conversion unavailable; using tracker coordinate");
            }
            lastCursorX_.store(cursor.x);
            lastCursorY_.store(cursor.y);

            IPoint2 segmentStart = hasLastPainterPoint_ ? lastPainterPoint_ : cursor;
            const float deltaX = static_cast<float>(cursor.x - segmentStart.x);
            const float deltaY = static_cast<float>(cursor.y - segmentStart.y);
            const float distancePixels = std::sqrt(deltaX * deltaX + deltaY * deltaY);
            int brushTickCount = hasLastPainterPoint_
                ? static_cast<int>(std::ceil(distancePixels / kPainterSampleSpacingPixels))
                : 1;
            brushTickCount = std::clamp(brushTickCount, 1, kMaximumSamplesPerMouseEvent);

            bool anyHit = false;
            bool anyChanged = false;
            for (int brushTick = 1; brushTick <= brushTickCount; ++brushTick)
            {
                const float interpolation = static_cast<float>(brushTick) /
                    static_cast<float>(brushTickCount);
                const IPoint2 sample(
                    static_cast<int>(std::lround(static_cast<float>(segmentStart.x) + deltaX * interpolation)),
                    static_cast<int>(std::lround(static_cast<float>(segmentStart.y) + deltaY * interpolation)));

                const int beforeCount = painter_->GetStrokeCount();
                if (!painter_->AddToStroke(sample, FALSE, FALSE))
                {
                    continue;
                }
                ++generatedBrushTicks_;
                const int strokePointCount = painter_->GetStrokeCount();
                lastStrokePointCount_.store(strokePointCount);
                if (strokePointCount <= beforeCount)
                {
                    continue;
                }
                anyHit = true;
                ++hitSamples_;
                if (ApplyNativePointGather())
                {
                    anyChanged = true;
                    strokeChanged_ = true;
                    ++changedSteps_;
                }
            }
            lastPainterPoint_ = cursor;
            hasLastPainterPoint_ = true;
            if (!anyHit)
            {
                lastCoveredVertices_.store(0);
            }
            return anyChanged;
        }

        bool End(bool cancel)
        {
            if (!active_)
            {
                return false;
            }
            const bool changed = strokeChanged_;
            if (ownsHold_ && theHold.Holding())
            {
                if (cancel || !changed)
                {
                    theHold.Cancel();
                }
                else
                {
                    theHold.Accept(_T("Maya Quad Draw Native Paint Deform Relax V20"));
                }
            }
            ownsHold_ = false;
            strokeChanged_ = false;
            active_ = false;

            if (painter_ != nullptr)
            {
                painter_->ClearStroke();
                Tab<INode*> noNodes;
                painter_->InitializeNodes(0, noNodes);
            }
            ClearStrokeData();
            RestoreSettings();
            ownerNode_ = nullptr;
            targetNode_ = nullptr;
            AppendEvent(cancel ? "END cancelled" : changed ? "END committed" : "END no change");
            return cancel ? true : changed;
        }

        bool IsActive() const { return active_; }
        bool Changed() const { return strokeChanged_; }
        long long SampleCalls() const { return sampleCalls_.load(); }
        long long GeneratedBrushTicks() const { return generatedBrushTicks_.load(); }
        long long HitSamples() const { return hitSamples_.load(); }
        long long ChangedSteps() const { return changedSteps_.load(); }
        int CoveredVertices() const { return lastCoveredVertices_.load(); }
        int StrokePointCount() const { return lastStrokePointCount_.load(); }
        int CursorX() const { return lastCursorX_.load(); }
        int CursorY() const { return lastCursorY_.load(); }
        int LogicalX() const { return lastLogicalX_.load(); }
        int LogicalY() const { return lastLogicalY_.load(); }
        int ClientX() const { return lastClientX_.load(); }
        int ClientY() const { return lastClientY_.load(); }
        int ClientWidth() const { return lastClientWidth_.load(); }
        int ClientHeight() const { return lastClientHeight_.load(); }
        int GraphicsWidth() const { return lastGraphicsWidth_.load(); }
        int GraphicsHeight() const { return lastGraphicsHeight_.load(); }

        void Shutdown()
        {
            if (active_)
            {
                End(true);
            }
            else
            {
                RestoreSettings();
            }
        }

    private:
        bool CaptureStrokeData()
        {
            EPoly* epoly = EPolyFromNode(ownerNode_);
            MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
            if (mesh == nullptr || mesh->numv <= 0)
            {
                return false;
            }
            if (!mesh->GetFlag(MN_MESH_FILLED_IN))
            {
                mesh->FillInMesh();
            }

            const size_t vertexCount = static_cast<size_t>(mesh->numv);
            inputPositions_.resize(vertexCount);
            goalPositions_.assign(vertexCount, Point3(0.0f, 0.0f, 0.0f));
            amounts_.assign(vertexCount, 0.0f);
            boundary_.assign(vertexCount, false);
            std::vector<int> neighborCounts(vertexCount, 0);

            for (int vertexIndex = 0; vertexIndex < mesh->numv; ++vertexIndex)
            {
                inputPositions_[static_cast<size_t>(vertexIndex)] = mesh->v[vertexIndex].p;
                boundary_[static_cast<size_t>(vertexIndex)] = IsBoundaryVertex(*mesh, vertexIndex);
            }

            // This is the exact target construction used by Autodesk's SDK
            // MeshPaintMgr::InitPaintDeform(PAINTMODE_PAINTRELAX): each face
            // contributes the previous and next endpoint around the vertex.
            for (int faceIndex = 0; faceIndex < mesh->numf; ++faceIndex)
            {
                const MNFace& face = mesh->f[faceIndex];
                if (face.GetFlag(MN_DEAD) || face.deg <= 0)
                {
                    continue;
                }
                for (int corner = 0; corner < face.deg; ++corner)
                {
                    const int currentIndex = face.vtx[corner];
                    const int previousIndex = face.vtx[(corner + face.deg - 1) % face.deg];
                    const int nextIndex = face.vtx[(corner + 1) % face.deg];
                    if (currentIndex < 0 || currentIndex >= mesh->numv ||
                        previousIndex < 0 || previousIndex >= mesh->numv ||
                        nextIndex < 0 || nextIndex >= mesh->numv)
                    {
                        continue;
                    }
                    goalPositions_[static_cast<size_t>(currentIndex)] +=
                        inputPositions_[static_cast<size_t>(previousIndex)] +
                        inputPositions_[static_cast<size_t>(nextIndex)];
                    neighborCounts[static_cast<size_t>(currentIndex)] += 2;
                }
            }

            for (size_t vertexIndex = 0; vertexIndex < vertexCount; ++vertexIndex)
            {
                if (neighborCounts[vertexIndex] > 0)
                {
                    goalPositions_[vertexIndex] /= static_cast<float>(neighborCounts[vertexIndex]);
                }
                else
                {
                    goalPositions_[vertexIndex] = inputPositions_[vertexIndex];
                    boundary_[vertexIndex] = true;
                }
            }
            return true;
        }

        void ClearStrokeData()
        {
            inputPositions_.clear();
            goalPositions_.clear();
            amounts_.clear();
            boundary_.clear();
            surface_.Clear();
        }

        float NativeBrushAmount(float linearWeight) const
        {
            linearWeight = std::clamp(linearWeight, 0.0f, 1.0f);
            if (linearWeight <= 0.0f)
            {
                return 0.0f;
            }

            const float distance = 1.0f - linearWeight;
            const float focus = std::clamp(focus_ * 0.01f, 0.0f, 1.0f);
            float remappedWeight = 1.0f;
            if (focus < 0.9999f && distance > focus)
            {
                remappedWeight = 1.0f - ((distance - focus) / (1.0f - focus));
            }
            remappedWeight = std::clamp(remappedWeight, 0.0f, 1.0f);

            // Painter's PointGather returns linear envelope membership.  The
            // Paint Deform source then evaluates the native Painter falloff
            // graph itself before multiplying by brush strength.
            ICurve* curve = painter_ != nullptr ? painter_->GetFalloffGraph() : nullptr;
            const float falloff = curve != nullptr
                ? curve->GetValue(0, 1.0f - remappedWeight)
                : remappedWeight;
            return std::clamp(falloff * strength_, 0.0f, 1.0f);
        }

        bool ResolvePainterPoint(IPoint2& painterPoint)
        {
            ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
            if (!viewport.IsAlive())
            {
                return false;
            }
            GraphicsWindow* graphics = viewport.getGW();
            const HWND viewportWindow = viewport.GetHWnd();
            if (graphics == nullptr || viewportWindow == nullptr || !IsWindow(viewportWindow))
            {
                return false;
            }

            POINT clientCursor{};
            RECT clientRect{};
            if (!GetCursorPos(&clientCursor) ||
                !ScreenToClient(viewportWindow, &clientCursor) ||
                !GetClientRect(viewportWindow, &clientRect))
            {
                return false;
            }

            const int clientWidth = static_cast<int>(clientRect.right - clientRect.left);
            const int clientHeight = static_cast<int>(clientRect.bottom - clientRect.top);
            const int graphicsWidth = graphics->getWinSizeX();
            const int graphicsHeight = graphics->getWinSizeY();
            if (clientWidth <= 0 || clientHeight <= 0 || graphicsWidth <= 0 || graphicsHeight <= 0)
            {
                return false;
            }

            lastClientX_.store(static_cast<int>(clientCursor.x));
            lastClientY_.store(static_cast<int>(clientCursor.y));
            lastClientWidth_.store(clientWidth);
            lastClientHeight_.store(clientHeight);
            lastGraphicsWidth_.store(graphicsWidth);
            lastGraphicsHeight_.store(graphicsHeight);

            // Painter's meshSearchTree is built in GraphicsWindow pixels.
            // mouse.pos is a logical Max UI coordinate on a high-DPI display,
            // while the viewport window and GraphicsWindow can have different
            // extents.  Use the live physical cursor and the actual two window
            // extents instead of assuming a fixed 200% DPI multiplier.
            const double scaleX = static_cast<double>(graphicsWidth) / static_cast<double>(clientWidth);
            const double scaleY = static_cast<double>(graphicsHeight) / static_cast<double>(clientHeight);
            painterPoint.x = static_cast<int>(std::lround(static_cast<double>(clientCursor.x) * scaleX));
            painterPoint.y = static_cast<int>(std::lround(static_cast<double>(clientCursor.y) * scaleY));
            return true;
        }

        bool EnsurePainter()
        {
            if (painter_ != nullptr)
            {
                return true;
            }
            painterRef_ = static_cast<ReferenceTarget*>(GetCOREInterface()->CreateInstance(
                REF_TARGET_CLASS_ID, PAINTERINTERFACE_CLASS_ID));
            if (painterRef_ == nullptr)
            {
                return false;
            }
            painter_ = static_cast<IPainterInterface_V7*>(painterRef_->GetInterface(PAINTERINTERFACE_V7));
            return painter_ != nullptr;
        }

        bool ApplyNativePointGather()
        {
            EPoly* epoly = EPolyFromNode(ownerNode_);
            MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
            if (mesh == nullptr || mesh->numv == 0 || painter_ == nullptr)
            {
                return false;
            }
            if (!mesh->GetFlag(MN_MESH_FILLED_IN))
            {
                mesh->FillInMesh();
            }

            int weightCount = 0;
            float* nativeWeights = painter_->RetrievePointGatherWeights(ownerNode_, weightCount);
            if (nativeWeights == nullptr || weightCount != mesh->numv)
            {
                AppendEvent("RELAX skipped: native PointGather count mismatch");
                return false;
            }

            if (inputPositions_.size() != static_cast<size_t>(mesh->numv) ||
                goalPositions_.size() != static_cast<size_t>(mesh->numv) ||
                amounts_.size() != static_cast<size_t>(mesh->numv) ||
                boundary_.size() != static_cast<size_t>(mesh->numv))
            {
                AppendEvent("RELAX skipped: stroke snapshot/topology mismatch");
                return false;
            }

            int coveredVertices = 0;
            bool changed = false;
            const TimeValue time = GetCOREInterface()->GetTime();
            const Matrix3 ownerTM = ownerNode_->GetObjectTM(time);
            const Matrix3 inverseOwnerTM = Inverse(ownerTM);
            for (int vertexIndex = 0; vertexIndex < mesh->numv; ++vertexIndex)
            {
                const size_t index = static_cast<size_t>(vertexIndex);
                if (mesh->v[vertexIndex].GetFlag(MN_DEAD) || boundary_[index])
                {
                    continue;
                }

                const float pointAmount = NativeBrushAmount(nativeWeights[vertexIndex]);
                if (pointAmount <= 0.00001f)
                {
                    continue;
                }

                // Copy Autodesk MeshPaintMgr::PaintStroke_Deform accumulation:
                // keep the maximum direct hit, then build more slowly while
                // scrubbing weaker parts of the falloff over the same vertex.
                float& amount = amounts_[index];
                if (pointAmount < amount)
                {
                    amount += 0.02f * pointAmount;
                }
                else
                {
                    amount = pointAmount;
                }
                amount = std::clamp(amount, 0.0f, 1.0f);

                const Point3 tentativeLocal = amount > 0.99f
                    ? goalPositions_[index]
                    : inputPositions_[index] +
                        (goalPositions_[index] - inputPositions_[index]) * amount;
                Point3 projectedWorld;
                const Point3 newLocal = surface_.ClosestPoint(
                    tentativeLocal * ownerTM, offset_, projectedWorld)
                    ? projectedWorld * inverseOwnerTM
                    : tentativeLocal;
                const Point3 change = newLocal - mesh->v[vertexIndex].p;
                if (DotProd(change, change) > 0.00000001f)
                {
                    mesh->v[vertexIndex].p = newLocal;
                    changed = true;
                }
                nativeWeights[vertexIndex] = 0.0f;
                ++coveredVertices;
            }
            lastCoveredVertices_.store(coveredVertices);
            if (!changed)
            {
                return false;
            }

            mesh->SetFlag(MN_CACHEINVALID);
            epoly->LocalDataChanged(GEOM_CHANNEL);
            epoly->RefreshScreen();
            return true;
        }

        void SaveSettings()
        {
            saved_.enablePointGather = painter_->GetEnablePointGather();
            saved_.buildNormalData = painter_->GetBuildNormalData();
            saved_.updateOnMouseUp = painter_->GetUpdateOnMouseUp();
            saved_.lagRate = painter_->GetLagRate();
            saved_.minSize = painter_->GetMinSize();
            saved_.maxSize = painter_->GetMaxSize();
            saved_.minStrength = painter_->GetMinStr();
            saved_.maxStrength = painter_->GetMaxStr();
            saved_.pressureEnable = painter_->GetPressureEnable();
            saved_.pressureAffects = painter_->GetPressureAffects();
            saved_.predefinedStrength = painter_->GetPredefinedStrEnable();
            saved_.predefinedSize = painter_->GetPredefinedSizeEnable();
            saved_.additive = painter_->GetAdditiveMode();
            saved_.drawRing = painter_->GetDrawRing();
            saved_.drawNormal = painter_->GetDrawNormal();
            saved_.drawTrace = painter_->GetDrawTrace();
            settingsSaved_ = true;
        }

        void RestoreSettings()
        {
            if (painter_ == nullptr || !settingsSaved_)
            {
                return;
            }
            painter_->SetEnablePointGather(saved_.enablePointGather);
            painter_->SetBuildNormalData(saved_.buildNormalData);
            painter_->SetUpdateOnMouseUp(saved_.updateOnMouseUp);
            painter_->SetLagRate(saved_.lagRate);
            painter_->SetMinSize(saved_.minSize);
            painter_->SetMaxSize(saved_.maxSize);
            painter_->SetMinStr(saved_.minStrength);
            painter_->SetMaxStr(saved_.maxStrength);
            painter_->SetPressureEnable(saved_.pressureEnable);
            painter_->SetPressureAffects(saved_.pressureAffects);
            painter_->SetPredefinedStrEnable(saved_.predefinedStrength);
            painter_->SetPredefinedSizeEnable(saved_.predefinedSize);
            painter_->SetAdditiveMode(saved_.additive);
            painter_->SetDrawRing(saved_.drawRing);
            painter_->SetDrawNormal(saved_.drawNormal);
            painter_->SetDrawTrace(saved_.drawTrace);
            settingsSaved_ = false;
        }

        ReferenceTarget* painterRef_ = nullptr;
        IPainterInterface_V7* painter_ = nullptr;
        INode* ownerNode_ = nullptr;
        INode* targetNode_ = nullptr;
        SavedPainterSettings saved_;
        bool settingsSaved_ = false;
        bool active_ = false;
        bool ownsHold_ = false;
        bool strokeChanged_ = false;
        bool hasLastPainterPoint_ = false;
        IPoint2 lastPainterPoint_{0, 0};
        float radius_ = 20.0f;
        float focus_ = 50.0f;
        float strength_ = 1.0f;
        float offset_ = 0.0f;
        std::vector<Point3> inputPositions_;
        std::vector<Point3> goalPositions_;
        std::vector<float> amounts_;
        std::vector<bool> boundary_;
        FrozenSurface surface_;
        std::atomic<long long> sampleCalls_{0};
        std::atomic<long long> generatedBrushTicks_{0};
        std::atomic<long long> hitSamples_{0};
        std::atomic<long long> changedSteps_{0};
        std::atomic<int> lastCoveredVertices_{0};
        std::atomic<int> lastStrokePointCount_{0};
        std::atomic<int> lastCursorX_{-1};
        std::atomic<int> lastCursorY_{-1};
        std::atomic<int> lastLogicalX_{-1};
        std::atomic<int> lastLogicalY_{-1};
        std::atomic<int> lastClientX_{-1};
        std::atomic<int> lastClientY_{-1};
        std::atomic<int> lastClientWidth_{0};
        std::atomic<int> lastClientHeight_{0};
        std::atomic<int> lastGraphicsWidth_{0};
        std::atomic<int> lastGraphicsHeight_{0};
    };

    NativeStrokeRelax g_relax;

    class InternalRelaxGup final : public GUP
    {
    public:
        DWORD Start() override { return GUPRESULT_KEEP; }
        void Stop() override { g_relax.Shutdown(); }
        DWORD_PTR Control(DWORD) override { return 0; }
        void DeleteThis() override { delete this; }
    };

    class InternalRelaxGupClassDesc final : public ClassDesc
    {
    public:
        int IsPublic() override { return FALSE; }
        void* Create(BOOL = FALSE) override { return new InternalRelaxGup(); }
        const TCHAR* ClassName() override { return _T("Maya Quad Draw Native Paint Deform Relax V20"); }
        const TCHAR* NonLocalizedClassName() override { return _T("Maya Quad Draw Native Paint Deform Relax V20"); }
        SClass_ID SuperClassID() override { return GUP_CLASS_ID; }
        Class_ID ClassID() override { return kInternalRelaxGupClassId; }
        const TCHAR* Category() override { return _T(""); }
    };

    InternalRelaxGupClassDesc g_internalRelaxGupClassDesc;
}

BOOL WINAPI DllMain(HINSTANCE instance, ULONG reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

__declspec(dllexport) const TCHAR* LibDescription()
{
    return _T("Maya Quad Draw V20 SDK Paint Deform dense-stroke relax for 3ds Max 2024");
}

__declspec(dllexport) int LibInit() { return TRUE; }
__declspec(dllexport) ULONG LibVersion() { return VERSION_3DSMAX; }
__declspec(dllexport) int LibNumberClasses() { return 1; }
__declspec(dllexport) ClassDesc* LibClassDesc(int index)
{
    return index == 0 ? &g_internalRelaxGupClassDesc : nullptr;
}

#include <maxscript/macros/define_instantiation_functions.h>

def_visible_primitive(MQDInternalRelaxV20Version, "MQDInternalRelaxV20Version");
def_visible_primitive(MQDInternalRelaxV20Begin, "MQDInternalRelaxV20Begin");
def_visible_primitive(MQDInternalRelaxV20Step, "MQDInternalRelaxV20Step");
def_visible_primitive(MQDInternalRelaxV20End, "MQDInternalRelaxV20End");
def_visible_primitive(MQDInternalRelaxV20Cancel, "MQDInternalRelaxV20Cancel");
def_visible_primitive(MQDInternalRelaxV20Status, "MQDInternalRelaxV20Status");

Value* MQDInternalRelaxV20Version_cf(Value**, int count)
{
    check_arg_count(MQDInternalRelaxV20Version, 0, count);
    return new String(_T("0.20.0-max2024-sdk-paint-deform-dense-stroke"));
}

Value* MQDInternalRelaxV20Begin_cf(Value** argList, int count)
{
    check_arg_count(MQDInternalRelaxV20Begin, 6, count);
    return g_relax.Begin(
        argList[0]->to_node(),
        argList[1]->to_node(),
        argList[2]->to_float(),
        argList[3]->to_float(),
        argList[4]->to_float(),
        argList[5]->to_float())
        ? &true_value
        : &false_value;
}

Value* MQDInternalRelaxV20Step_cf(Value** argList, int count)
{
    check_arg_count(MQDInternalRelaxV20Step, 2, count);
    const IPoint2 cursor(argList[0]->to_int(), argList[1]->to_int());
    return g_relax.Step(cursor) ? &true_value : &false_value;
}

Value* MQDInternalRelaxV20End_cf(Value**, int count)
{
    check_arg_count(MQDInternalRelaxV20End, 0, count);
    return g_relax.End(false) ? &true_value : &false_value;
}

Value* MQDInternalRelaxV20Cancel_cf(Value**, int count)
{
    check_arg_count(MQDInternalRelaxV20Cancel, 0, count);
    return g_relax.End(true) ? &true_value : &false_value;
}

Value* MQDInternalRelaxV20Status_cf(Value**, int count)
{
    check_arg_count(MQDInternalRelaxV20Status, 0, count);
    std::wstring status = L"active=" + std::wstring(g_relax.IsActive() ? L"true" : L"false");
    status += L" changed=" + std::wstring(g_relax.Changed() ? L"true" : L"false");
    status += L" addToStrokeCalls=" + std::to_wstring(g_relax.SampleCalls());
    status += L" brushTicks=" + std::to_wstring(g_relax.GeneratedBrushTicks());
    status += L" hitSamples=" + std::to_wstring(g_relax.HitSamples());
    status += L" strokePoints=" + std::to_wstring(g_relax.StrokePointCount());
    status += L" changedSteps=" + std::to_wstring(g_relax.ChangedSteps());
    status += L" covered=" + std::to_wstring(g_relax.CoveredVertices());
    status += L" logical=" + std::to_wstring(g_relax.LogicalX()) + L"," + std::to_wstring(g_relax.LogicalY());
    status += L" client=" + std::to_wstring(g_relax.ClientX()) + L"," + std::to_wstring(g_relax.ClientY());
    status += L" painter=" + std::to_wstring(g_relax.CursorX()) + L"," + std::to_wstring(g_relax.CursorY());
    status += L" clientSize=" + std::to_wstring(g_relax.ClientWidth()) + L"x" + std::to_wstring(g_relax.ClientHeight());
    status += L" gwSize=" + std::to_wstring(g_relax.GraphicsWidth()) + L"x" + std::to_wstring(g_relax.GraphicsHeight());
    status += L" lagRate=0 spacingPx=2 commandModeSwitch=false";
    return new String(status.c_str());
}

