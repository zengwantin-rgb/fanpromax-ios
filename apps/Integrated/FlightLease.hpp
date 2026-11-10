#pragma once
#include "FieldLease.hpp"
namespace fanpro {
struct Velocity{float x{},y{},z{};};
struct PhysicsAccess {
    void *context{};
    bool (*live)(void *,const Identity &){};
    bool (*gravity)(void *,const Identity &,bool &){};
    bool (*setGravity)(void *,const Identity &,bool){};
    bool (*velocity)(void *,const Identity &,Velocity &){};
    bool (*setVelocity)(void *,const Identity &,Velocity){};
};
class FlightLease {
    Identity key{};bool held{},originalGravity{};
public:
    bool active()const{return held;}
    FieldResult restore(const PhysicsAccess &io) {
        if(!held)return FieldResult::off;
        if(!io.live(io.context,key)){held=false;return FieldResult::stale;}
        bool value{};
        if(!io.gravity(io.context,key,value))return FieldResult::readFailed;
        if(value){held=false;return FieldResult::conflict;}
        if(!io.setGravity(io.context,key,originalGravity))return FieldResult::writeFailed;
        if(!io.gravity(io.context,key,value) || value!=originalGravity)return FieldResult::readbackFailed;
        held=false;return FieldResult::off;
    }
    FieldResult apply(const PhysicsAccess &io,const Identity &target,int direction) {
        if(direction < -1 || direction>1)return FieldResult::invalid;
        if(held && !(key==target)){auto r=restore(io);if(held)return r;}
        if(!io.live(io.context,target))return FieldResult::stale;
        if(!held){
            bool value{};if(!io.gravity(io.context,target,value))return FieldResult::readFailed;
            key=target;originalGravity=value;
            if(!io.setGravity(io.context,key,false))return FieldResult::writeFailed;
            held=true;
            if(!io.gravity(io.context,key,value) || value)return FieldResult::readbackFailed;
        }
        bool currentGravity{};
        if(!io.live(io.context,key))return FieldResult::stale;
        if(!io.gravity(io.context,key,currentGravity))return FieldResult::readFailed;
        if(currentGravity)return FieldResult::conflict;
        Velocity velocity{};
        if(!io.velocity(io.context,key,velocity))return FieldResult::readFailed;
        if(!std::isfinite(velocity.x) || !std::isfinite(velocity.y) || !std::isfinite(velocity.z) ||
            std::abs(velocity.x)>30000 || std::abs(velocity.y)>30000 || std::abs(velocity.z)>30000)return FieldResult::invalid;
        velocity.z=direction*300.0f;
        if(!io.live(io.context,key))return FieldResult::stale;
        if(!io.setVelocity(io.context,key,velocity))return FieldResult::writeFailed;
        if(!io.live(io.context,key))return FieldResult::stale;
        Velocity actual{};
        if(!io.velocity(io.context,key,actual))return FieldResult::readbackFailed;
        auto matches=[](float requested,float observed) {
            return std::isfinite(observed) && std::abs(requested-observed)<=0.5f+std::abs(requested)*0.0001f;
        };
        if(!matches(velocity.x,actual.x) || !matches(velocity.y,actual.y) || !matches(velocity.z,actual.z))return FieldResult::readbackFailed;
        // Immediate local physics readback only; this does not establish sustained motion.
        return FieldResult::applied;
    }
};
}
