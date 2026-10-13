#include "StepBuildCandidateRules.h"
#include <iostream>
#include <limits>
#include <stdexcept>

using namespace mqd_stepbuild;
static int passed = 0;
static void require(bool condition, const char* label)
{
    if (!condition) throw std::runtime_error(label);
    ++passed;
}
int main()
{
    try
    {
        const Vec3 viewZ{0,0,1};
        require(FacingBoundaryFace({0,0,1}, viewZ), "front boundary face passes");
        require(!FacingBoundaryFace({0,0,-1}, viewZ), "back boundary face rejected");
        require(FacingBoundaryFace({1,0,0}, viewZ), "native grazing equality retained");
        require(FacingBoundaryFace({0,0,0}, viewZ), "zero face normal follows native sign gate; geometry checked separately");
        require(!FacingBoundaryFace({0,0,std::numeric_limits<double>::quiet_NaN()}, viewZ), "nonfinite normal fails closed");
        require(FacingBoundaryFace({1,2,3}, {2,4,6}), "positive scaling preserves sign");
        require(!FacingBoundaryFace({1,2,3}, {-2,-4,-6}), "reversed view reverses eligibility");
        // Exhaustive topology/state combinations exercise the production mask.
        // edge=0: no edges, edge=1: internal/wire edge only, edge=2: open edge.
        for (int face=0; face<2; ++face)
        for (int edge=0; edge<3; ++edge)
        for (int seed=0; seed<2; ++seed)
        for (int dead=0; dead<2; ++dead)
        for (int hidden=0; hidden<2; ++hidden)
        {
            CandidateMask mask(1);
            if (face) mask.MarkFaceVertex(0);
            if (edge) mask.MarkEdgeVertex(0, edge==2);
            if (seed) mask.SeedFacingFaceVertex(0);
            const bool expected = !dead && !hidden && (!face || seed) && (edge==0 || edge==2);
            require(mask.Eligible(0, dead!=0, hidden!=0)==expected, "native source-domain and boundary eligibility truth table");
            require(mask.SourceEligible(0,dead!=0,hidden!=0)==(!dead && !hidden && (!face || seed)), "source domain remains distinct from post-selection boundary eligibility");
        }
        CandidateMask folded(3);
        for (int v=0; v<3; ++v) { folded.MarkFaceVertex(v); folded.MarkEdgeVertex(v,true); }
        // A small front face and a large rear face share vertex 0. Max seeds
        // the front face vertices independently; averaging would erase this.
        require(!FacingBoundaryFace({0,0,-9},viewZ), "averaged fold would point backwards");
        if (FacingBoundaryFace({0,0,1},viewZ))
        {
            folded.SeedFacingFaceVertex(0);
            folded.SeedFacingFaceVertex(1);
        }
        require(folded.Eligible(0,false,false), "fold joint retains a front-face seed");
        require(folded.Eligible(1,false,false), "front-only endpoint retained");
        require(!folded.Eligible(2,false,false), "back-only endpoint excluded");
        // Internal vertices can be on a seeded face but may not create branches.
        CandidateMask internal(1);
        internal.MarkFaceVertex(0); internal.MarkEdgeVertex(0,false); internal.SeedFacingFaceVertex(0);
        require(!internal.Eligible(0,false,false), "seeded fully internal vertex still excluded");
        require(internal.SourceEligible(0,false,false), "internal seeded point participates in nearest four before veto");
        CandidateMask loose(1);
        require(loose.Eligible(0,false,false), "loose point does not need an invented normal");
        loose.MarkFaceVertex(-1); loose.MarkEdgeVertex(999,true); loose.SeedFacingFaceVertex(999);
        require(loose.Eligible(0,false,false), "invalid adjacency cannot corrupt a valid point");
        require(!loose.Eligible(-1,false,false) && !loose.Eligible(1,false,false), "invalid input ids rejected");
        CandidateMask empty(0);
        require(!empty.Eligible(0,false,false), "empty mesh safe");
        const int existing[] = {79,82,83,81};
        require(SharesThreeFaceVertices({79,82,83,77}, existing,4), "incident candidate reuses three vertices of earlier face");
        require(SharesThreeFaceVertices({77,83,82,79}, existing,4), "reversed incident cycle still rejected");
        require(!SharesThreeFaceVertices({82,83,90,91}, existing,4), "normal one-edge adjacent extension allowed");
        require(!SharesThreeFaceVertices({90,91,92,93}, existing,4), "new loose quad allowed by overlap guard");
        require(SharesThreeFaceVertices({79,82,83}, existing,4), "three common ids also rejected for triangle proposal");
        require(SharesThreeFaceVertices({79,82,83,81}, existing,4), "identical face rejected");
        require(!SharesThreeFaceVertices({79,82,90}, existing,4), "two common ids can participate in real triangle hole");
        require(!SharesThreeFaceVertices({79,90,91,92}, existing,4), "single shared vertex not misclassified as duplicate area");
        std::cout << "PASS " << passed << " Step Build candidate checks\n";
        return 0;
    }
    catch (const std::exception& e)
    {
        std::cerr << "FAIL after " << passed << " checks: " << e.what() << '\n';
        return 1;
    }
}
