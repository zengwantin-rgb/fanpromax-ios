#include "MotionWindow.hpp"
#include <cassert>
#include <cstdio>
using namespace fanpro;
int main(){
    MotionWindow w;Identity key{1,2,3,4};MotionReport r;
    for(int i=0;i<=20;++i)r=w.add(key,10,i*.1,i*50,0);
    assert(r.valid && std::abs(r.netMPS-5)<1e-6 && std::abs(r.pathMPS-5)<1e-6);
    // A return to the starting point is not counted as net progress.
    for(int i=0;i<=20;++i)r=w.add(key,30,3+i*.1,(i<=10 ? i : 20-i)*50,0);
    assert(r.valid && r.netMPS==0 && r.pathMPS>0);
    w.add(key,10,6,0,0);assert(!w.add(key,30,7,1000,0).valid);
    ++key.serial;assert(!w.add(key,30,8,1500,0).valid);
    assert(!w.add(key,30,10,1600,0).valid); // Unobserved time starts a new window.
    puts("PASS: straight net speed, reversal separated from path length, multiplier/object changes and sampling gaps reset windows");
}
