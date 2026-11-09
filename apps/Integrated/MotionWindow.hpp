#pragma once
#include "FieldLease.hpp"
namespace fanpro {
struct MotionReport {bool valid{};double seconds{},netMeters{},pathMeters{},netMPS{},pathMPS{};uint64_t samples{};unsigned tenths{};};
class MotionWindow {
    Identity key{};unsigned selected{};double start{},last{},originX{},originY{},lastX{},lastY{},path{};uint64_t samples{};bool active{};
public:
    void reset(){active=false;}
    MotionReport add(const Identity &id,unsigned tenths,double time,double x,double y) {
        MotionReport out;
        if(!std::isfinite(time) || !std::isfinite(x) || !std::isfinite(y) || std::abs(x)>1e8 || std::abs(y)>1e8){reset();return out;}
        if(!active || !(id==key) || tenths!=selected || time<=last || time-last>1.0){
            key=id;selected=tenths;start=last=time;originX=lastX=x;originY=lastY=y;path=0;samples=1;active=true;return out;
        }
        double step=std::hypot(x-lastX,y-lastY);
        if(step>30000){reset();return out;}
        path+=step;last=time;lastX=x;lastY=y;++samples;
        if(time-start<2.0)return out;
        out.valid=true;out.seconds=time-start;out.netMeters=std::hypot(x-originX,y-originY)/100;
        out.pathMeters=path/100;out.netMPS=out.netMeters/out.seconds;out.pathMPS=out.pathMeters/out.seconds;
        out.samples=samples;out.tenths=selected;
        active=false;return out;
    }
};
}
