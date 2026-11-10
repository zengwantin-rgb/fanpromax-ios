#include "SpeedPolicyLease.hpp"
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <map>
using namespace fanpro;
struct Fixture {
    Identity movement{0x1000,0x2000,0x5000,1},character{0x6000,0x7000,0x5000,2};
    std::map<uint64_t,float> fields{{0x16dc,175},{0x1420,135},{0x6bf8,800}};
    float factor{640.0f/175},otherCap{10000};uint64_t rejected{};bool requested{true};
    Access access(bool restore=false) {
        return {this,[](void *c,const Identity &k){auto &f=*static_cast<Fixture *>(c);return k==f.movement || k==f.character;},
            [](void *c,uint64_t at,float &v){auto &f=*static_cast<Fixture *>(c);auto i=f.fields.find(at);if(i==f.fields.end())return false;v=i->second;return true;},
            restore ? restoreWrite : write};
    }
    static bool restoreWrite(void *c,uint64_t at,float v){auto &f=*static_cast<Fixture *>(c);if(f.rejected==at)return false;f.fields.at(at)=v;return true;}
    static bool write(void *c,uint64_t at,float v){auto &f=*static_cast<Fixture *>(c);return f.requested && restoreWrite(c,at,v);}
    static bool native(void *c,const Identity &m,const Identity &a,float &v){auto &f=*static_cast<Fixture *>(c);if(!(m==f.movement && a==f.character))return false;v=std::min({f.fields.at(0x16dc)*f.factor,f.fields.at(0x6bf8),f.otherCap});return true;}
    SpeedPolicyReport apply(SpeedPolicyLease &lease,float mult){return lease.apply(access(),access(true),movement,character,mult,this,native);}
};
int main(){
    Fixture f;SpeedPolicyLease policy;
    auto r=f.apply(policy,3);assert(r.nativeRatioVerified && std::abs(r.actualNative-1920)<0.01f && f.fields.at(0x6bf8)==2400);
    r=f.apply(policy,3);assert(r.nativeRatioVerified && std::abs(r.originalNative-640)<0.01f && f.fields.at(0x16dc)==525);
    f.factor=600.0f/175;r=f.apply(policy,2);assert(r.nativeRatioVerified && std::abs(r.originalNative-600)<0.01f && std::abs(r.actualNative-1200)<0.01f);
    r=f.apply(policy,1);assert(r.nativeRatioVerified && !policy.walkingActive() && f.fields.at(0x16dc)==175 && f.fields.at(0x6bf8)==800);
    f.otherCap=900;r=f.apply(policy,3);assert(!r.nativeRatioVerified && r.result==FieldResult::readbackFailed && f.fields.at(0x16dc)==175 && f.fields.at(0x6bf8)==800);
    f.otherCap=10000;f.rejected=0x6bf8;r=f.apply(policy,3);assert(!r.nativeRatioVerified && f.fields.at(0x16dc)==175 && f.fields.at(0x1420)==135);
    f.rejected=0;r=f.apply(policy,3);assert(r.nativeRatioVerified);f.requested=false;
    r=f.apply(policy,2);assert(!r.nativeRatioVerified && f.fields.at(0x16dc)==175 && f.fields.at(0x6bf8)==800);
    f.requested=true;r=f.apply(policy,3);assert(r.nativeRatioVerified);f.fields.at(0x6bf8)=700;
    r=f.apply(policy,3);assert(!r.nativeRatioVerified && r.result==FieldResult::conflict && f.fields.at(0x16dc)==175 && f.fields.at(0x6bf8)==700);
    Fixture stale;SpeedPolicyLease stalePolicy;assert(stale.apply(stalePolicy,3).nativeRatioVerified);++stale.character.serial;
    r=stale.apply(stalePolicy,3);assert(!r.nativeRatioVerified && stale.fields.at(0x16dc)==175 && stale.fields.at(0x6bf8)==2400);
    puts("PASS: independent cap, same-task native ratio, no compounding, changed policy, unrelated clamp rejection, partial rollback, cancellation, game edits and recycled identity");
}
