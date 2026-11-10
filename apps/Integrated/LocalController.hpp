#pragma once
#include "PortCore.hpp"
#include <algorithm>

namespace nsport::local {
struct LocalController {
    uint64_t world{},controller{},player{};
    uint32_t controllers{},ownedControllers{};
    bool verified{};
    const char *reason{"waiting_engine"};
};

// Pinned native ownership route: Engine world context -> GameInstance.LocalPlayers.
// World-context and GameInstance links are ordinary pointers; LocalPlayers entries
// and PlayerController.Player use the original 24-byte encoded object reference.
inline LocalController readLocalController(const Memory &m) {
    struct Array {uint64_t data;int32_t count,capacity;};
    const auto same=[](const Array &a,const Array &b){
        return a.data==b.data && a.count==b.count && a.capacity==b.capacity;
    };
    const auto valid=[](const Array &a,int maximum){
        return a.data && a.count>0 && a.count<=maximum && a.capacity>=a.count && a.capacity<=4096;
    };
    const auto type=[&](uint64_t object,uint64_t singleton){
        return object && isA(m,m.encodedPointer(object+0x30),m.pointer(m.base+singleton));
    };
    LocalController out;
    const auto engine=m.pointer(m.base+0x81e8ef0);
    if(!type(engine,0x8098ac8)) return out;
    out.reason="waiting_viewport";const auto viewport=m.pointer(engine+0x960);
    if(!type(viewport,0x809b590)) return out;
    out.reason="waiting_world";out.world=m.pointer(viewport+0x1f8);
    if(!type(out.world,0x80b74f0)) return out;
    Array contexts{},players{},controllers{};
    out.reason="waiting_world_context";
    if(!m.get(engine+0x210,contexts) || !valid(contexts,64)) return out;
    uint64_t context{},contextAddress{};
    for(int32_t i=0;i<contexts.count;++i) {
        const auto at=contexts.data+uint64_t(i)*8;const auto candidate=m.pointer(at);
        if(!candidate || m.pointer(candidate+0x250)!=out.world) continue;
        if(context) {out.reason="multiple_world_contexts";return out;}
        context=candidate;contextAddress=at;
    }
    if(!context) return out;
    out.reason="waiting_game_instance";const auto instance=m.pointer(context+0x70);
    if(!instance) return out;
    out.reason="waiting_local_players";
    if(!m.get(instance+0x60,players) || !valid(players,16)) return out;
    std::array<std::array<uint64_t,3>,16> playerWords{};
    std::array<uint64_t,16> localPlayers{};
    for(int32_t i=0;i<players.count;++i) {
        if(!m.get(players.data+uint64_t(i)*24,playerWords[i])) {out.reason="local_players_unreadable";return out;}
        localPlayers[i]=decodePointer(playerWords[i]);
        if(!type(localPlayers[i],0x80a23c0)) {out.reason="local_player_type_unverified";return out;}
    }
    out.reason="waiting_controller";
    if(!m.get(out.world+0x230,controllers) || !valid(controllers,16)) return out;
    std::array<uint64_t,16> resolved{},seen{};
    std::array<std::array<uint64_t,3>,16> ownerWords{};
    std::array<bool,16> ownerRead{};
    for(int32_t i=0;i<controllers.count;++i) {
        resolved[i]=resolveWeak(m,controllers.data+uint64_t(i)*24);
        const auto candidate=resolved[i];
        if(!type(candidate,0x80ad348)) continue;
        if(std::find(seen.begin(),seen.begin()+out.controllers,candidate)!=seen.begin()+out.controllers) continue;
        seen[out.controllers++]=candidate;
        if(!m.get(candidate+0x358,ownerWords[i])) {out.controller=0;out.reason="controller_player_unreadable";return out;}
        ownerRead[i]=true;const auto player=decodePointer(ownerWords[i]);
        if(std::find(localPlayers.begin(),localPlayers.begin()+players.count,player)==localPlayers.begin()+players.count) continue;
        ++out.ownedControllers;out.controller=candidate;out.player=player;
    }
    out.reason="controller_identity_changed";Array current{};
    if(m.pointer(m.base+0x81e8ef0)!=engine || m.pointer(engine+0x960)!=viewport ||
            m.pointer(viewport+0x1f8)!=out.world || !m.get(engine+0x210,current) || !same(current,contexts) ||
            m.pointer(contextAddress)!=context || m.pointer(context+0x250)!=out.world ||
            m.pointer(context+0x70)!=instance || !m.get(instance+0x60,current) || !same(current,players) ||
            !m.get(out.world+0x230,current) || !same(current,controllers)) {out.controller=0;return out;}
    for(int32_t i=0;i<players.count;++i) {
        std::array<uint64_t,3> words{};
        if(!m.get(players.data+uint64_t(i)*24,words) || words!=playerWords[i] || !type(localPlayers[i],0x80a23c0)) {
            out.controller=0;return out;
        }
    }
    for(int32_t i=0;i<controllers.count;++i) {
        if(resolveWeak(m,controllers.data+uint64_t(i)*24)!=resolved[i]) {out.controller=0;return out;}
        if(!ownerRead[i]) continue;
        std::array<uint64_t,3> words{};
        if(!m.get(resolved[i]+0x358,words) || words!=ownerWords[i]) {out.controller=0;return out;}
    }
    if(out.ownedControllers!=1) {
        out.controller=0;out.player=0;
        out.reason=out.ownedControllers ? "multiple_owned_controllers" : "no_owned_controller";
        return out;
    }
    out.verified=true;out.reason="unique_owned_controller";return out;
}
}
