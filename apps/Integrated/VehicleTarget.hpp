#pragma once
#include "LocalController.hpp"
#include "FieldLease.hpp"
namespace fanpro {
inline bool objectIdentity(const nsport::Memory &m,uint64_t object,uint64_t world,Identity &out) {
    struct Item {uint64_t reserved,object;uint32_t flags;int32_t serial;};
    std::array<uint32_t,3> words{};int32_t count{};
    if(!object || !m.get(object+0x20,words) || !m.get(m.base+0x8174538,count) || count<=0 || count>2000000)return false;
    uint32_t index=nsport::decodeSerial(words);if(index>=uint32_t(count))return false;
    uint64_t table=m.pointer(m.base+0x8174520),chunk=table ? m.pointer(table+uint64_t(index>>16)*8) : 0;
    if(!chunk)return false;
    uint64_t at=chunk+uint64_t(index&0xffff)*sizeof(Item);Item item{};
    if(!m.get(at,item) || item.object!=object || !item.serial || (item.flags&0x30000000))return false;
    out={object,at,world,item.serial};return true;
}
struct VehicleTarget {
    Identity body{};
    uint64_t vehicle{};
    bool ready{};
    const char *reason{"local_identity_unavailable"},*route{"none"};
};
inline VehicleTarget readVehicleTarget(const nsport::Memory &m,const nsport::local::LocalController &owner) {
    VehicleTarget out;if(!owner.verified)return out;
    const auto type=[&](uint64_t object,uint64_t slot){return object && nsport::isA(m,m.encodedPointer(object+0x30),m.pointer(m.base+slot));};
    const auto vehicleType=[&](uint64_t object){
        for(uint64_t slot:{0x7f8b4a0ULL,0x7f33a70ULL,0x7f33b00ULL,0x7f195c8ULL})if(type(object,slot))return true;
        return false;
    };
    uint64_t chosen{},sourcePawn{},sourceField{},sourceRider{},sourceRoot{},sourceParent{};
    out.reason="waiting_controlled_or_ridden_vehicle";
    for(uint64_t field:{0x370ULL,0x2e0ULL}) {
        uint64_t pawn=m.encodedPointer(owner.controller+field),candidate{};
        const char *route="none";uint64_t rider{},root{},parent{};
        if(vehicleType(pawn)){candidate=pawn;route=field==0x2e0 ? "possessed_vehicle" : "acknowledged_vehicle";}
        else if(type(pawn,0x7f2c5b0)) {
            Identity actor;uint8_t dead{};
            if(!objectIdentity(m,pawn,owner.world,actor) || !m.get(pawn+0x930,dead) || (dead&1))continue;
            rider=m.pointer(pawn+0x1a88);if(!rider || m.pointer(rider+0xa0)!=pawn)continue;
            root=m.pointer(pawn+0x278);parent=root ? m.pointer(root+0x230) : 0;
            candidate=parent ? m.pointer(parent+0xa0) : 0;if(!vehicleType(candidate))continue;
            route="attached_character";
        }
        if(!candidate)continue;
        if(chosen && chosen!=candidate){out.reason="ambiguous_local_vehicle";return out;}
        chosen=candidate;sourcePawn=pawn;sourceField=field;sourceRider=rider;sourceRoot=root;sourceParent=parent;out.route=route;
    }
    if(!chosen)return out;
    out.vehicle=chosen;Identity actor;
    if(!objectIdentity(m,chosen,owner.world,actor)){out.reason="vehicle_generation_invalid";return out;}
    uint64_t outer=m.encodedPointer(chosen+8);bool sameWorld=false;
    for(unsigned depth=0;outer && depth<8;++depth){
        if(type(outer,0x80a1620)){sameWorld=m.pointer(outer+0x178)==owner.world;break;}
        uint64_t next=m.encodedPointer(outer+8);if(next==outer)break;outer=next;
    }
    if(!sameWorld){out.reason="vehicle_world_mismatch";return out;}
    uint64_t body=m.pointer(chosen+0x278);uint8_t registered{};
    if(!type(body,0x80ae820)){out.reason="vehicle_root_not_primitive";return out;}
    if(m.pointer(body+0xa0)!=chosen){out.reason="vehicle_root_owner_mismatch";return out;}
    if(!m.get(body+0x84,registered) || !(registered&1)){out.reason="vehicle_root_unregistered";return out;}
    if(!objectIdentity(m,body,owner.world,out.body)){out.reason="vehicle_root_generation_invalid";return out;}
    if(m.encodedPointer(owner.controller+sourceField)!=sourcePawn || m.pointer(chosen+0x278)!=body || m.pointer(body+0xa0)!=chosen){out.reason="vehicle_identity_changed";return out;}
    if(sourceRider && (m.pointer(sourcePawn+0x1a88)!=sourceRider || m.pointer(sourceRider+0xa0)!=sourcePawn ||
        m.pointer(sourcePawn+0x278)!=sourceRoot || m.pointer(sourceRoot+0x230)!=sourceParent || m.pointer(sourceParent+0xa0)!=chosen)){
        out.reason="attachment_changed";return out;
    }
    out.ready=true;out.reason="ready";return out;
}
}
