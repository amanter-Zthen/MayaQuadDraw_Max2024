#pragma once
#include "VisibilityDepthMath.h"
#include <vector>

// Shift candidate policy recovered from Max 2024 PolyTools.gup 180067540.
// A facing face adjacent to an open edge seeds its vertices; loose vertices
// are independent. Eligibility is distinct from target occlusion and from the
// obstacle geometry that still participates in intersection checks.
namespace mqd_stepbuild
{
    using mqd_visibility::Vec3;
    inline bool FacingBoundaryFace(const Vec3& faceNormal, const Vec3& objectViewZ)
    {
        const double dot = mqd_visibility::Dot(faceNormal, objectViewZ);
        return std::isfinite(dot) && dot >= 0.0;
    }

    inline bool SharesThreeFaceVertices(const std::vector<int>& candidate, const int* face, int degree)
    {
        int common = 0;
        for (int id : candidate)
        {
            if (std::find(face, face + degree, id) != face + degree && ++common >= 3) return true;
        }
        return false;
    }

    class CandidateMask
    {
        struct State
        {
            bool hasFace = false;
            bool hasEdge = false;
            bool hasOpenEdge = false;
            bool facingFaceSeed = false;
        };
        std::vector<State> vertices;
        bool Valid(int id) const { return id >= 0 && static_cast<size_t>(id) < vertices.size(); }
    public:
        explicit CandidateMask(int count) : vertices(static_cast<size_t>(count)) {}
        void MarkFaceVertex(int id)
        {
            if (Valid(id)) vertices[static_cast<size_t>(id)].hasFace = true;
        }
        void MarkEdgeVertex(int id, bool open)
        {
            if (!Valid(id)) return;
            State& s = vertices[static_cast<size_t>(id)];
            s.hasEdge = true;
            s.hasOpenEdge = s.hasOpenEdge || open;
        }
        void SeedFacingFaceVertex(int id)
        {
            if (Valid(id)) vertices[static_cast<size_t>(id)].facingFaceSeed = true;
        }
        bool SourceEligible(int id, bool dead, bool hidden) const
        {
            if (!Valid(id) || dead || hidden) return false;
            const State& s = vertices[static_cast<size_t>(id)];
            return !s.hasFace || s.facingFaceSeed;
        }
        bool Eligible(int id, bool dead, bool hidden) const
        {
            if (!SourceEligible(id, dead, hidden)) return false;
            const State& s = vertices[static_cast<size_t>(id)];
            return !s.hasEdge || s.hasOpenEdge;
        }
    };
}
