#include "DisplayPolicy.hpp"
#include <cassert>
#include <iostream>
#include <limits>
using namespace nsport;
int main() {
    Snapshot s;s.cameraReady=true;
    Marker m;m.kind=Kind::character;m.relation=Relation::enemy;m.playerKind=PlayerKind::human;m.position={10000,0,0};s.markers.push_back(m);
    m.playerKind=PlayerKind::bot;s.markers.push_back(m);
    m.playerKind=PlayerKind::unknown;s.markers.push_back(m);
    m.playerKind=PlayerKind::human;m.relation=Relation::teammate;s.markers.push_back(m);
    m.relation=Relation::enemy;m.position={20000,0,0};s.markers.push_back(m);
    m.position={20001,0,0};s.markers.push_back(m);
    m.position={0,0,20001};s.markers.push_back(m); // Range uses all three dimensions.
    m.position={std::numeric_limits<float>::quiet_NaN(),0,0};s.markers.push_back(m);
    m.kind=Kind::vehicle;m.position={100,0,0};s.markers.push_back(m);
    auto counts=displayCounts(s,true,false,200);assert(counts.humans==2 && counts.bots==1 && counts.unknown==1);
    counts=displayCounts(s,true,true,200);assert(counts.humans==2 && counts.bots==0 && counts.unknown==1);
    counts=displayCounts(s,false,false,200);assert(counts.humans==3 && counts.bots==1 && counts.unknown==1);
    counts=displayCounts(s,true,true,50);assert(counts.humans==0 && counts.bots==0 && counts.unknown==0);
    s.cameraReady=false;counts=displayCounts(s,false,false,3000);assert(counts.humans==0 && counts.bots==0 && counts.unknown==0);
    assert(displayCharacter(s.markers[2],true,true)); // Unknown classification is never guessed to be a bot.
    assert(!displayCharacter(s.markers[1],false,true));assert(displayCharacter(s.markers.back(),true,true));
    assert(displayRange({20000,0,0},{},200) && !displayRange({20001,0,0},{},200));
    assert(!displayRange({},{},0) && !displayRange({},{},3001));
    assert(!displayRange({},{},std::numeric_limits<float>::infinity()));
    assert(!displayRange({},{std::numeric_limits<float>::quiet_NaN(),0,0},200));
    std::cout<<"PASS: shared world/radar bot/team filters; unknown classification retained; filtered counts; inclusive distance boundary, 3D range, invalid camera/distance and absent camera\n";
}
