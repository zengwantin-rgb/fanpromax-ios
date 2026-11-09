#pragma once
#include "PortCore.hpp"
#include <cmath>
namespace nsport {
inline bool displayCharacter(const Marker &m,bool hideTeammates,bool hideBots) {
    if(m.kind!=Kind::character)return true;
    return !(hideTeammates && m.relation==Relation::teammate) && !(hideBots && m.playerKind==PlayerKind::bot);
}
inline bool displayRange(Vec3 position,Vec3 camera,float meters) {
    if(!std::isfinite(meters)||meters<=0||meters>3000)return false;
    const float d=distance(position,camera);
    return std::isfinite(d) && d<=meters*100;
}
struct DisplayCounts {uint32_t humans{},bots{},unknown{};};
inline DisplayCounts displayCounts(const Snapshot &snapshot,bool hideTeammates,bool hideBots,float meters) {
    DisplayCounts result;if(!snapshot.cameraReady)return result;
    for(const auto &m:snapshot.markers) {
        if(m.kind!=Kind::character || !displayCharacter(m,hideTeammates,hideBots) || !displayRange(m.position,snapshot.camera.position,meters))continue;
        if(m.playerKind==PlayerKind::human)++result.humans;
        else if(m.playerKind==PlayerKind::bot)++result.bots;
        else ++result.unknown;
    }
    return result;
}
}
