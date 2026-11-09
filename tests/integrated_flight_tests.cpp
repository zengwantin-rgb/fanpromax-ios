#include "FlightLease.hpp"
#include <cassert>
#include <cstdio>
using namespace fanpro;
struct Fixture {
    Identity key{0x1000,0x2000,0x3000,1};bool gravity{true};Velocity v{120,-30,50};unsigned calls{};bool refuse{};
    PhysicsAccess io(){return{this,[](void *c,const Identity &k){return static_cast<Fixture *>(c)->key==k;},
        [](void *c,const Identity &,bool &v){v=static_cast<Fixture *>(c)->gravity;return true;},
        [](void *c,const Identity &,bool v){auto &f=*static_cast<Fixture *>(c);++f.calls;if(f.refuse)return false;f.gravity=v;return true;},
        [](void *c,const Identity &,Velocity &v){v=static_cast<Fixture *>(c)->v;return true;},
        [](void *c,const Identity &,Velocity v){auto &f=*static_cast<Fixture *>(c);++f.calls;f.v=v;return true;}};}
};
int main(){
    Fixture f;auto io=f.io();FlightLease lease;
    assert(lease.apply(io,f.key,1)==FieldResult::applied && !f.gravity && f.v.x==120 && f.v.y==-30 && f.v.z==300);
    assert(lease.apply(io,f.key,0)==FieldResult::applied && f.v.z==0);
    assert(lease.apply(io,f.key,-1)==FieldResult::applied && f.v.z==-300);
    assert(lease.restore(io)==FieldResult::off && f.gravity && f.v.z==-300);
    assert(lease.apply(io,f.key,0)==FieldResult::applied);++f.key.serial;unsigned n=f.calls;
    assert(lease.restore(io)==FieldResult::stale && f.calls==n);
    f.gravity=true;f.refuse=true;assert(lease.apply(io,f.key,0)==FieldResult::writeFailed && !lease.active());
    f.refuse=false;assert(lease.apply(io,f.key,0)==FieldResult::applied);f.gravity=true;n=f.calls;
    assert(lease.restore(io)==FieldResult::conflict && f.calls==n);
    puts("PASS: vertical flight preserves horizontal velocity, neutral hovers, gravity restores without restoring stale velocity, recycled objects and game-side changes are preserved");
}
