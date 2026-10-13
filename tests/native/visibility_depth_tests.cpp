#include "VisibilityDepthMath.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace mqd_visibility;
int passed = 0;
void require(bool value, const char* name)
{
    if (!value) throw std::runtime_error(name);
    ++passed;
}
bool visible(double depth, const std::vector<double>& hits, double epsilon)
{
    for (size_t i = 1; i < hits.size(); ++i)
        if (CloserToDeeperLayer(depth, hits.front(), hits[i], epsilon)) return false;
    return true;
}
double depthAtZ(Vec3 origin, Vec3 dir, double z)
{
    double t = 0;
    require(IntersectTriangle(origin, dir, {-30,-30,z}, {30,-30,z}, {0,30,z}, t), "ray hits test layer");
    return t;
}
int main()
{
    try
    {
        // Reproduces the old metric: even a small sideways pixel displacement
        // masks a 0.0005-unit separation behind the distance tolerance.
        const double gap = 0.0005, lateral = 0.25, tolerance = gap*0.1;
        const double oldFrontDistance = std::sqrt(lateral*lateral+gap*gap);
        const double oldBackDistance = lateral;
        require(!(oldBackDistance+tolerance < oldFrontDistance), "old Euclidean test wrongly accepts rear layer");
        require(CloserToDeeperLayer(gap, 0, gap, 0.01), "depth test rejects the same rear layer");

        for (double separation : {20.0, 0.0005, 0.00005})
        for (double eyeDepth : {100.0, 10000.0, 1000000.0})
        {
            const Vec3 origin{0,0,-eyeDepth};
            // A deliberately non-unit float direction catches parameter/dot
            // mismatches that only become large with far cameras.
            const Vec3 dir{0,0,static_cast<float>(0.99999994)};
            std::vector<double> hits;
            for (int i = 0; i < 3; ++i)
                hits.push_back(depthAtZ(origin, dir, static_cast<float>(i*separation)));
            for (int i = 0; i < 3; ++i)
            {
                const Vec3 point{0,0,static_cast<float>(i*separation)};
                require(visible(RayDepth(point, origin, dir), hits, 0.01) == (i == 0), "three layers remain distinct with near/far eye");
            }
        }
        for (double separation : {20.0, 0.0005})
        {
            const Vec3 origin{-10,-2,-100};
            const Vec3 direction{0.1f,0.02f,1.0f};
            std::vector<double> hits;
            for (int i = 0; i < 3; ++i) hits.push_back(depthAtZ(origin, direction, i*separation));
            for (int i = 0; i < 3; ++i)
            {
                const double d = i*separation;
                require(visible(RayDepth({0.1*d,0.02*d,d},origin,direction),hits,0.01) == (i == 0), "oblique thin layers remain distinct");
            }
        }
        double t = 0;
        require(!IntersectTriangle({0,0,-1},{1,0,0},{-1,-1,0},{1,-1,0},{0,1,0},t), "parallel ray rejected");
        require(!IntersectTriangle({0,0,1},{0,0,1},{-1,-1,0},{1,-1,0},{0,1,0},t), "behind-eye intersection rejected");
        require(IntersectTriangle({0,0,-1},{0,0,1},{-1,-1,0},{0,1,0},{1,-1,0},t), "reversed winding still double-sided");
        std::cout << "PASS " << passed << " numerical checks\n";
        return 0;
    }
    catch (const std::exception& e)
    {
        std::cerr << "FAIL after " << passed << " checks: " << e.what() << '\n';
        return 1;
    }
}
