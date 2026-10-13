#pragma once

#include <algorithm>
#include <cmath>

// Shared by the Max bridge and the standalone numerical regression test.
// Double arithmetic starts before subtraction, not after a float dot product.
namespace mqd_visibility
{
    struct Vec3
    {
        double x, y, z;
        Vec3 operator-(const Vec3& rhs) const { return {x-rhs.x, y-rhs.y, z-rhs.z}; }
    };
    inline double Dot(const Vec3& a, const Vec3& b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
    inline Vec3 Cross(const Vec3& a, const Vec3& b)
    {
        return {a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x};
    }
    inline double RayDepth(const Vec3& point, const Vec3& origin, const Vec3& direction)
    {
        // Float-normalized SDK vectors are not exactly unit length. Dividing
        // by length squared matches the ray parameter even for distant eyes.
        return Dot(point-origin, direction)/Dot(direction, direction);
    }
    inline bool IntersectTriangle(const Vec3& origin, const Vec3& direction,
        const Vec3& a, const Vec3& b, const Vec3& c, double& parameter)
    {
        const Vec3 edge1 = b-a, edge2 = c-a;
        const Vec3 p = Cross(direction, edge2);
        const double determinant = Dot(edge1, p);
        const double scale = std::sqrt(Dot(edge1, edge1)*Dot(edge2, edge2));
        if (!std::isfinite(scale) || scale == 0.0 || std::abs(determinant) <= scale*1.0e-12) return false;
        const double inverseDeterminant = 1.0/determinant;
        const Vec3 offset = origin-a;
        const double u = Dot(offset, p)*inverseDeterminant;
        if (u < -1.0e-9 || u > 1.0+1.0e-9) return false;
        const Vec3 q = Cross(offset, edge1);
        const double v = Dot(direction, q)*inverseDeterminant;
        if (v < -1.0e-9 || u+v > 1.0+1.0e-9) return false;
        parameter = Dot(edge2, q)*inverseDeterminant;
        return std::isfinite(parameter) && parameter > 1.0e-5;
    }
    inline bool CloserToDeeperLayer(double candidateDepth, double frontDepth,
        double deeperDepth, double surfaceEpsilon)
    {
        const double tolerance = std::min(surfaceEpsilon, std::abs(deeperDepth-frontDepth)*0.1);
        return std::abs(candidateDepth-deeperDepth)+tolerance < std::abs(candidateDepth-frontDepth);
    }
}
