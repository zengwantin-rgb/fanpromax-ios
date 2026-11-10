#include "FlightMotionWindow.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
using namespace fanpro;
int main(){
    Identity id{1,2,3,4};FlightMotionWindow w;FlightMotionReport r;
    for(int i=0;i<=20;++i)r=w.add(id,true,1,i*0.1,10000+i*30,300,300);
    assert(r.valid && !r.discontinuityCandidate && std::abs(r.heightChangeMeters-6)<0.001 && r.largestDropMeters==0);
    w.reset();w.add(id,true,1,0,10000,300,300);w.add(id,true,1,0.1,10030,300,300);
    r=w.add(id,true,1,0.2,9700,300,300);assert(r.valid && r.discontinuityCandidate && r.largestDropMeters>3 && r.seconds<2);
    w.reset();for(int i=0;i<=20;++i)r=w.add(id,true,-1,i*0.1,10000-i*30,-300,-300);
    assert(r.valid && !r.discontinuityCandidate && std::abs(r.heightChangeMeters+6)<0.001);
    w.reset();w.add(id,true,1,0,10000,300,300);++id.serial;
    assert(!w.add(id,true,1,0.1,9000,300,300).valid);
    assert(!w.add(id,true,1,1,8000,300,300).valid);
    assert(!w.add(id,false,0,1.1,7000,0,0).valid);
    assert(!w.add(id,false,0,1.2,NAN,0,0).valid);
    puts("PASS: ascent/descent, immediate discontinuity evidence, identity/request/gap resets; no server attribution");
}
