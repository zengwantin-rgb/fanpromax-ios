#pragma once
#include "FieldLease.hpp"
#include <algorithm>
namespace fanpro {
struct FlightMotionReport {
    bool valid{},discontinuityCandidate{},requested{};int direction{};
    double seconds{},heightChangeMeters{},peakRiseMeters{},largestDropMeters{},largestNegativeResidualMeters{},minObservedMPS{},maxObservedMPS{};
    uint64_t samples{};
};
class FlightMotionWindow {
    Identity key{};bool active{},requested{};int direction{};
    double start{},last{},originZ{},lastZ{},previousNextVelocity{},peak{},drop{},residual{},minVelocity{},maxVelocity{};uint64_t samples{};
public:
    void reset(){active=false;}
    FlightMotionReport add(const Identity &id,bool wanted,int selected,double time,double z,double observedVelocity,double nextVelocity) {
        FlightMotionReport out;
        if(!std::isfinite(time) || !std::isfinite(z) || !std::isfinite(observedVelocity) || !std::isfinite(nextVelocity) ||
            std::abs(z)>1e8 || std::abs(observedVelocity)>30000 || std::abs(nextVelocity)>30000){reset();return out;}
        if(!active || !(key==id) || wanted!=requested || selected!=direction || time<=last || time-last>0.5) {
            key=id;requested=wanted;direction=selected;start=last=time;originZ=lastZ=peak=z;
            previousNextVelocity=nextVelocity;drop=residual=0;minVelocity=maxVelocity=observedVelocity;samples=1;active=true;return out;
        }
        double dt=time-last,dz=z-lastZ,error=dz-(previousNextVelocity+observedVelocity)*0.5*dt;
        peak=std::max(peak,z);drop=std::min(drop,dz);residual=std::min(residual,error);
        minVelocity=std::min(minVelocity,observedVelocity);maxVelocity=std::max(maxVelocity,observedVelocity);
        last=time;lastZ=z;previousNextVelocity=nextVelocity;++samples;
        // A candidate discontinuity can also come from local collision/constraints.
        // Emit it immediately so stopping/exporting cannot erase a short rollback.
        bool candidate=dz < -50 && error < -100;
        if(time-start<2.0 && !candidate)return out;
        out.valid=true;out.discontinuityCandidate=candidate;out.requested=requested;out.direction=direction;
        out.seconds=time-start;out.samples=samples;out.heightChangeMeters=(z-originZ)/100;out.peakRiseMeters=(peak-originZ)/100;
        out.largestDropMeters=-drop/100;out.largestNegativeResidualMeters=-residual/100;
        out.minObservedMPS=minVelocity/100;out.maxObservedMPS=maxVelocity/100;
        active=false;return out;
    }
};
}
