#include <limits>
#include "VisibilityDepthMath.h"
#include "StepBuildCandidateRules.h"

#include <triobj.h>
#include <maxscript/foundation/arrays.h>
#include <maxscript/foundation/3dmath.h>

// V16 is a single successor module, not a companion picking plug-in.  It
// compiles the proven V15 input/Relax bridge into the same binary and keeps the
// V15 MAXScript primitive names as a compatibility ABI for the existing Core.
#define MQD_NATIVE_BRIDGE_CLASS_ID_A 0x6b704d58
#define MQD_NATIVE_BRIDGE_CLASS_ID_B 0x3f157b47
#define MQD_NATIVE_BRIDGE_CLASS_NAME _T("Maya Quad Draw Native Bridge V16")
#define MQD_NATIVE_BRIDGE_DESCRIPTION _T("Maya Quad Draw V16 native visibility and input bridge for 3ds Max 2024")
#define MQD_NATIVE_BRIDGE_VERSION_STRING _T("0.17.9-max2024-v16-settings-tab")
#include "../MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp"

namespace
{
    constexpr float kRayParallelEpsilon = 1.0e-7f;
    constexpr float kRayStartEpsilon = 1.0e-5f;
    constexpr float kDefaultSurfaceEpsilon = 0.01f;

    struct VisibilityTriangle
    {
        Point3 a;
        Point3 b;
        Point3 c;
        Point3 normal;
        int faceIndex = -1;
    };

    struct VisibilityHit
    {
        double parameter = 0.0;
        Point3 point;
        Point3 normal;
        int faceIndex = -1;
    };

    struct VisibilityBvhNode
    {
        Point3 minimum;
        Point3 maximum;
        int left = -1;
        int right = -1;
        int first = 0;
        int count = 0;

        bool IsLeaf() const { return count > 0; }
    };

    struct TargetTriangleCache
    {
        bool valid = false;
        ULONG nodeHandle = 0;
        TimeValue time = TIME_NegInfinity;
        Object* evaluatedObject = nullptr;
        Matrix3 objectTM;
        std::vector<VisibilityTriangle> triangles;
        std::vector<int> triangleOrder;
        std::vector<VisibilityBvhNode> bvhNodes;

        void Clear()
        {
            valid = false;
            nodeHandle = 0;
            time = TIME_NegInfinity;
            evaluatedObject = nullptr;
            objectTM = Matrix3();
            triangles.clear();
            triangleOrder.clear();
            bvhNodes.clear();
        }
    };

    TargetTriangleCache g_targetTriangleCache;

    bool NearlyEqual(float a, float b, float epsilon = 1.0e-5f)
    {
        return std::abs(a - b) <= epsilon;
    }

    bool NearlyEqual(const Point3& a, const Point3& b, float epsilon = 1.0e-5f)
    {
        return NearlyEqual(a.x, b.x, epsilon) &&
            NearlyEqual(a.y, b.y, epsilon) &&
            NearlyEqual(a.z, b.z, epsilon);
    }

    bool NearlyEqual(const Matrix3& a, const Matrix3& b)
    {
        for (int row = 0; row < 4; ++row)
        {
            if (!NearlyEqual(a.GetRow(row), b.GetRow(row)))
            {
                return false;
            }
        }
        return true;
    }

    Point3 NormalizedOrZero(const Point3& value)
    {
        const float valueLength = Length(value);
        return valueLength > kRayParallelEpsilon
            ? value / valueLength
            : Point3(0.0f, 0.0f, 0.0f);
    }

    float Component(const Point3& point, int axis)
    {
        return axis == 0 ? point.x : axis == 1 ? point.y : point.z;
    }

    Point3 MinimumPoint(const Point3& a, const Point3& b)
    {
        return Point3(std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z));
    }

    Point3 MaximumPoint(const Point3& a, const Point3& b)
    {
        return Point3(std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z));
    }

    Point3 TriangleMinimum(const VisibilityTriangle& triangle)
    {
        return MinimumPoint(triangle.a, MinimumPoint(triangle.b, triangle.c));
    }

    Point3 TriangleMaximum(const VisibilityTriangle& triangle)
    {
        return MaximumPoint(triangle.a, MaximumPoint(triangle.b, triangle.c));
    }

    Point3 TriangleCenter(const VisibilityTriangle& triangle)
    {
        return (triangle.a + triangle.b + triangle.c) / 3.0f;
    }

    int BuildVisibilityBvhNode(TargetTriangleCache& cache, int first, int count)
    {
        VisibilityBvhNode node;
        node.minimum = Point3(
            std::numeric_limits<float>::max(),
            std::numeric_limits<float>::max(),
            std::numeric_limits<float>::max());
        node.maximum = Point3(
            -std::numeric_limits<float>::max(),
            -std::numeric_limits<float>::max(),
            -std::numeric_limits<float>::max());
        Point3 centroidMinimum = node.minimum;
        Point3 centroidMaximum = node.maximum;

        for (int offset = 0; offset < count; ++offset)
        {
            const VisibilityTriangle& triangle = cache.triangles[static_cast<size_t>(cache.triangleOrder[static_cast<size_t>(first + offset)])];
            node.minimum = MinimumPoint(node.minimum, TriangleMinimum(triangle));
            node.maximum = MaximumPoint(node.maximum, TriangleMaximum(triangle));
            const Point3 center = TriangleCenter(triangle);
            centroidMinimum = MinimumPoint(centroidMinimum, center);
            centroidMaximum = MaximumPoint(centroidMaximum, center);
        }

        const int nodeIndex = static_cast<int>(cache.bvhNodes.size());
        cache.bvhNodes.push_back(node);
        if (count <= 8)
        {
            cache.bvhNodes[static_cast<size_t>(nodeIndex)].first = first;
            cache.bvhNodes[static_cast<size_t>(nodeIndex)].count = count;
            return nodeIndex;
        }

        const Point3 centroidExtent = centroidMaximum - centroidMinimum;
        int axis = 0;
        if (centroidExtent.y > centroidExtent.x && centroidExtent.y >= centroidExtent.z)
        {
            axis = 1;
        }
        else if (centroidExtent.z > centroidExtent.x && centroidExtent.z > centroidExtent.y)
        {
            axis = 2;
        }

        const int leftCount = count / 2;
        const int middle = first + leftCount;
        std::nth_element(
            cache.triangleOrder.begin() + first,
            cache.triangleOrder.begin() + middle,
            cache.triangleOrder.begin() + first + count,
            [&cache, axis](int a, int b)
            {
                return Component(TriangleCenter(cache.triangles[static_cast<size_t>(a)]), axis) <
                    Component(TriangleCenter(cache.triangles[static_cast<size_t>(b)]), axis);
            });

        const int left = BuildVisibilityBvhNode(cache, first, leftCount);
        const int right = BuildVisibilityBvhNode(cache, middle, count - leftCount);
        cache.bvhNodes[static_cast<size_t>(nodeIndex)].left = left;
        cache.bvhNodes[static_cast<size_t>(nodeIndex)].right = right;
        return nodeIndex;
    }

    void BuildVisibilityBvh(TargetTriangleCache& cache)
    {
        cache.triangleOrder.resize(cache.triangles.size());
        for (size_t index = 0; index < cache.triangleOrder.size(); ++index)
        {
            cache.triangleOrder[index] = static_cast<int>(index);
        }
        cache.bvhNodes.clear();
        cache.bvhNodes.reserve(cache.triangles.size() * 2);
        if (!cache.triangles.empty())
        {
            BuildVisibilityBvhNode(cache, 0, static_cast<int>(cache.triangles.size()));
        }
    }

    bool BuildTargetTriangleCache(INode* targetNode)
    {
        if (targetNode == nullptr)
        {
            g_targetTriangleCache.Clear();
            return false;
        }

        Interface* core = GetCOREInterface();
        const TimeValue time = core->GetTime();
        const ObjectState state = targetNode->EvalWorldState(time);
        Object* object = state.obj;
        if (object == nullptr || !object->CanConvertToType(triObjectClassID))
        {
            g_targetTriangleCache.Clear();
            return false;
        }

        const ULONG nodeHandle = targetNode->GetHandle();
        const Matrix3 objectTM = targetNode->GetObjectTM(time);
        if (g_targetTriangleCache.valid &&
            g_targetTriangleCache.nodeHandle == nodeHandle &&
            g_targetTriangleCache.time == time &&
            g_targetTriangleCache.evaluatedObject == object &&
            NearlyEqual(g_targetTriangleCache.objectTM, objectTM))
        {
            return !g_targetTriangleCache.triangles.empty();
        }

        TriObject* triObject = static_cast<TriObject*>(object->ConvertToType(time, triObjectClassID));
        if (triObject == nullptr)
        {
            g_targetTriangleCache.Clear();
            return false;
        }

        const Mesh& mesh = triObject->GetMesh();
        std::vector<VisibilityTriangle> triangles;
        const int meshFaceCount = static_cast<int>(mesh.numFaces);
        const int meshVertexCount = static_cast<int>(mesh.numVerts);
        triangles.reserve(static_cast<size_t>(std::max(0, meshFaceCount)));

        for (int faceIndex = 0; faceIndex < meshFaceCount; ++faceIndex)
        {
            const Face& face = mesh.faces[faceIndex];
            const int aIndex = static_cast<int>(face.v[0]);
            const int bIndex = static_cast<int>(face.v[1]);
            const int cIndex = static_cast<int>(face.v[2]);
            if (aIndex < 0 || bIndex < 0 || cIndex < 0 ||
                aIndex >= meshVertexCount || bIndex >= meshVertexCount || cIndex >= meshVertexCount)
            {
                continue;
            }

            VisibilityTriangle triangle;
            triangle.a = mesh.verts[aIndex] * objectTM;
            triangle.b = mesh.verts[bIndex] * objectTM;
            triangle.c = mesh.verts[cIndex] * objectTM;
            triangle.normal = NormalizedOrZero(CrossProd(triangle.b - triangle.a, triangle.c - triangle.a));
            triangle.faceIndex = faceIndex;
            if (Length(triangle.normal) > kRayParallelEpsilon)
            {
                triangles.push_back(triangle);
            }
        }

        if (triObject != object)
        {
            triObject->DeleteThis();
        }

        g_targetTriangleCache.valid = true;
        g_targetTriangleCache.nodeHandle = nodeHandle;
        g_targetTriangleCache.time = time;
        g_targetTriangleCache.evaluatedObject = object;
        g_targetTriangleCache.objectTM = objectTM;
        g_targetTriangleCache.triangles.swap(triangles);
        BuildVisibilityBvh(g_targetTriangleCache);
        return !g_targetTriangleCache.triangles.empty();
    }

    mqd_visibility::Vec3 Precise(const Point3& p) { return {p.x, p.y, p.z}; }

    bool IntersectTriangleTwoSided(
        const Ray& ray,
        const VisibilityTriangle& triangle,
        double& parameter)
    {
        return mqd_visibility::IntersectTriangle(Precise(ray.p), Precise(ray.dir),
            Precise(triangle.a), Precise(triangle.b), Precise(triangle.c), parameter);
    }

    bool IntersectBounds(const Ray& ray, const Point3& minimum, const Point3& maximum)
    {
        float nearParameter = 0.0f;
        float farParameter = std::numeric_limits<float>::max();
        for (int axis = 0; axis < 3; ++axis)
        {
            const float origin = Component(ray.p, axis);
            const float direction = Component(ray.dir, axis);
            const float axisMinimum = Component(minimum, axis);
            const float axisMaximum = Component(maximum, axis);
            if (std::abs(direction) <= kRayParallelEpsilon)
            {
                if (origin < axisMinimum || origin > axisMaximum)
                {
                    return false;
                }
                continue;
            }

            float first = (axisMinimum - origin) / direction;
            float second = (axisMaximum - origin) / direction;
            if (first > second)
            {
                std::swap(first, second);
            }
            nearParameter = std::max(nearParameter, first);
            farParameter = std::min(farParameter, second);
            if (farParameter < nearParameter)
            {
                return false;
            }
        }
        return farParameter > kRayStartEpsilon;
    }

    void CollectSortedTargetHits(const Ray& sourceRay, std::vector<VisibilityHit>& hits)
    {
        hits.clear();
        const Point3 direction = NormalizedOrZero(sourceRay.dir);
        if (Length(direction) <= kRayParallelEpsilon)
        {
            return;
        }

        const Ray ray(sourceRay.p, direction);
        hits.reserve(8);
        if (g_targetTriangleCache.bvhNodes.empty())
        {
            return;
        }

        std::vector<int> nodeStack;
        nodeStack.push_back(0);
        while (!nodeStack.empty())
        {
            const int nodeIndex = nodeStack.back();
            nodeStack.pop_back();
            const VisibilityBvhNode& node = g_targetTriangleCache.bvhNodes[static_cast<size_t>(nodeIndex)];
            if (!IntersectBounds(ray, node.minimum, node.maximum))
            {
                continue;
            }

            if (!node.IsLeaf())
            {
                if (node.left >= 0) nodeStack.push_back(node.left);
                if (node.right >= 0) nodeStack.push_back(node.right);
                continue;
            }

            for (int offset = 0; offset < node.count; ++offset)
            {
                const int orderedIndex = g_targetTriangleCache.triangleOrder[static_cast<size_t>(node.first + offset)];
                const VisibilityTriangle& triangle = g_targetTriangleCache.triangles[static_cast<size_t>(orderedIndex)];
                double parameter = 0.0;
                if (IntersectTriangleTwoSided(ray, triangle, parameter))
                {
                    VisibilityHit hit;
                    hit.parameter = parameter;
                    hit.point = ray.p + ray.dir * static_cast<float>(parameter);
                    hit.normal = triangle.normal;
                    hit.faceIndex = triangle.faceIndex;
                    hits.push_back(hit);
                }
            }
        }

        std::sort(hits.begin(), hits.end(), [](const VisibilityHit& a, const VisibilityHit& b)
        {
            return a.parameter < b.parameter;
        });

        if (hits.size() < 2)
        {
            return;
        }

        std::vector<VisibilityHit> uniqueHits;
        uniqueHits.reserve(hits.size());
        const VisibilityBvhNode& rootBounds = g_targetTriangleCache.bvhNodes.front();
        const float mergeEpsilon = std::max(1.0e-6f, Length(rootBounds.maximum - rootBounds.minimum) * 1.0e-7f);
        for (const VisibilityHit& hit : hits)
        {
            if (uniqueHits.empty() || std::abs(hit.parameter - uniqueHits.back().parameter) > mergeEpsilon)
            {
                uniqueHits.push_back(hit);
            }
        }
        hits.swap(uniqueHits);
    }

    bool ScreenRay(ViewExp& viewport, float screenX, float screenY, Ray& worldRay)
    {
        viewport.MapScreenToWorldRay(screenX, screenY, worldRay);
        worldRay.dir = NormalizedOrZero(worldRay.dir);
        return Length(worldRay.dir) > kRayParallelEpsilon;
    }

    float ScriptToViewportPixelScale(ViewExp& viewport)
    {
        // MAXScript's viewPoint/mouse.pos values are expressed in logical
        // pixels.  ViewExp::MapScreenToWorldRay consumes the native viewport
        // pixel coordinates used by GraphicsWindow.  On a DPI-scaled display
        // (the development machine is 225%), passing the logical values
        // unchanged moves the selection ray towards the upper-left.
        using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
        HMODULE user32 = GetModuleHandleW(L"user32.dll");
        GetDpiForWindowFn getDpiForWindowFn = user32 != nullptr
            ? reinterpret_cast<GetDpiForWindowFn>(GetProcAddress(user32, "GetDpiForWindow"))
            : nullptr;

        UINT dpi = 0;
        HWND viewportWindow = viewport.GetHWnd();
        if (getDpiForWindowFn != nullptr && viewportWindow != nullptr)
        {
            dpi = getDpiForWindowFn(viewportWindow);
        }
        if (dpi == 0)
        {
            dpi = g_viewportDpi > 0 ? static_cast<UINT>(g_viewportDpi) : 96U;
        }
        return std::max(1.0f, static_cast<float>(dpi) / 96.0f);
    }

    bool ScriptScreenRay(ViewExp& viewport, float logicalX, float logicalY, Ray& worldRay)
    {
        const float scale = ScriptToViewportPixelScale(viewport);
        return ScreenRay(viewport, logicalX * scale, logicalY * scale, worldRay);
    }

    bool SurfaceHitAt(
        INode* targetNode,
        ViewExp& viewport,
        float screenX,
        float screenY,
        VisibilityHit& hit)
    {
        if (!BuildTargetTriangleCache(targetNode))
        {
            return false;
        }

        Ray worldRay;
        if (!ScriptScreenRay(viewport, screenX, screenY, worldRay))
        {
            return false;
        }

        std::vector<VisibilityHit> hits;
        CollectSortedTargetHits(worldRay, hits);
        if (hits.empty())
        {
            return false;
        }
        hit = hits.front();
        return true;
    }

    void BuildOwnerVertexWorldNormals(
        const MNMesh& mesh,
        const Matrix3& ownerTM,
        std::vector<Point3>& normals,
        std::vector<unsigned char>& hasNormal)
    {
        normals.assign(static_cast<size_t>(mesh.numv), Point3(0.0f, 0.0f, 0.0f));
        hasNormal.assign(static_cast<size_t>(mesh.numv), 0);
        for (int faceIndex = 0; faceIndex < mesh.numf; ++faceIndex)
        {
            const MNFace& face = mesh.f[faceIndex];
            if (face.GetFlag(MN_DEAD) || face.deg < 3)
            {
                continue;
            }

            const int rootIndex = face.vtx[0];
            if (rootIndex < 0 || rootIndex >= mesh.numv)
            {
                continue;
            }
            const Point3 root = mesh.v[rootIndex].p * ownerTM;
            Point3 faceNormal(0.0f, 0.0f, 0.0f);
            for (int corner = 1; corner + 1 < face.deg; ++corner)
            {
                const int bIndex = face.vtx[corner];
                const int cIndex = face.vtx[corner + 1];
                if (bIndex < 0 || cIndex < 0 || bIndex >= mesh.numv || cIndex >= mesh.numv)
                {
                    continue;
                }
                const Point3 b = mesh.v[bIndex].p * ownerTM;
                const Point3 c = mesh.v[cIndex].p * ownerTM;
                faceNormal += CrossProd(b - root, c - root);
            }
            if (Length(faceNormal) > kRayParallelEpsilon)
            {
                for (int corner = 0; corner < face.deg; ++corner)
                {
                    const int vertexIndex = face.vtx[corner];
                    if (vertexIndex >= 0 && vertexIndex < mesh.numv && !mesh.v[vertexIndex].GetFlag(MN_DEAD))
                    {
                        normals[static_cast<size_t>(vertexIndex)] += faceNormal;
                        hasNormal[static_cast<size_t>(vertexIndex)] = 1;
                    }
                }
            }
        }

        for (size_t vertexIndex = 0; vertexIndex < normals.size(); ++vertexIndex)
        {
            normals[vertexIndex] = NormalizedOrZero(normals[vertexIndex]);
            if (Length(normals[vertexIndex]) <= kRayParallelEpsilon)
            {
                hasNormal[vertexIndex] = 0;
            }
        }
    }

    bool CandidateBelongsToVisibleSurfaceLayer(
        const Point3& candidateWorld,
        ViewExp& viewport,
        GraphicsWindow& graphics,
        float surfaceEpsilon,
        bool allowSilhouetteMiss = false)
    {
        // Aim through the actual vertex. Integer-pixel round trips move a ray
        // sideways, and that error can be much larger than a thin layer gap.
        Ray candidateRay;
        Ray centerRay;
        if (!ScreenRay(viewport, graphics.getWinSizeX()*0.5f, graphics.getWinSizeY()*0.5f, centerRay))
        {
            return false;
        }
        if (viewport.IsPerspView())
        {
            Matrix3 worldToView;
            viewport.GetAffineTM(worldToView);
            candidateRay.p = Inverse(worldToView).GetTrans();
            candidateRay.dir = NormalizedOrZero(candidateWorld-candidateRay.p);
            if (DotProd(candidateRay.dir, centerRay.dir) <= 0.0f) return false;
        }
        else
        {
            candidateRay.dir = centerRay.dir;
            const double depth = mqd_visibility::RayDepth(Precise(candidateWorld), Precise(centerRay.p), Precise(centerRay.dir));
            candidateRay.p = candidateWorld-centerRay.dir*static_cast<float>(depth);
        }

        std::vector<VisibilityHit> hits;
        CollectSortedTargetHits(candidateRay, hits);
        if (hits.empty())
        {
            // Component hover keeps the existing pixel tolerance at silhouettes.
            // A missing target ray alone is not evidence of an occluded component.
            return allowSilhouetteMiss;
        }
        // CollectSortedTargetHits normalizes its direction; use the exact same
        // normalization here so the intersection and vertex depths agree.
        const Point3 rayDirection = NormalizedOrZero(candidateRay.dir);
        const double candidateDepth = mqd_visibility::RayDepth(Precise(candidateWorld), Precise(candidateRay.p), Precise(rayDirection));
        if (hits.size() == 1)
        {
            // Open/one-sided targets may have no second intersection. A work
            // vertex far behind their only hit is still occluded; points at or
            // in front of that surface retain the normal projection allowance.
            return candidateDepth-hits.front().parameter <= surfaceEpsilon;
        }

        // Compare every deeper layer, including folded and thin surfaces.
        // Keep tolerance smaller than the layer gap so thin back layers cannot
        // become visible just because the absolute scene-unit epsilon is large.
        for (size_t i = 1; i < hits.size(); ++i)
        {
            if (mqd_visibility::CloserToDeeperLayer(candidateDepth, hits[0].parameter, hits[i].parameter, surfaceEpsilon))
                return false;
        }
        return true;
    }
}

def_visible_primitive(MQDNativeV16BridgeVersion, "MQDNativeV16BridgeVersion");
def_visible_primitive(MQDNativeV16SurfaceHit, "MQDNativeV16SurfaceHit");
def_visible_primitive(MQDNativeV16FilterVisibleCandidateIds, "MQDNativeV16FilterVisibleCandidateIds");
def_visible_primitive(MQDNativeV16InvalidateVisibilityCache, "MQDNativeV16InvalidateVisibilityCache");
def_visible_primitive(MQDNativeV16FilterSurfaceIds, "MQDNativeV16FilterSurfaceIds");
def_visible_primitive(MQDNativeV16FilterStepBuildIds, "MQDNativeV16FilterStepBuildIds");
def_visible_primitive(MQDNativeV16FilterStepBuildSourceIds, "MQDNativeV16FilterStepBuildSourceIds");
def_visible_primitive(MQDNativeV16PrepareStepBuildFace, "MQDNativeV16PrepareStepBuildFace");
def_visible_primitive(MQDNativeV16CommitStepBuildFace, "MQDNativeV16CommitStepBuildFace");
def_visible_primitive(MQDNativeV16CreateFaceSafe, "MQDNativeV16CreateFaceSafe");

Value* MQDNativeV16BridgeVersion_cf(Value**, int count)
{
    check_arg_count(MQDNativeV16BridgeVersion, 0, count);
    return new String(MQD_NATIVE_BRIDGE_VERSION_STRING);
}

Value* MQDNativeV16SurfaceHit_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16SurfaceHit, 4, count);
    INode* targetNode = argList[0]->to_node();
    const float screenX = argList[1]->to_float();
    const float screenY = argList[2]->to_float();
    const float offset = argList[3]->to_float();

    ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
    VisibilityHit hit;
    if (!SurfaceHitAt(targetNode, viewport, screenX, screenY, hit))
    {
        return &undefined;
    }

    MAXScript_TLS* _tls = static_cast<MAXScript_TLS*>(TlsGetValue(thread_locals_index));
    one_typed_value_local_tls(Array* result);
    vl.result = new Array(3);
    vl.result->append(new Point3Value(hit.point + hit.normal * offset));
    vl.result->append(new Point3Value(hit.normal));
    vl.result->append(Integer::intern(hit.faceIndex + 1));
    return_value_tls(vl.result);
}

Value* MQDNativeV16FilterVisibleCandidateIds_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16FilterVisibleCandidateIds, 7, count);
    INode* ownerNode = argList[0]->to_node();
    INode* targetNode = argList[1]->to_node();
    if (!is_array(argList[2]))
    {
        return &undefined;
    }

    Array* candidateIds = static_cast<Array*>(argList[2]);
    const float screenX = argList[3]->to_float();
    const float screenY = argList[4]->to_float();
    const float normalDotThreshold = argList[5]->to_float();
    const float surfaceEpsilon = std::max(kDefaultSurfaceEpsilon, argList[6]->to_float());

    MAXScript_TLS* _tls = static_cast<MAXScript_TLS*>(TlsGetValue(thread_locals_index));
    one_typed_value_local_tls(Array* result);
    vl.result = new Array(candidateIds->size);

    EPoly* epoly = EPolyFromNode(ownerNode);
    MNMesh* ownerMesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
    if (ownerMesh == nullptr || targetNode == nullptr || !BuildTargetTriangleCache(targetNode))
    {
        return_value_tls(vl.result);
    }

    ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
    GraphicsWindow* graphics = viewport.getGW();
    if (graphics == nullptr)
    {
        return_value_tls(vl.result);
    }
    graphics->setTransform(Matrix3());

    VisibilityHit cursorHit;
    if (!SurfaceHitAt(targetNode, viewport, screenX, screenY, cursorHit))
    {
        return_value_tls(vl.result);
    }

    const TimeValue time = GetCOREInterface()->GetTime();
    const Matrix3 ownerTM = ownerNode->GetObjectTM(time);
    std::vector<Point3> ownerVertexNormals;
    std::vector<unsigned char> ownerVertexHasNormal;
    BuildOwnerVertexWorldNormals(*ownerMesh, ownerTM, ownerVertexNormals, ownerVertexHasNormal);
    for (int sourceIndex = 0; sourceIndex < candidateIds->size; ++sourceIndex)
    {
        const int vertexIndex = candidateIds->data[sourceIndex]->to_int() - 1;
        if (vertexIndex < 0 || vertexIndex >= ownerMesh->numv || ownerMesh->v[vertexIndex].GetFlag(MN_DEAD))
        {
            continue;
        }

        const Point3 candidateWorld = ownerMesh->v[vertexIndex].p * ownerTM;
        const bool hasCandidateNormal = ownerVertexHasNormal[static_cast<size_t>(vertexIndex)] != 0;
        const Point3 candidateNormal = ownerVertexNormals[static_cast<size_t>(vertexIndex)];
        if (hasCandidateNormal && DotProd(candidateNormal, cursorHit.normal) < normalDotThreshold)
        {
            continue;
        }

        if (!CandidateBelongsToVisibleSurfaceLayer(candidateWorld, viewport, *graphics, surfaceEpsilon))
        {
            continue;
        }

        vl.result->append(Integer::intern(vertexIndex + 1));
    }
    return_value_tls(vl.result);
}

Value* MQDNativeV16InvalidateVisibilityCache_cf(Value**, int count)
{
    check_arg_count(MQDNativeV16InvalidateVisibilityCache, 0, count);
    g_targetTriangleCache.Clear();
    return &true_value;
}

// Occlusion only: mouse position and averaged work-mesh normals do not decide
// whether a component can be picked. This is also used for candidate obstacles
// and weld destinations, so a rear vertex cannot block or weld into a front one.
Value* MQDNativeV16FilterSurfaceIds_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16FilterSurfaceIds, 4, count);
    INode* owner = argList[0]->to_node();
    INode* target = argList[1]->to_node();
    if (!is_array(argList[2])) return &undefined;
    EPoly* epoly = EPolyFromNode(owner);
    MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
    if (mesh == nullptr || target == owner || !BuildTargetTriangleCache(target)) return &undefined;
    ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
    GraphicsWindow* graphics = viewport.getGW();
    if (graphics == nullptr) return &undefined;
    graphics->setTransform(Matrix3());
    Array* ids = static_cast<Array*>(argList[2]);
    const float epsilon = std::max(kDefaultSurfaceEpsilon, argList[3]->to_float());
    const Matrix3 tm = owner->GetObjectTM(GetCOREInterface()->GetTime());
    MAXScript_TLS* _tls = static_cast<MAXScript_TLS*>(TlsGetValue(thread_locals_index));
    one_typed_value_local_tls(Array* result);
    vl.result = new Array(ids->size);
    for (int i = 0; i < ids->size; ++i)
    {
        const int v = ids->data[i]->to_int() - 1;
        if (v < 0 || v >= mesh->numv || mesh->v[v].GetFlag(MN_DEAD)) continue;
        if (CandidateBelongsToVisibleSurfaceLayer(mesh->v[v].p * tm, viewport, *graphics, epsilon, true))
            vl.result->append(Integer::intern(v + 1));
    }
    return_value_tls(vl.result);
}

namespace
{
    bool BuildStepBuildCandidateMask(MNMesh& mesh, INode& owner, mqd_stepbuild::CandidateMask& mask)
    {
        ViewExp& view = GetCOREInterface()->GetActiveViewExp();
        if (view.getGW() == nullptr) return false;
        Matrix3 viewTM;
        view.GetAffineTM(viewTM);
        const Matrix3 ownerTM = owner.GetObjectTM(GetCOREInterface()->GetTime());
        // Match Step Build: inverse-view row 2, then inverse object linear TM.
        // This is not the target normal and not a smoothed vertex normal.
        const Point3 row0 = ownerTM.GetRow(0), row1 = ownerTM.GetRow(1), row2 = ownerTM.GetRow(2);
        const double determinant = mqd_visibility::Dot(Precise(row0), mqd_visibility::Cross(Precise(row1), Precise(row2)));
        if (!std::isfinite(determinant) || determinant == 0.0) return false;
        Matrix3 inverseOwner = Inverse(ownerTM);
        inverseOwner.NoTrans();
        const Point3 objectViewZ = Inverse(viewTM).GetRow(2) * inverseOwner;
        const double lengthSq = mqd_visibility::Dot(Precise(objectViewZ), Precise(objectViewZ));
        if (!std::isfinite(lengthSq) || lengthSq == 0.0) return false;

        std::vector<unsigned char> boundaryFaces(static_cast<size_t>(mesh.numf), 0);
        for (int e = 0; e < mesh.nume; ++e)
        {
            const MNEdge& edge = mesh.e[e];
            if (edge.GetFlag(MN_DEAD)) continue;
            const bool open = edge.f2 == -1 && edge.f1 >= 0 && edge.f1 < mesh.numf && !mesh.f[edge.f1].GetFlag(MN_DEAD);
            mask.MarkEdgeVertex(edge.v1, open);
            mask.MarkEdgeVertex(edge.v2, open);
            if (open) boundaryFaces[static_cast<size_t>(edge.f1)] = 1;
        }
        for (int f = 0; f < mesh.numf; ++f)
        {
            const MNFace& face = mesh.f[f];
            if (face.GetFlag(MN_DEAD) || face.deg < 3) continue;
            const bool facing = boundaryFaces[static_cast<size_t>(f)] &&
                mqd_stepbuild::FacingBoundaryFace(Precise(mesh.GetFaceNormal(f, true)), Precise(objectViewZ));
            for (int c = 0; c < face.deg; ++c)
            {
                mask.MarkFaceVertex(face.vtx[c]);
                if (facing) mask.SeedFacingFaceVertex(face.vtx[c]);
            }
        }
        return true;
    }
}

// Read-only candidate-domain query. Ordinary picking and welding still use
// FilterSurfaceIds. The caller intersects this result with that layer filter.
Value* FilterStepBuildIdsImpl(Value** argList, bool sourceOnly)
{
    INode* owner = argList[0]->to_node();
    if (owner == nullptr || !is_array(argList[1])) return &undefined;
    EPoly* epoly = EPolyFromNode(owner);
    MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
    if (mesh == nullptr) return &undefined;
    mqd_stepbuild::CandidateMask mask(mesh->numv);
    if (!BuildStepBuildCandidateMask(*mesh, *owner, mask)) return &undefined;
    Array* ids = static_cast<Array*>(argList[1]);
    MAXScript_TLS* _tls = static_cast<MAXScript_TLS*>(TlsGetValue(thread_locals_index));
    one_typed_value_local_tls(Array* result);
    vl.result = new Array(ids->size);
    for (int i = 0; i < ids->size; ++i)
    {
        const int v = ids->data[i]->to_int() - 1;
        if (v < 0 || v >= mesh->numv) continue;
        const bool dead = mesh->v[v].GetFlag(MN_DEAD) != 0;
        const bool hidden = mesh->v[v].GetFlag(MN_HIDDEN) != 0;
        if (sourceOnly ? mask.SourceEligible(v, dead, hidden) : mask.Eligible(v, dead, hidden))
            vl.result->append(Integer::intern(v + 1));
    }
    return_value_tls(vl.result);
}

Value* MQDNativeV16FilterStepBuildIds_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16FilterStepBuildIds, 2, count);
    return FilterStepBuildIdsImpl(argList, false);
}

Value* MQDNativeV16FilterStepBuildSourceIds_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16FilterStepBuildSourceIds, 2, count);
    return FilterStepBuildIdsImpl(argList, true);
}

namespace
{
    bool ExistingFaceGeometryUnchanged(const MNMesh& before, const MNMesh& after)
    {
        if (before.numv != after.numv || after.numf < before.numf) return false;
        for (int i = 0; i < before.numv; ++i)
        {
            const Point3& p = after.v[i].p;
            if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z) ||
                p != before.v[i].p || before.v[i].GetFlag(MN_DEAD) != after.v[i].GetFlag(MN_DEAD)) return false;
        }
        for (int i = 0; i < before.numf; ++i)
        {
            const MNFace& a = before.f[i];
            const MNFace& b = after.f[i];
            if (a.deg != b.deg || a.GetFlag(MN_DEAD) != b.GetFlag(MN_DEAD) ||
                a.material != b.material || a.smGroup != b.smGroup) return false;
            for (int j = 0; j < a.deg; ++j)
                if (a.vtx[j] != b.vtx[j] || a.edg[j] != b.edg[j]) return false;
        }
        return true;
    }

    bool IsOnlyRequestedFace(const MNMesh& before, const MNMesh& after, int index, const std::vector<int>& ids)
    {
        if (index != before.numf || after.numf != before.numf + 1 ||
            !ExistingFaceGeometryUnchanged(before, after)) return false;
        const MNFace& face = after.f[index];
        if (face.GetFlag(MN_DEAD) || face.deg != static_cast<int>(ids.size())) return false;
        for (int j = 0; j < face.deg; ++j) if (face.vtx[j] != ids[static_cast<size_t>(j)]) return false;
        return true;
    }

    bool StepBuildIdsAndTopologyValid(MNMesh& mesh, INode& owner, const std::vector<int>& ids)
    {
        mqd_stepbuild::CandidateMask mask(mesh.numv);
        if (!BuildStepBuildCandidateMask(mesh, owner, mask)) return false;
        for (int id : ids)
            if (!mask.Eligible(id, mesh.v[id].GetFlag(MN_DEAD) != 0, mesh.v[id].GetFlag(MN_HIDDEN) != 0)) return false;
        for (int f = 0; f < mesh.numf; ++f)
        {
            const MNFace& face = mesh.f[f];
            if (!face.GetFlag(MN_DEAD) && face.deg >= 3 &&
                mqd_stepbuild::SharesThreeFaceVertices(ids, face.vtx, face.deg)) return false;
        }
        return true;
    }

    bool StepBuildResultFacesView(MNMesh& mesh, int faceIndex, INode& owner)
    {
        if (faceIndex < 0 || faceIndex >= mesh.numf) return false;
        ViewExp& view = GetCOREInterface()->GetActiveViewExp();
        GraphicsWindow* graphics = view.getGW();
        if (graphics == nullptr) return false;
        Ray centerRay;
        if (!ScreenRay(view, graphics->getWinSizeX()*0.5f, graphics->getWinSizeY()*0.5f, centerRay)) return false;
        Matrix3 viewTM;
        view.GetAffineTM(viewTM);
        Matrix3 ownerTM = owner.GetObjectTM(GetCOREInterface()->GetTime());
        const MNFace& face = mesh.f[faceIndex];
        Point3 center(0.0f,0.0f,0.0f);
        for (int c = 0; c < face.deg; ++c) center += mesh.v[face.vtx[c]].p;
        center = (center / static_cast<float>(face.deg)) * ownerTM;
        Point3 towardEye = -centerRay.dir;
        if (view.IsPerspView())
        {
            towardEye = Inverse(viewTM).GetTrans() - center;
            if (DotProd(towardEye, centerRay.dir) >= 0.0f) return false;
        }
        towardEye = NormalizedOrZero(towardEye);
        ownerTM.NoTrans();
        // Match PolyTools' post-create face-normal/linear-TM test. Direction
        // correction is decided in preparation, never substituted at commit.
        const Point3 normal = NormalizedOrZero(mesh.GetFaceNormal(faceIndex, true) * ownerTM);
        return Length(normal) > kRayParallelEpsilon && Length(towardEye) > kRayParallelEpsilon &&
            mqd_stepbuild::FacingBoundaryFace(Precise(normal), Precise(towardEye));
    }
}

// A read-only counterpart to Step Build's final face checks. A disposable mesh
// resolves the SAME orientation constraints used by CreateFaceSafe. A reverse
// cycle is permitted only if both topology and camera facing accept it. This
// avoids turning an invalid overlapping candidate into a backwards real face.
Value* MQDNativeV16PrepareStepBuildFace_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16PrepareStepBuildFace, 2, count);
    INode* owner = argList[0]->to_node();
    if (owner == nullptr || !is_array(argList[1])) return &undefined;
    EPoly* epoly = EPolyFromNode(owner);
    MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
    Array* input = static_cast<Array*>(argList[1]);
    if (mesh == nullptr || (input->size != 3 && input->size != 4)) return &undefined;
    std::vector<int> ids;
    for (int i = 0; i < input->size; ++i)
    {
        const int v = input->data[i]->to_int() - 1;
        if (v < 0 || v >= mesh->numv || mesh->v[v].GetFlag(MN_DEAD) ||
            std::find(ids.begin(), ids.end(), v) != ids.end()) return &undefined;
        ids.push_back(v);
    }
    if (!StepBuildIdsAndTopologyValid(*mesh, *owner, ids)) return &undefined;

    bool valid = false;
    for (int orientation = 0; orientation < 2 && !valid; ++orientation)
    {
        if (orientation == 1) std::reverse(ids.begin(), ids.end());
        MNMesh trial(*mesh);
        const int face = trial.CreateFace(static_cast<int>(ids.size()), ids.data());
        if (!IsOnlyRequestedFace(*mesh, trial, face, ids)) continue;
        valid = StepBuildResultFacesView(trial, face, *owner);
    }
    if (!valid) return &undefined;
    MAXScript_TLS* _tls = static_cast<MAXScript_TLS*>(TlsGetValue(thread_locals_index));
    one_typed_value_local_tls(Array* result);
    vl.result = new Array(input->size);
    for (int id : ids) vl.result->append(Integer::intern(id + 1));
    return_value_tls(vl.result);
}

// Ordered node-local creation: never asks PolyTools' global selection-based
// command to infer/reorder a set of points. EPoly's own TopoChangeRestore owns
// Undo/Redo; Begin/Accept/Cancel are balanced within this synchronous call.
Value* CreateFaceSafeImpl(Value** argList, bool strictStepBuild)
{
    INode* owner = argList[0]->to_node();
    if (!is_array(argList[1])) return &undefined;
    Array* input = static_cast<Array*>(argList[1]);
    EPoly* epoly = EPolyFromNode(owner);
    MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
    if (mesh == nullptr || (input->size != 3 && input->size != 4) || theHold.IsSuspended()) return &undefined;
    std::vector<int> ids;
    for (int i = 0; i < input->size; ++i)
    {
        const int v = input->data[i]->to_int() - 1;
        if (v < 0 || v >= mesh->numv || mesh->v[v].GetFlag(MN_DEAD) ||
            std::find(ids.begin(), ids.end(), v) != ids.end()) return &undefined;
        ids.push_back(v);
    }
    for (int i = 0; i < mesh->numf; ++i)
    {
        const MNFace& f = mesh->f[i];
        if (f.GetFlag(MN_DEAD) || f.deg != static_cast<int>(ids.size())) continue;
        bool sameVertices = true;
        for (int j = 0; j < f.deg; ++j)
            if (std::find(ids.begin(), ids.end(), f.vtx[j]) == ids.end()) sameVertices = false;
        if (sameVertices) return &undefined;
    }
    if (strictStepBuild && !StepBuildIdsAndTopologyValid(*mesh, *owner, ids)) return &undefined;
    const MNMesh before(*mesh);
    // Prove that exactly this cycle can be added on a disposable mesh first.
    MNMesh trial(before);
    int trialFace = trial.CreateFace(static_cast<int>(ids.size()), ids.data());
    if (trialFace < 0 && !strictStepBuild)
    {
        std::reverse(ids.begin(), ids.end());
        trial = before;
        trialFace = trial.CreateFace(static_cast<int>(ids.size()), ids.data());
    }
    if (!IsOnlyRequestedFace(before, trial, trialFace, ids) ||
        (strictStepBuild && !StepBuildResultFacesView(trial, trialFace, *owner)))
    {
        AppendCallbackLog("face.safe.rejected=dry-run\r\n");
        return &undefined;
    }

    theHold.Begin();
    if (!theHold.Holding())
    {
        theHold.Cancel();
        AppendCallbackLog("face.safe.rejected=undo-unavailable\r\n");
        return &undefined;
    }
    bool accepted = false;
    int face = -1;
    const int putCountBefore = theHold.GetGlobalPutCount();
    try
    {
        face = epoly->EpfnCreateFace(ids.data(), static_cast<int>(ids.size()), false);
        accepted = IsOnlyRequestedFace(before, *mesh, face, ids) &&
            theHold.GetGlobalPutCount() > putCountBefore &&
            (!strictStepBuild || StepBuildResultFacesView(*mesh, face, *owner));
    }
    catch (...) { accepted = false; }
    if (!accepted)
    {
        theHold.Cancel();
        // An exception can precede registration of EPoly's native restore.
        // Preserve the pre-operation mesh even in that failure path.
        *mesh = before;
        mesh->InvalidateGeomCache();
        epoly->LocalDataChanged(TOPO_CHANNEL | GEOM_CHANNEL | SELECT_CHANNEL);
        AppendCallbackLog("face.safe.rolled-back=true\r\n");
        return &undefined;
    }
    theHold.Accept(_T("MQD Safe Face"));
    char record[192];
    snprintf(record, sizeof(record),
        "face.safe.committed=true geometryUnchanged=true undo=native-topology records=%d parentHoldDepth=%d\r\n",
        theHold.GetGlobalPutCount() - putCountBefore, theHold.GetBeginDepth());
    AppendCallbackLog(record);
    return Integer::intern(face + 1);
}

Value* MQDNativeV16CreateFaceSafe_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16CreateFaceSafe, 2, count);
    return CreateFaceSafeImpl(argList, false);
}

Value* MQDNativeV16CommitStepBuildFace_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV16CommitStepBuildFace, 2, count);
    return CreateFaceSafeImpl(argList, true);
}
