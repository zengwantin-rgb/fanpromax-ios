#pragma once
#include "PortCore.hpp"
#include <cmath>
#include <cstring>

namespace nsport::aim {
struct VehicleBounds {Vec3 origin,extent;float radius{};};
static_assert(sizeof(VehicleBounds)==28);
// Read the association used by 0x22d23e4 -> 0x3189170 -> 0x4ede944.
// This is an exclusion, not a replacement for the game's interface/type checks.
inline bool attachedVehicle(const Memory &m,uint64_t pawn,uint64_t &out) {
    out=0;uint64_t rider{},owner{},root{},parent{};
    if(!m.get(pawn+0x1a88,rider)) return false;
    if(!rider) return true;
    if(!m.get(rider+0xa0,owner) || !owner || !m.get(owner+0x278,root)) return false;
    if(!root) return true;
    if(!m.get(root+0x230,parent)) return false;
    if(parent && !m.get(parent+0xa0,out)) return false;
    return m.pointer(pawn+0x1a88)==rider && m.pointer(rider+0xa0)==owner &&
        m.pointer(owner+0x278)==root && m.pointer(root+0x230)==parent;
}
inline bool vehiclePoint(const Memory &m,uint64_t object,uint64_t world,Vec3 &out,VehicleBounds *body=nullptr,float *centerOffsetZ=nullptr) {
    if(!object || !world) return false;
    const auto cl=m.encodedPointer(object+0x30);bool vehicle=false;
    for(uint64_t slot:{0x7f8b4a0ULL,0x7f33a70ULL,0x7f33b00ULL,0x7f195c8ULL})
        if(isA(m,cl,m.pointer(m.base+slot))) {vehicle=true;break;}
    if(!vehicle) return false;
    uint64_t outer=m.encodedPointer(object+8);bool sameWorld=false;
    for(unsigned depth=0;outer && depth<8;++depth) {
        if(isA(m,m.encodedPointer(outer+0x30),m.pointer(m.base+0x80a1620))) {
            sameWorld=m.pointer(outer+0x178)==world;break;
        }
        const auto next=m.encodedPointer(outer+8);if(next==outer) break;outer=next;
    }
    const auto root=m.pointer(object+0x278);
    if(!sameWorld || !root) return false;
    const auto rootClass=m.encodedPointer(root+0x30);uint8_t registered{};
    if(!isA(m,rootClass,m.pointer(m.base+0x80b05a8)) || !m.get(root+0x84,registered) || !(registered&1)) return false;
    // Original GetComponentBounds (0x52d3a64) copies this world-space box/sphere,
    // independently of ComponentToWorld's translation at +0x150 (the chassis pivot).
    VehicleBounds bounds{},after{};Vec3 pivot{};
    if(!m.get(root+0x104,bounds) || !m.get(root+0x150,pivot)) return false;
    const auto finite=[](Vec3 v){return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);};
    if(!finite(bounds.origin) || !finite(bounds.extent) || !finite(pivot) || !std::isfinite(bounds.radius) ||
        std::abs(bounds.origin.x)>=1e8 || std::abs(bounds.origin.y)>=1e8 || std::abs(bounds.origin.z)>=1e8 ||
        bounds.extent.x<=.5f || bounds.extent.y<=.5f || bounds.extent.z<=.5f ||
        bounds.extent.x>5000 || bounds.extent.y>5000 || bounds.extent.z>5000 ||
        bounds.radius<=.5f || bounds.radius>10000 || distance(bounds.origin,pivot)>5000) return false;
    if(!m.get(root+0x104,after) || std::memcmp(&bounds,&after,sizeof bounds) ||
        m.pointer(object+0x278)!=root || m.encodedPointer(object+0x30)!=cl || m.encodedPointer(root+0x30)!=rootClass ||
        !m.get(root+0x84,registered) || !(registered&1)) return false;
    out=bounds.origin;if(body) *body=bounds;if(centerOffsetZ) *centerOffsetZ=bounds.origin.z-pivot.z;return true;
}
}
