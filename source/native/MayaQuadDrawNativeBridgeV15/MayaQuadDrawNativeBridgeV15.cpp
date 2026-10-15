#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <vector>
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include "SettingsTabPolicy.h"

#include <guplib.h>
#include <maxapi.h>
#include <GraphicsWindow.h>
#include <hold.h>
#include <iepoly.h>
#include <mnmesh.h>

#include <maxscript/maxscript.h>
#include <maxscript/foundation/ValueHolderMember.h>
#include <maxscript/foundation/functions.h>
#include <maxscript/foundation/numbers.h>
#include <maxscript/foundation/strings.h>
#include <maxscript/kernel/exceptions.h>

// The V16 bridge compiles this proven input/Relax implementation into the new
// binary and supplies version-specific metadata before including this file.
// A direct V15 build keeps the original values below.
#ifndef MQD_NATIVE_BRIDGE_CLASS_ID_A
#define MQD_NATIVE_BRIDGE_CLASS_ID_A 0x6b704d57
#endif
#ifndef MQD_NATIVE_BRIDGE_CLASS_ID_B
#define MQD_NATIVE_BRIDGE_CLASS_ID_B 0x3f157b46
#endif
#ifndef MQD_NATIVE_BRIDGE_CLASS_NAME
#define MQD_NATIVE_BRIDGE_CLASS_NAME _T("Maya Quad Draw Native Bridge V15")
#endif
#ifndef MQD_NATIVE_BRIDGE_DESCRIPTION
#define MQD_NATIVE_BRIDGE_DESCRIPTION _T("Maya Quad Draw V15 native internal relax bridge for 3ds Max 2024")
#endif
#ifndef MQD_NATIVE_BRIDGE_VERSION_STRING
#define MQD_NATIVE_BRIDGE_VERSION_STRING _T("0.16.0-max2024-v15-native-brush-relax")
#endif

namespace
{
    HMODULE g_module = nullptr;
    std::atomic<long long> g_trackCallbackCount{0};
    std::atomic<bool> g_stopScheduled{false};
    std::atomic<UINT_PTR> g_watchdogTimerId{0};
    // Main-thread session ownership. Command pointers are compared only, never
    // dereferenced after Max changes modes. No scene/Undo data lives here.
    unsigned long long g_sessionGeneration = 0;
    CommandMode* g_sessionCommand = nullptr;
    bool g_sessionWatching = false;
    bool g_sessionCommandLost = false;
    UINT_PTR g_sessionTimerId = 0;
    int g_sessionPendingFlags = 0;
    constexpr int kSettingsTabRequest = 4;
    HHOOK g_settingsTabHook = nullptr;
    mqd::SettingsTabKeyState g_settingsTabKey;
    bool g_settingsTabPendingToggle = false;
    unsigned long long g_stopGeneration = 0;
    CommandMode* g_stopCommand = nullptr;
    ValueHolderMember g_buildDelegate;
    ValueHolderMember g_moveDelegate;
    ValueHolderMember g_borderDelegate;
    ValueHolderMember g_optimizerDelegate;

    enum class GestureRoute
    {
        None,
        Build,
        Move,
        Border,
        Optimizer
    };

    GestureRoute g_activeGesture = GestureRoute::None;

    struct PressCaptureState
    {
        bool valid = false;
        bool buttonDown = false;
        bool crossedThreshold = false;
        bool moveHintAtPress = false;
        bool shiftAtPress = false;
        bool ctrlAtPress = false;
        bool altAtPress = false;
        POINT start{};
        POINT current{};
    };

    PressCaptureState g_press;
    bool g_hoverMoveHint = false;
    HWND g_hookedViewport = nullptr;
    int g_viewportDpi = 96;
    int g_dragThresholdX = 6;
    int g_dragThresholdY = 6;
    constexpr int kLogicalDragThreshold = 6;
    constexpr UINT_PTR kViewportSubclassId = 0x4D5144563132ULL;

    constexpr Class_ID kBridgeGupClassId(MQD_NATIVE_BRIDGE_CLASS_ID_A, MQD_NATIVE_BRIDGE_CLASS_ID_B);

    bool g_relaxStrokeActive = false;
    bool g_relaxOwnsHold = false;

    void AppendCallbackLog(const char* text);

    EPoly* EPolyFromNode(INode* node)
    {
        if (node == nullptr)
        {
            return nullptr;
        }
        Object* object = node->GetObjectRef();
        // Use Max's documented base-object resolver. The derived object owns
        // the modifier stack, not the Editable Poly control mesh/interface.
        object = object != nullptr ? object->FindBaseObject() : nullptr;
        return object != nullptr
            ? static_cast<EPoly*>(object->GetInterface(EPOLY_INTERFACE))
            : nullptr;
    }

    class RelaxStrokeRestore final : public RestoreObj
    {
    public:
        explicit RelaxStrokeRestore(INode* node)
            : m_node(node)
        {
            Capture(m_undo);
        }

        void Restore(int isUndo) override
        {
            if (isUndo)
            {
                Capture(m_redo);
            }
            Apply(m_undo);
        }

        void Redo() override
        {
            Apply(m_redo);
        }

        int Size() override
        {
            return static_cast<int>(sizeof(*this) + (m_undo.size() + m_redo.size()) * sizeof(Point3));
        }

        TSTR Description() override
        {
            return TSTR(_T("Maya Quad Draw Relax"));
        }

    private:
        void Capture(std::vector<Point3>& points)
        {
            EPoly* epoly = EPolyFromNode(m_node);
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
            EPoly* epoly = EPolyFromNode(m_node);
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

        INode* m_node = nullptr;
        std::vector<Point3> m_undo;
        std::vector<Point3> m_redo;
    };

    bool IsBoundaryVertex(const MNMesh& mesh, int vertexIndex)
    {
        if (vertexIndex < 0 || vertexIndex >= mesh.numv)
        {
            return true;
        }
        const MNVert& vertex = mesh.v[vertexIndex];
        if (vertex.GetFlag(MN_DEAD))
        {
            return true;
        }
        Tab<int>* vertexEdges = mesh.GetVEdge();
        if (vertexEdges == nullptr)
        {
            return true;
        }
        const Tab<int>& edgesForVertex = vertexEdges[vertexIndex];
        for (int edgeSlot = 0; edgeSlot < edgesForVertex.Count(); ++edgeSlot)
        {
            const int edgeIndex = edgesForVertex[edgeSlot];
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

    float SmoothBrushWeight(float distancePixels, float radiusPixels, float focusPercent)
    {
        if (distancePixels > radiusPixels)
        {
            return 0.0f;
        }
        const float focus = std::clamp(focusPercent * 0.01f, 0.0f, 1.0f);
        const float innerRadius = radiusPixels * focus;
        if (distancePixels <= innerRadius || radiusPixels <= innerRadius + 0.0001f)
        {
            return 1.0f;
        }
        const float t = std::clamp((distancePixels - innerRadius) / (radiusPixels - innerRadius), 0.0f, 1.0f);
        const float smoothStep = t * t * (3.0f - 2.0f * t);
        return 1.0f - smoothStep;
    }

    bool ProjectToPickedSurface(
        INode* targetNode,
        ViewExp& viewport,
        const Point3& tentativeWorld,
        float offset,
        Point3& projectedWorld)
    {
        if (targetNode == nullptr)
        {
            return false;
        }
        const TimeValue time = GetCOREInterface()->GetTime();
        ObjectState state = targetNode->EvalWorldState(time);
        Object* targetObject = state.obj;
        if (targetObject == nullptr)
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
        if (!targetObject->IntersectRay(time, objectRay, at, objectNormal))
        {
            return false;
        }
        Point3 hitObject = objectRay.p + objectRay.dir * at;
        Point3 worldNormal = VectorTransform(targetTM, objectNormal);
        const float normalLength = Length(worldNormal);
        if (normalLength > 0.000001f)
        {
            worldNormal /= normalLength;
        }
        projectedWorld = hitObject * targetTM + worldNormal * offset;
        return true;
    }

    bool ApplyRelaxStep(
        INode* ownerNode,
        INode* targetNode,
        int seedFace,
        float screenX,
        float screenY,
        float radius,
        float focus,
        float strength,
        float offset)
    {
        EPoly* epoly = EPolyFromNode(ownerNode);
        MNMesh* mesh = epoly != nullptr ? epoly->GetMeshPtr() : nullptr;
        if (mesh == nullptr || mesh->numv == 0 || seedFace < 0 || seedFace >= mesh->numf)
        {
            return false;
        }
        if (!mesh->GetFlag(MN_MESH_FILLED_IN))
        {
            mesh->FillInMesh();
        }
        if (mesh->f[seedFace].GetFlag(MN_DEAD))
        {
            return false;
        }

        ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
        GraphicsWindow* graphics = viewport.getGW();
        if (graphics == nullptr)
        {
            return false;
        }
        const TimeValue time = GetCOREInterface()->GetTime();
        const Matrix3 ownerTM = ownerNode->GetObjectTM(time);
        const Matrix3 inverseOwnerTM = Inverse(ownerTM);
        graphics->setTransform(Matrix3());

        // Max's painter sizes are logical UI units.  GraphicsWindow coordinates
        // are DPI-scaled viewport pixels, so keep the brush consistent on the
        // user's 4K/high-DPI display.
        const float dpiScale = std::max(1.0f, static_cast<float>(g_viewportDpi) / 96.0f);
        radius = std::max(radius, 1.0f) * dpiScale;
        focus = std::clamp(focus, 0.0f, 100.0f);
        strength = std::clamp(strength, 0.0f, 1.0f);

        std::vector<float> brushWeights(static_cast<size_t>(mesh->numv), 0.0f);
        std::vector<float> screenDistances(static_cast<size_t>(mesh->numv), 1.0e30f);
        std::vector<unsigned char> reachable(static_cast<size_t>(mesh->numv), 0);
        std::vector<int> queue;
        Tab<int>* vertexEdges = mesh->GetVEdge();
        if (vertexEdges == nullptr)
        {
            return false;
        }
        const MNFace& face = mesh->f[seedFace];
        for (int corner = 0; corner < face.deg; ++corner)
        {
            const int vertexIndex = face.vtx[corner];
            if (vertexIndex >= 0 && vertexIndex < mesh->numv && !reachable[static_cast<size_t>(vertexIndex)])
            {
                reachable[static_cast<size_t>(vertexIndex)] = 1;
                queue.push_back(vertexIndex);
            }
        }

        for (size_t queueIndex = 0; queueIndex < queue.size(); ++queueIndex)
        {
            const int vertexIndex = queue[queueIndex];
            const Point3 worldPoint = mesh->v[vertexIndex].p * ownerTM;
            IPoint3 screen{};
            graphics->wTransPoint(&worldPoint, &screen);
            const float dx = static_cast<float>(screen.x) - screenX;
            const float dy = static_cast<float>(screen.y) - screenY;
            const float distancePixels = std::sqrt(dx * dx + dy * dy);
            screenDistances[static_cast<size_t>(vertexIndex)] = distancePixels;

            // Topology traversal is independent of the circular brush test.
            // Stopping here when a seed-face corner was outside the radius made
            // the old bridge collapse to a single fallback vertex.
            const Tab<int>& edgesForVertex = vertexEdges[vertexIndex];
            for (int edgeSlot = 0; edgeSlot < edgesForVertex.Count(); ++edgeSlot)
            {
                const int edgeIndex = edgesForVertex[edgeSlot];
                if (edgeIndex < 0 || edgeIndex >= mesh->nume || mesh->e[edgeIndex].GetFlag(MN_DEAD))
                {
                    continue;
                }
                const MNEdge& edge = mesh->e[edgeIndex];
                const int neighbor = edge.v1 == vertexIndex ? edge.v2 : edge.v1;
                if (neighbor >= 0 && neighbor < mesh->numv && !reachable[static_cast<size_t>(neighbor)])
                {
                    reachable[static_cast<size_t>(neighbor)] = 1;
                    queue.push_back(neighbor);
                }
            }
        }

        // Use the configured screen-space radius on normal-density meshes.  On
        // sparse retopology, expand just enough to include a small local patch;
        // this preserves a real falloff instead of snapping one vertex.
        std::vector<float> movableDistances;
        movableDistances.reserve(queue.size());
        int verticesInsideRadius = 0;
        for (int vertexIndex : queue)
        {
            if (vertexIndex < 0 || vertexIndex >= mesh->numv ||
                mesh->v[vertexIndex].GetFlag(MN_DEAD) || IsBoundaryVertex(*mesh, vertexIndex))
            {
                continue;
            }
            const float distancePixels = screenDistances[static_cast<size_t>(vertexIndex)];
            movableDistances.push_back(distancePixels);
            if (distancePixels <= radius)
            {
                ++verticesInsideRadius;
            }
        }

        float effectiveRadius = radius;
        if (!movableDistances.empty())
        {
            std::sort(movableDistances.begin(), movableDistances.end());
            const size_t minimumPatchSize = std::min<size_t>(4, movableDistances.size());
            if (verticesInsideRadius < static_cast<int>(minimumPatchSize))
            {
                const float patchEdgeDistance = movableDistances[minimumPatchSize - 1];
                effectiveRadius = std::max(radius, patchEdgeDistance + std::max(1.0f, radius * 0.15f));
            }
        }

        for (int vertexIndex : queue)
        {
            if (vertexIndex < 0 || vertexIndex >= mesh->numv ||
                mesh->v[vertexIndex].GetFlag(MN_DEAD) || IsBoundaryVertex(*mesh, vertexIndex))
            {
                continue;
            }
            const float distancePixels = screenDistances[static_cast<size_t>(vertexIndex)];
            brushWeights[static_cast<size_t>(vertexIndex)] = SmoothBrushWeight(distancePixels, effectiveRadius, focus);
        }

        mesh->ClearVFlags(MN_USER);
        bool anyWeight = false;
        for (int vertexIndex = 0; vertexIndex < mesh->numv; ++vertexIndex)
        {
            if (!mesh->v[vertexIndex].GetFlag(MN_DEAD))
            {
                mesh->v[vertexIndex].SetFlag(MN_USER);
            }
            anyWeight = anyWeight || brushWeights[static_cast<size_t>(vertexIndex)] > 0.00001f;
        }

        if (!anyWeight || strength <= 0.00001f)
        {
            mesh->ClearVFlags(MN_USER);
            AppendCallbackLog("relax.step=false reason=no-movable-weight\r\n");
            return false;
        }

        Tab<Point3> delta;
        delta.SetCount(mesh->numv);
        MNMeshUtilities utilities(mesh);
        const float nativeAmount = 0.5f * strength;
        const bool relaxed = utilities.Relax(
            MN_USER,
            brushWeights.data(),
            nativeAmount,
            1,
            true,
            false,
            delta.Addr(0));
        mesh->ClearVFlags(MN_USER);
        if (!relaxed)
        {
            AppendCallbackLog("relax.step=false reason=native-relax-rejected\r\n");
            return false;
        }

        bool changed = false;
        for (int vertexIndex = 0; vertexIndex < mesh->numv; ++vertexIndex)
        {
            if (brushWeights[static_cast<size_t>(vertexIndex)] <= 0.00001f || IsBoundaryVertex(*mesh, vertexIndex))
            {
                continue;
            }
            const Point3 tentativeLocal = mesh->v[vertexIndex].p + delta[vertexIndex];
            const Point3 tentativeWorld = tentativeLocal * ownerTM;
            Point3 projectedWorld;
            mesh->v[vertexIndex].p = ProjectToPickedSurface(targetNode, viewport, tentativeWorld, offset, projectedWorld)
                ? projectedWorld * inverseOwnerTM
                : tentativeLocal;
            changed = true;
        }
        if (!changed)
        {
            return false;
        }
        mesh->SetFlag(MN_CACHEINVALID);
        epoly->LocalDataChanged(GEOM_CHANNEL);
        epoly->RefreshScreen();
        return true;
    }

    bool RemovePressHook();
    void EndSessionWatch();

    class BridgeGup final : public GUP
    {
    public:
        DWORD Start() override { return GUPRESULT_KEEP; }
        void Stop() override { EndSessionWatch(); RemovePressHook(); }
        DWORD_PTR Control(DWORD) override { return 0; }
        void DeleteThis() override { delete this; }
    };

    class BridgeGupClassDesc final : public ClassDesc
    {
    public:
        int IsPublic() override { return FALSE; }
        void* Create(BOOL = FALSE) override { return new BridgeGup(); }
        const TCHAR* ClassName() override { return MQD_NATIVE_BRIDGE_CLASS_NAME; }
        const TCHAR* NonLocalizedClassName() override { return MQD_NATIVE_BRIDGE_CLASS_NAME; }
        SClass_ID SuperClassID() override { return GUP_CLASS_ID; }
        Class_ID ClassID() override { return kBridgeGupClassId; }
        const TCHAR* Category() override { return _T(""); }
    };

    BridgeGupClassDesc g_bridgeGupClassDesc;

    std::wstring CallbackLogPath()
    {
        wchar_t modulePath[MAX_PATH]{};
        const DWORD length = GetModuleFileNameW(g_module, modulePath, MAX_PATH);
        std::wstring path(modulePath, length);

        const std::wstring::size_type fileSeparator = path.find_last_of(L"\\/");
        if (fileSeparator != std::wstring::npos)
        {
            const std::wstring moduleDirectory = path.substr(0, fileSeparator);
            const std::wstring::size_type parentSeparator = moduleDirectory.find_last_of(L"\\/");
            if (parentSeparator != std::wstring::npos)
            {
                const std::wstring packageRoot = moduleDirectory.substr(0, parentSeparator);
                const std::wstring logsDirectory = packageRoot + L"\\logs";
                const DWORD attributes = GetFileAttributesW(logsDirectory.c_str());
                if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
                {
                    return logsDirectory + L"\\MayaQuadDraw_InputBridge.callback.txt";
                }
            }
        }

        const std::wstring::size_type extension = path.find_last_of(L'.');
        if (extension != std::wstring::npos)
        {
            path.resize(extension);
        }
        path += L".callback.txt";
        return path;
    }

    void WriteCallbackLog(long long callbackCount, int argCount)
    {
        const std::wstring path = CallbackLogPath();
        HANDLE file = CreateFileW(
            path.c_str(),
            GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return;
        }

        char buffer[256]{};
        const int length = sprintf_s(
            buffer,
            "callback.count=%lld\r\ncallback.argCount=%d\r\ncallback.threadId=%lu\r\ncallback.return=false\r\n",
            callbackCount,
            argCount,
            GetCurrentThreadId());
        DWORD written = 0;
        if (length > 0)
        {
            WriteFile(file, buffer, static_cast<DWORD>(length), &written, nullptr);
            FlushFileBuffers(file);
        }
        CloseHandle(file);
    }

    void AppendCallbackLog(const char* text)
    {
        const std::wstring path = CallbackLogPath();
        HANDLE file = CreateFileW(
            path.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return;
        }

        DWORD written = 0;
        WriteFile(file, text, static_cast<DWORD>(strlen(text)), &written, nullptr);
        FlushFileBuffers(file);
        CloseHandle(file);
    }

    std::string ToUtf8(const std::wstring& text)
    {
        if (text.empty())
        {
            return {};
        }

        const int size = WideCharToMultiByte(
            CP_UTF8,
            0,
            text.data(),
            static_cast<int>(text.size()),
            nullptr,
            0,
            nullptr,
            nullptr);
        if (size <= 0)
        {
            return {};
        }

        std::string result(static_cast<size_t>(size), '\0');
        WideCharToMultiByte(
            CP_UTF8,
            0,
            text.data(),
            static_cast<int>(text.size()),
            result.data(),
            size,
            nullptr,
            nullptr);
        return result;
    }

    void AppendCallbackLog(const std::wstring& text)
    {
        const std::string utf8 = ToUtf8(text);
        if (!utf8.empty())
        {
            AppendCallbackLog(utf8.c_str());
        }
    }

    std::wstring ValueRepresentation(Value* value)
    {
        if (value == nullptr)
        {
            return L"<null>";
        }

        try
        {
            StringStream* stream = new StringStream(256);
            ValueHolderMember streamHolder(stream);
            value->sprin1(stream);
            return stream->content_string != nullptr ? std::wstring(stream->content_string) : L"<empty>";
        }
        catch (...)
        {
            return L"<unprintable>";
        }
    }

    void WriteProtocolEvent(
        long long callbackCount,
        const std::vector<std::wstring>& arguments,
        Value* result)
    {
        if (callbackCount > 400)
        {
            return;
        }

        std::wstring line = L"event=" + std::to_wstring(callbackCount);
        for (size_t index = 0; index < arguments.size(); ++index)
        {
            line += L" arg" + std::to_wstring(index) + L"=" + arguments[index];
        }
        line += L" result=" + ValueRepresentation(result) + L"\r\n";
        AppendCallbackLog(line);
    }

    void ResetPressCapture()
    {
        g_press = PressCaptureState{};
    }

    void UpdateThresholdState(POINT current)
    {
        if (!g_press.valid)
        {
            return;
        }

        g_press.current = current;
        const LONG dx = current.x - g_press.start.x;
        const LONG dy = current.y - g_press.start.y;
        if (std::abs(dx) >= g_dragThresholdX || std::abs(dy) >= g_dragThresholdY)
        {
            g_press.crossedThreshold = true;
        }
    }

    LRESULT CALLBACK ViewportSubclassProc(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam,
        UINT_PTR,
        DWORD_PTR)
    {
        if (message == WM_LBUTTONDOWN)
        {
            ResetPressCapture();
            g_press.valid = true;
            g_press.buttonDown = true;
            g_press.moveHintAtPress = g_hoverMoveHint;
            g_press.shiftAtPress = (wParam & MK_SHIFT) != 0;
            g_press.ctrlAtPress = (wParam & MK_CONTROL) != 0;
            g_press.altAtPress = (GetKeyState(VK_MENU) & 0x8000) != 0;
            g_press.start = POINT{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            g_press.current = g_press.start;
        }
        else if (message == WM_MOUSEMOVE && (wParam & MK_LBUTTON) != 0)
        {
            UpdateThresholdState(POINT{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) });
        }
        else if (message == WM_LBUTTONUP)
        {
            UpdateThresholdState(POINT{ GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) });
            g_press.buttonDown = false;
        }

        if (message == WM_NCDESTROY)
        {
            RemoveWindowSubclass(hwnd, ViewportSubclassProc, kViewportSubclassId);
            if (g_hookedViewport == hwnd)
            {
                g_hookedViewport = nullptr;
            }
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    bool RemovePressHook()
    {
        if (g_hookedViewport == nullptr)
        {
            ResetPressCapture();
            return true;
        }

        const HWND hwnd = g_hookedViewport;
        g_hookedViewport = nullptr;
        const BOOL removed = IsWindow(hwnd)
            ? RemoveWindowSubclass(hwnd, ViewportSubclassProc, kViewportSubclassId)
            : TRUE;
        ResetPressCapture();
        AppendCallbackLog(removed ? "inputHook.removed=true\r\n" : "inputHook.removed=false\r\n");
        return removed != FALSE;
    }

    bool InstallPressHook()
    {
        RemovePressHook();
        ViewExp& viewport = GetCOREInterface()->GetActiveViewExp();
        HWND hwnd = viewport.GetHWnd();
        if (hwnd == nullptr || !IsWindow(hwnd))
        {
            return false;
        }

        using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
        const HMODULE user32 = GetModuleHandleW(L"user32.dll");
        const auto getDpiForWindowFn = user32 != nullptr
            ? reinterpret_cast<GetDpiForWindowFn>(GetProcAddress(user32, "GetDpiForWindow"))
            : nullptr;
        g_viewportDpi = getDpiForWindowFn != nullptr
            ? static_cast<int>(getDpiForWindowFn(hwnd))
            : 96;
        if (g_viewportDpi <= 0)
        {
            g_viewportDpi = 96;
        }
        g_dragThresholdX = MulDiv(kLogicalDragThreshold, g_viewportDpi, 96);
        g_dragThresholdY = MulDiv(kLogicalDragThreshold, g_viewportDpi, 96);
        if (g_dragThresholdX < 1) g_dragThresholdX = 1;
        if (g_dragThresholdY < 1) g_dragThresholdY = 1;

        const BOOL installed = SetWindowSubclass(hwnd, ViewportSubclassProc, kViewportSubclassId, 0);
        if (installed)
        {
            g_hookedViewport = hwnd;
        }
        return installed != FALSE;
    }

    std::wstring PressDebugText()
    {
        const LONG dx = g_press.current.x - g_press.start.x;
        const LONG dy = g_press.current.y - g_press.start.y;
        std::wstring text = L" captured=" + std::wstring(g_press.valid ? L"true" : L"false");
        text += L" crossed=" + std::wstring(g_press.crossedThreshold ? L"true" : L"false");
        text += L" moveHint=" + std::wstring(g_press.moveHintAtPress ? L"true" : L"false");
        text += L" delta=(" + std::to_wstring(dx) + L"," + std::to_wstring(dy) + L")";
        text += L" threshold=(" + std::to_wstring(g_dragThresholdX) + L"," + std::to_wstring(g_dragThresholdY) + L")";
        return text;
    }

    void CALLBACK StopTrackTimerProc(HWND hwnd, UINT, UINT_PTR timerId, DWORD)
    {
        KillTimer(hwnd, timerId);
        if (timerId != g_watchdogTimerId.load()) return;
        g_watchdogTimerId.store(0);
        g_stopScheduled.store(false);
        if (g_stopGeneration != g_sessionGeneration || g_stopCommand == nullptr ||
            GetCOREInterface()->GetCommandMode() != g_stopCommand)
        {
            AppendCallbackLog("exit.cleanup.skipped=command-or-session-changed\r\n");
            return;
        }
        const BOOL executed = ExecuteMAXScriptScript(
            _T("try(PBEndTrack())catch()"),
            MAXScript::ScriptSource::NonEmbedded,
            TRUE);
        RemovePressHook();
        AppendCallbackLog(executed ? "watchdog.cleanup.executed=true\r\n" : "watchdog.cleanup.executed=false\r\n");
    }

    const char* ResultKind(Value* value)
    {
        if (value == &true_value)
        {
            return "true";
        }
        if (value == &false_value)
        {
            return "false";
        }
        if (value == &ok)
        {
            return "ok";
        }
        if (value == &undefined)
        {
            return "undefined";
        }
        return value != nullptr ? "other" : "null";
    }

    void CancelTrackStopTimer()
    {
        const UINT_PTR timerId = g_watchdogTimerId.exchange(0);
        if (timerId != 0)
        {
            KillTimer(nullptr, timerId);
        }
        g_stopScheduled.store(false);
    }

    void ScheduleTrackStop(UINT delayMs, bool replaceExisting, CommandMode* ownedCommand,
        unsigned long long generation)
    {
        if (generation != g_sessionGeneration || ownedCommand == nullptr ||
            GetCOREInterface()->GetCommandMode() != ownedCommand) return;
        if (replaceExisting)
        {
            CancelTrackStopTimer();
        }

        if (!g_stopScheduled.exchange(true))
        {
            // Defer cleanup until the viewport callback has unwound so Max is
            // never re-entered from inside its own mouse dispatch.
            const UINT_PTR timerId = SetTimer(nullptr, 0, delayMs, StopTrackTimerProc);
            g_watchdogTimerId.store(timerId);
            g_stopGeneration = generation;
            g_stopCommand = ownedCommand;
            if (timerId == 0) g_stopScheduled.store(false);
            if (delayMs <= 1)
            {
                AppendCallbackLog(timerId != 0 ? "exit.cleanup.scheduled=true\r\n" : "exit.cleanup.scheduled=false\r\n");
            }
            else
            {
                AppendCallbackLog(timerId != 0 ? "watchdog.60s.scheduled=true\r\n" : "watchdog.60s.scheduled=false\r\n");
            }
        }
    }

    bool OwnsSessionCommand()
    {
        return g_sessionWatching && !g_sessionCommandLost && g_sessionCommand != nullptr &&
            GetCOREInterface()->GetCommandMode() == g_sessionCommand;
    }

    bool SettingsTabOwnsFocus()
    {
        // Exact native input-window focus excludes spinners, the Listener,
        // modifier controls, dialogs and other applications.
        return OwnsSessionCommand() && IsWindow(g_hookedViewport) &&
            GetFocus() == g_hookedViewport &&
            GetCOREInterface()->GetActiveViewExp().GetHWnd() == g_hookedViewport &&
            GetAncestor(GetForegroundWindow(), GA_ROOTOWNER) ==
                GetAncestor(g_hookedViewport, GA_ROOTOWNER);
    }

    bool SettingsTabBusy()
    {
        return g_press.buttonDown || g_activeGesture != GestureRoute::None ||
            g_relaxStrokeActive || theHold.Holding() || theHold.IsSuspended() ||
            theHold.RestoreOrRedoing() || (GetKeyState(VK_LBUTTON) & 0x8000) != 0;
    }

    void CALLBACK SessionTimerProc(HWND hwnd, UINT, UINT_PTR timerId, DWORD)
    {
        KillTimer(hwnd, timerId);
        if (timerId != g_sessionTimerId || !g_sessionWatching) return;
        g_sessionTimerId = 0;
        int flags = g_sessionPendingFlags;
        g_sessionPendingFlags = 0;
        HWND settingsFocus = nullptr;
        if ((flags & kSettingsTabRequest) != 0)
        {
            // Context/history changes win over a queued UI request. Recheck
            // focus and mouse/Undo state after returning to Max's message loop.
            if (g_settingsTabPendingToggle && flags == kSettingsTabRequest && SettingsTabOwnsFocus() && !SettingsTabBusy())
                settingsFocus = g_hookedViewport;
            else
                flags &= ~kSettingsTabRequest;
        }
        g_settingsTabPendingToggle = false;
        if (flags == 0) return;
        const auto generation = g_sessionGeneration;
        // The MAXScript handler rechecks this token before touching its state.
        // Dispatch after host notifications unwind, not from ModeChanged().
        const std::wstring script = L"if MayaQuadDrawR6 != undefined do MayaQuadDrawR6.onHostDeferred " +
            std::to_wstring(g_sessionGeneration) + L" " + std::to_wstring(flags) +
            (OwnsSessionCommand() ? L" true" : L" false");
        const BOOL executed = ExecuteMAXScriptScript(script.c_str(), MAXScript::ScriptSource::NonEmbedded, TRUE);
        if (!executed) AppendCallbackLog("session.deferred.exception=true\r\n");
        if (settingsFocus != nullptr && executed && generation == g_sessionGeneration &&
            OwnsSessionCommand() && IsWindow(settingsFocus) &&
            GetAncestor(GetForegroundWindow(), GA_ROOTOWNER) == GetAncestor(settingsFocus, GA_ROOTOWNER))
        {
            // Opening the floater is UI-only. Keep the originating viewport
            // focused so the next Tab can close it without a modeling click.
            SetFocus(settingsFocus);
        }
    }

    bool RequestSessionCheck(int flags)
    {
        if (!g_sessionWatching) return false;
        g_sessionPendingFlags |= flags;
        if (g_sessionTimerId == 0) g_sessionTimerId = SetTimer(nullptr, 0, 1, SessionTimerProc);
        return g_sessionTimerId != 0;
    }

    LRESULT CALLBACK SettingsTabMessageProc(int code, WPARAM removeFlag, LPARAM messagePtr)
    {
        if (code == HC_ACTION && removeFlag == PM_REMOVE && messagePtr != 0)
        {
            auto* message = reinterpret_cast<MSG*>(messagePtr);
            if ((message->message == WM_KEYDOWN || message->message == WM_KEYUP) && message->wParam == VK_TAB)
            {
                const bool inScope = SettingsTabOwnsFocus() && message->hwnd == g_hookedViewport;
                const bool bareTab = ((GetKeyState(VK_SHIFT) | GetKeyState(VK_CONTROL) | GetKeyState(VK_MENU)) & 0x8000) == 0;
                const auto action = g_settingsTabKey.process(
                    message->message == WM_KEYDOWN, message->message == WM_KEYUP,
                    (message->lParam & (static_cast<LPARAM>(1) << 30)) != 0,
                    inScope, bareTab, inScope && SettingsTabBusy());
                if (action == mqd::SettingsTabAction::Toggle)
                {
                    const bool queued = RequestSessionCheck(kSettingsTabRequest);
                    if (queued) g_settingsTabPendingToggle = !g_settingsTabPendingToggle;
                    AppendCallbackLog(queued
                        ? "settings.tab.queued=true\r\n" : "settings.tab.queued=false\r\n");
                }
                if (action != mqd::SettingsTabAction::Pass)
                {
                    // Consume before accelerators/Qt focus traversal, without
                    // executing MAXScript or creating windows inside the hook.
                    message->message = WM_NULL;
                    message->wParam = 0;
                    message->lParam = 0;
                }
            }
        }
        return CallNextHookEx(g_settingsTabHook, code, removeFlag, messagePtr);
    }

    void RemoveSettingsTabHook()
    {
        if (g_settingsTabHook != nullptr) UnhookWindowsHookEx(g_settingsTabHook);
        g_settingsTabHook = nullptr;
        g_settingsTabKey.reset();
        g_settingsTabPendingToggle = false;
    }

    void InstallSettingsTabHook()
    {
        RemoveSettingsTabHook();
        const DWORD viewportThread = GetWindowThreadProcessId(g_hookedViewport, nullptr);
        if (viewportThread != 0 && viewportThread == GetCurrentThreadId())
            g_settingsTabHook = SetWindowsHookExW(WH_GETMESSAGE, SettingsTabMessageProc, nullptr, viewportThread);
        AppendCallbackLog(g_settingsTabHook != nullptr
            ? "settings.tab.hook=true\r\n" : "settings.tab.hook=false\r\n");
    }

    class SessionCommandObserver final : public CommandModeChangedCallback
    {
    public:
        void ModeChanged(CommandMode*, CommandMode* newMode) override
        {
            if (g_sessionWatching && newMode != g_sessionCommand)
            {
                g_sessionCommandLost = true;
                RequestSessionCheck(2);
            }
        }
    };
    SessionCommandObserver g_sessionCommandObserver;

    void EndSessionWatch()
    {
        RemoveSettingsTabHook();
        if (g_sessionWatching)
            GetCOREInterface()->UnRegisterCommandModeChangedCallback(&g_sessionCommandObserver);
        g_sessionWatching = false;
        g_sessionCommand = nullptr;
        g_sessionCommandLost = false;
        if (g_sessionTimerId != 0) KillTimer(nullptr, g_sessionTimerId);
        g_sessionTimerId = 0;
        g_sessionPendingFlags = 0;
        CancelTrackStopTimer();
    }

    Value* DelegateForRoute(GestureRoute route)
    {
        switch (route)
        {
            case GestureRoute::Build: return g_buildDelegate.get_value();
            case GestureRoute::Move: return g_moveDelegate.get_value();
            case GestureRoute::Border: return g_borderDelegate.get_value();
            case GestureRoute::Optimizer: return g_optimizerDelegate.get_value();
            default: return nullptr;
        }
    }

    const wchar_t* RouteName(GestureRoute route)
    {
        switch (route)
        {
            case GestureRoute::Build: return L"build";
            case GestureRoute::Move: return L"move";
            case GestureRoute::Border: return L"border";
            case GestureRoute::Optimizer: return L"optimizer";
            default: return L"none";
        }
    }

    Value* ApplyRoute(GestureRoute route, Value** argList, int count)
    {
        Value* delegate = DelegateForRoute(route);
        if (delegate == nullptr || !is_function(delegate))
        {
            AppendCallbackLog("route.delegate.ready=false\r\n");
            return &false_value;
        }

        try
        {
            return delegate->apply(argList, count);
        }
        catch (MAXScriptException&)
        {
            AppendCallbackLog("route.delegate.exception=maxscript\r\n");
        }
        catch (...)
        {
            AppendCallbackLog("route.delegate.exception=unknown\r\n");
        }
        return &false_value;
    }
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        MaxSDK::Util::UseLanguagePackLocale();
        g_module = module;
        DisableThreadLibraryCalls(g_module);
    }
    return TRUE;
}

__declspec(dllexport) void LibInit()
{
}

__declspec(dllexport) const TCHAR* LibDescription()
{
    return MQD_NATIVE_BRIDGE_DESCRIPTION;
}

__declspec(dllexport) ULONG LibVersion()
{
    return VERSION_3DSMAX;
}

// loadDllsFromDir routes through Max's generic plug-in loader.  Even though
// this DLX only adds MAXScript primitives and owns no ClassDesc instances, the
// loader still requires the two standard class-enumeration exports.
__declspec(dllexport) int LibNumberClasses()
{
    return 1;
}

__declspec(dllexport) ClassDesc* LibClassDesc(int index)
{
    return index == 0 ? &g_bridgeGupClassDesc : nullptr;
}

#include <maxscript/macros/define_instantiation_functions.h>

def_visible_primitive(MQDNativeV15BridgeVersion, "MQDNativeV15BridgeVersion");
def_visible_primitive(MQDNativeV15SetDelegates, "MQDNativeV15SetDelegates");
def_visible_primitive(MQDNativeV15TrackPrimitive, "MQDNativeV15TrackPrimitive");
def_visible_primitive(MQDNativeV15TrackCount, "MQDNativeV15TrackCount");
def_visible_primitive(MQDNativeV15TrackReset, "MQDNativeV15TrackReset");
def_visible_primitive(MQDNativeV15InputHookRemove, "MQDNativeV15InputHookRemove");
def_visible_primitive(MQDNativeV15SetMoveHint, "MQDNativeV15SetMoveHint");
def_visible_primitive(MQDNativeV15RelaxBegin, "MQDNativeV15RelaxBegin");
def_visible_primitive(MQDNativeV15RelaxStep, "MQDNativeV15RelaxStep");
def_visible_primitive(MQDNativeV15RelaxEnd, "MQDNativeV15RelaxEnd");
def_visible_primitive(MQDNativeV15RelaxCancel, "MQDNativeV15RelaxCancel");
def_visible_primitive(MQDNativeV15ShiftDown, "MQDNativeV15ShiftDown");
def_visible_primitive(MQDNativeV16SessionBegin, "MQDNativeV16SessionBegin");
def_visible_primitive(MQDNativeV16SessionRequest, "MQDNativeV16SessionRequest");
def_visible_primitive(MQDNativeV16SessionEnd, "MQDNativeV16SessionEnd");
def_visible_primitive(MQDNativeV16SessionOwnsCommand, "MQDNativeV16SessionOwnsCommand");
def_visible_primitive(MQDNativeV16SessionResetInput, "MQDNativeV16SessionResetInput");
def_visible_primitive(MQDNativeV16SettingsTabHookActive, "MQDNativeV16SettingsTabHookActive");

Value* MQDNativeV16SessionBegin_cf(Value**, int count)
{
    check_arg_count(MQDNativeV16SessionBegin, 0, count);
    EndSessionWatch();
    ++g_sessionGeneration;
    g_sessionCommand = GetCOREInterface()->GetCommandMode();
    if (g_sessionCommand == nullptr) return Integer64::intern(0);
    g_sessionWatching = true;
    GetCOREInterface()->RegisterCommandModeChangedCallback(&g_sessionCommandObserver);
    InstallSettingsTabHook();
    return Integer64::intern(g_sessionGeneration);
}

Value* MQDNativeV16SettingsTabHookActive_cf(Value**, int count)
{
    check_arg_count(MQDNativeV16SettingsTabHookActive, 0, count);
    return g_settingsTabHook != nullptr && OwnsSessionCommand() ? &true_value : &false_value;
}

Value* MQDNativeV16SessionRequest_cf(Value** args, int count)
{
    check_arg_count(MQDNativeV16SessionRequest, 2, count);
    return static_cast<unsigned long long>(args[0]->to_int64()) == g_sessionGeneration &&
        RequestSessionCheck(args[1]->to_int()) ? &true_value : &false_value;
}

Value* MQDNativeV16SessionEnd_cf(Value** args, int count)
{
    check_arg_count(MQDNativeV16SessionEnd, 1, count);
    if (static_cast<unsigned long long>(args[0]->to_int64()) != g_sessionGeneration) return &false_value;
    EndSessionWatch();
    return &true_value;
}

Value* MQDNativeV16SessionOwnsCommand_cf(Value** args, int count)
{
    check_arg_count(MQDNativeV16SessionOwnsCommand, 1, count);
    return static_cast<unsigned long long>(args[0]->to_int64()) == g_sessionGeneration &&
        OwnsSessionCommand() ? &true_value : &false_value;
}

Value* MQDNativeV16SessionResetInput_cf(Value** args, int count)
{
    check_arg_count(MQDNativeV16SessionResetInput, 1, count);
    if (static_cast<unsigned long long>(args[0]->to_int64()) != g_sessionGeneration ||
        !OwnsSessionCommand()) return &false_value;
    g_activeGesture = GestureRoute::None;
    g_hoverMoveHint = false;
    ResetPressCapture();
    return &true_value;
}

Value* MQDNativeV15BridgeVersion_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15BridgeVersion, 0, count);
    return new String(MQD_NATIVE_BRIDGE_VERSION_STRING);
}

Value* MQDNativeV15SetDelegates_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV15SetDelegates, 4, count);
    for (int index = 0; index < count; ++index)
    {
        if (argList[index] == nullptr || !is_function(argList[index]))
        {
            return &false_value;
        }
    }

    g_buildDelegate.set_value(argList[0]);
    g_moveDelegate.set_value(argList[1]);
    g_borderDelegate.set_value(argList[2]);
    g_optimizerDelegate.set_value(argList[3]);
    return &true_value;
}

Value* MQDNativeV15TrackPrimitive_cf(Value** argList, int count)
{
    // A queued abort owns only the command that received it.
    if (g_stopScheduled.load()) return &false_value;
    CommandMode* dispatchCommand = GetCOREInterface()->GetCommandMode();
    const auto dispatchGeneration = g_sessionGeneration;
    const long long callbackCount = ++g_trackCallbackCount;
    if (callbackCount == 1)
    {
        WriteCallbackLog(callbackCount, count);
        AppendCallbackLog("dispatcher.ready=true\r\n");
        std::wstring hookLine = L"inputHook.ready=" + std::wstring(g_hookedViewport != nullptr ? L"true" : L"false");
        hookLine += L" dpi=" + std::to_wstring(g_viewportDpi);
        hookLine += L" logicalThreshold=" + std::to_wstring(kLogicalDragThreshold);
        hookLine += L" physicalThreshold=(" + std::to_wstring(g_dragThresholdX) + L"," + std::to_wstring(g_dragThresholdY) + L")\r\n";
        AppendCallbackLog(hookLine);
    }

    if (count < 4)
    {
        AppendCallbackLog("dispatcher.argCount.invalid=true\r\n");
        return &false_value;
    }

    Value* event = argList[0];
    const bool shiftDown = argList[1] == &true_value;
    GestureRoute route = GestureRoute::Build;
    bool clearGestureAfterDispatch = false;
    bool exiting = false;
    bool pendingMove = false;

    if (event == n_freeMove)
    {
        route = shiftDown ? GestureRoute::Border : GestureRoute::Move;
    }
    else if (event == n_mouseMove)
    {
        const bool immediateComponentMove =
            g_press.valid &&
            g_press.moveHintAtPress &&
            !g_press.shiftAtPress &&
            !g_press.ctrlAtPress &&
            !g_press.altAtPress;
        if (immediateComponentMove)
        {
            g_activeGesture = GestureRoute::Move;
            route = GestureRoute::Move;
        }
        else if (g_press.valid && !g_press.crossedThreshold)
        {
            route = GestureRoute::Build;
            pendingMove = true;
        }
        else
        {
            if (g_activeGesture == GestureRoute::None)
            {
                const bool routeAsBorder = g_press.valid ? g_press.shiftAtPress : shiftDown;
                g_activeGesture = routeAsBorder ? GestureRoute::Border : GestureRoute::Move;
            }
            route = g_activeGesture;
        }
    }
    else if (event == n_mousePoint)
    {
        route = g_activeGesture == GestureRoute::None ? GestureRoute::Build : g_activeGesture;
        clearGestureAfterDispatch = true;
    }
    else if (event == n_mouseAbort)
    {
        route = g_activeGesture == GestureRoute::None ? GestureRoute::Build : g_activeGesture;
        clearGestureAfterDispatch = true;
        exiting = true;
    }

    Value* routedArgs[4]{ argList[0], argList[1], argList[2], argList[3] };
    if (route == GestureRoute::Border && g_activeGesture == GestureRoute::Border)
    {
        routedArgs[1] = &true_value;
    }
    else if (route == GestureRoute::Move && g_activeGesture == GestureRoute::Move)
    {
        routedArgs[1] = &false_value;
    }
    Value* result = ApplyRoute(route, routedArgs, count);

    if (event != n_freeMove)
    {
        std::wstring line = L"event=" + ValueRepresentation(event);
        line += L" route=" + std::wstring(RouteName(route));
        line += shiftDown ? L" shift=true" : L" shift=false";
        if (pendingMove) line += L" pending=true";
        line += PressDebugText();
        line += L" result=" + ValueRepresentation(result) + L"\r\n";
        AppendCallbackLog(line);
    }

    if (clearGestureAfterDispatch)
    {
        g_activeGesture = GestureRoute::None;
        ResetPressCapture();
    }

    if (exiting)
    {
        ScheduleTrackStop(1, true, dispatchCommand, dispatchGeneration);
    }
    return result != nullptr ? result : &false_value;
}

Value* MQDNativeV15TrackCount_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15TrackCount, 0, count);
    return Integer64::intern(g_trackCallbackCount.load());
}

Value* MQDNativeV15TrackReset_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15TrackReset, 0, count);
    EndSessionWatch();
    ++g_sessionGeneration;
    g_trackCallbackCount.store(0);
    g_activeGesture = GestureRoute::None;
    g_hoverMoveHint = false;
    ResetPressCapture();
    return InstallPressHook() ? &true_value : &false_value;
}

Value* MQDNativeV15InputHookRemove_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15InputHookRemove, 0, count);
    g_hoverMoveHint = false;
    return RemovePressHook() ? &true_value : &false_value;
}

Value* MQDNativeV15SetMoveHint_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV15SetMoveHint, 1, count);
    g_hoverMoveHint = argList[0] == &true_value;
    return &true_value;
}

Value* MQDNativeV15RelaxBegin_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV15RelaxBegin, 1, count);
    if (g_relaxStrokeActive)
    {
        return &true_value;
    }
    INode* ownerNode = argList[0]->to_node();
    if (EPolyFromNode(ownerNode) == nullptr)
    {
        return &false_value;
    }
    g_relaxOwnsHold = theHold.Holding() == 0;
    if (g_relaxOwnsHold)
    {
        theHold.Begin();
    }
    if (theHold.Holding())
    {
        theHold.Put(new RelaxStrokeRestore(ownerNode));
    }
    g_relaxStrokeActive = true;
    return &true_value;
}

Value* MQDNativeV15RelaxStep_cf(Value** argList, int count)
{
    check_arg_count(MQDNativeV15RelaxStep, 9, count);
    INode* ownerNode = argList[0]->to_node();
    INode* targetNode = argList[1]->to_node();
    const int seedFace = argList[2]->to_int() - 1;
    const float screenX = argList[3]->to_float();
    const float screenY = argList[4]->to_float();
    const float radius = argList[5]->to_float();
    const float focus = argList[6]->to_float();
    const float strength = argList[7]->to_float();
    const float offset = argList[8]->to_float();
    return ApplyRelaxStep(ownerNode, targetNode, seedFace, screenX, screenY, radius, focus, strength, offset)
        ? &true_value
        : &false_value;
}

Value* MQDNativeV15RelaxEnd_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15RelaxEnd, 0, count);
    if (!g_relaxStrokeActive)
    {
        return &false_value;
    }
    if (g_relaxOwnsHold && theHold.Holding())
    {
        theHold.Accept(_T("Maya Quad Draw Relax"));
    }
    g_relaxStrokeActive = false;
    g_relaxOwnsHold = false;
    return &true_value;
}

Value* MQDNativeV15RelaxCancel_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15RelaxCancel, 0, count);
    if (g_relaxStrokeActive && g_relaxOwnsHold && theHold.Holding())
    {
        theHold.Cancel();
    }
    g_relaxStrokeActive = false;
    g_relaxOwnsHold = false;
    return &true_value;
}

Value* MQDNativeV15ShiftDown_cf(Value**, int count)
{
    check_arg_count(MQDNativeV15ShiftDown, 0, count);
    return (GetKeyState(VK_SHIFT) & 0x8000) != 0 ? &true_value : &false_value;
}

