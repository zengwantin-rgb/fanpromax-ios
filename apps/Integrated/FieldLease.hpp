#pragma once
#include <cmath>
#include <cstdint>
namespace fanpro {
struct Identity {
    uint64_t object{},item{},world{};int32_t serial{};
    bool operator==(const Identity &o)const{return object==o.object && item==o.item && world==o.world && serial==o.serial;}
};
struct Access {
    void *context{};
    bool (*live)(void *,const Identity &){};
    bool (*read)(void *,uint64_t,float &){};
    bool (*write)(void *,uint64_t,float){};
};
enum class FieldResult {off,applied,unchanged,invalid,stale,readFailed,writeFailed,readbackFailed,conflict};
// An exact field lease never restores into a recycled object or overwrites a game's new value.
class FieldLease {
    Identity key{};uint64_t offset{};float original{},owned{};bool held{};
    bool valid(const Access &io)const{return io.live && io.read && io.write && io.live(io.context,key);}
public:
    bool active()const{return held;}
    FieldResult restore(const Access &io) {
        if(!held)return FieldResult::off;
        if(!valid(io)){held=false;return FieldResult::stale;}
        float current{};
        if(!io.read(io.context,key.object+offset,current))return FieldResult::readFailed;
        if(current!=owned){held=false;return FieldResult::conflict;}
        if(!io.live(io.context,key)) {held=false;return FieldResult::stale;}
        if(!io.write(io.context,key.object+offset,original))return FieldResult::writeFailed;
        float check{};
        if(!io.read(io.context,key.object+offset,check) || check!=original)return FieldResult::readbackFailed;
        held=false;return FieldResult::off;
    }
    FieldResult apply(const Access &io,const Identity &target,uint64_t field,float multiplier) {
        if(!target.object || !target.item || !target.serial || !target.world || field>0x20000 || field%4 ||
            !std::isfinite(multiplier) || multiplier<1 || multiplier>3)return FieldResult::invalid;
        if(held && (!(key==target) || offset!=field)) {
            auto result=restore(io);
            if(held)return result;
        }
        Identity candidate=target;
        if(!io.live || !io.read || !io.write || !io.live(io.context,candidate))return FieldResult::stale;
        float current{};
        if(!io.read(io.context,candidate.object+field,current))return FieldResult::readFailed;
        if(!std::isfinite(current) || current<=0 || current>10000)return FieldResult::invalid;
        if(held && current!=owned) {held=false;return FieldResult::conflict;}
        float baseline=held ? original : current;
        float desired=baseline*multiplier;
        if(!std::isfinite(desired) || desired>10000)return FieldResult::invalid;
        if(!held){key=candidate;offset=field;original=current;owned=current;held=true;}
        if(current==desired)return FieldResult::unchanged;
        if(!io.live(io.context,key)){held=false;return FieldResult::stale;}
        if(!io.write(io.context,key.object+offset,desired))return FieldResult::writeFailed;
        owned=desired; // Retain the restoration lease even when subsequent readback fails.
        float check{};
        if(!io.read(io.context,key.object+offset,check) || check!=desired)return FieldResult::readbackFailed;
        return FieldResult::applied;
    }
};
}
