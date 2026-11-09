#include "FieldLease.hpp"
#include <cassert>
#include <cstdio>
#include <limits>
using namespace fanpro;
struct Fixture {
    Identity key{0x1000,0x2000,0x3000,7};float value{600};unsigned writes{};bool readable{true},writable{true},readbackFails{};
    Access io(){return {this,[](void *c,const Identity &key){return static_cast<Fixture *>(c)->key==key;},
        [](void *c,uint64_t at,float &v){auto &f=*static_cast<Fixture *>(c);if(!f.readable || (f.readbackFails && f.writes) || at!=f.key.object+0x6dc)return false;v=f.value;return true;},
        [](void *c,uint64_t at,float v){auto &f=*static_cast<Fixture *>(c);if(!f.writable || at!=f.key.object+0x6dc)return false;++f.writes;f.value=v;return true;}};}
};
int main(){
    Fixture f;FieldLease lease;auto io=f.io();
    assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::applied && f.value==1200);
    for(int i=0;i<100;++i)assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::unchanged && f.value==1200);
    assert(f.writes==1);assert(lease.apply(io,f.key,0x6dc,3)==FieldResult::applied && f.value==1800);
    assert(lease.restore(io)==FieldResult::off && f.value==600);
    assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::applied);f.value=650;
    assert(lease.restore(io)==FieldResult::conflict && f.value==650);
    assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::applied);++f.key.serial;
    auto count=f.writes;assert(lease.restore(io)==FieldResult::stale && count==f.writes);
    assert(lease.apply(io,f.key,0x6dc,std::numeric_limits<float>::quiet_NaN())==FieldResult::invalid && count==f.writes);
    f.value=600;f.readbackFails=true;assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::readbackFailed && lease.active());
    f.readbackFails=false;assert(lease.restore(io)==FieldResult::off && f.value==600);
    f.writable=false;assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::writeFailed && f.value==600);
    f.writable=true;assert(lease.restore(io)==FieldResult::off);
    assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::applied);f.value=700;
    count=f.writes;assert(lease.apply(io,f.key,0x6dc,2)==FieldResult::conflict && f.writes==count && f.value==700);
    puts("PASS: no compounding, exact restoration, game-side changes preserved, recycled objects rejected, failed readback retains cleanup and failed writes reported");
}
