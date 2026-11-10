#pragma once
#include "FieldLease.hpp"
namespace fanpro {
struct SpeedPolicyReport {
    FieldResult result{FieldResult::off},cleanup{FieldResult::off};
    const char *stage{"off"};
    float originalNative{},expectedNative{},actualNative{};
    unsigned writes{};bool nativeRatioVerified{};
};
class SpeedPolicyLease {
    FieldLease walk,crouch,cap;
    static bool error(FieldResult r){return r!=FieldResult::off && r!=FieldResult::applied && r!=FieldResult::unchanged;}
public:
    bool walkingActive()const{return walk.active();}
    bool crouchingActive()const{return crouch.active();}
    bool capActive()const{return cap.active();}
    FieldResult restore(const Access &io) {
        // Attempt every restoration even if one object disappeared or a field changed.
        auto a=walk.restore(io),b=crouch.restore(io),c=cap.restore(io);
        return error(a) ? a : error(b) ? b : c;
    }
    SpeedPolicyReport apply(const Access &io,const Access &restoreIO,
        const Identity &movement,const Identity &character,float multiplier,
        void *context,bool (*nativeMax)(void *,const Identity &,const Identity &,float &)) {
        SpeedPolicyReport report;
        auto fail=[&](FieldResult result,const char *stage){report.result=result;report.stage=stage;report.cleanup=restore(restoreIO);if(!std::isfinite(report.originalNative))report.originalNative=0;if(!std::isfinite(report.expectedNative))report.expectedNative=0;if(!std::isfinite(report.actualNative))report.actualNative=0;return report;};
        if(!std::isfinite(multiplier) || multiplier<1 || multiplier>3 || !nativeMax)return fail(FieldResult::invalid,"request");
        // Measure the original policy in the same game-thread task. No frame is advanced
        // between restoration, native baseline sampling, writes and verification.
        report.cleanup=restore(restoreIO);
        if(error(report.cleanup)){report.result=report.cleanup;report.stage="restore_previous";return report;}
        if(!nativeMax(context,movement,character,report.originalNative))return fail(FieldResult::readFailed,"native_baseline");
        report.expectedNative=report.originalNative*multiplier;
        if(!std::isfinite(report.originalNative) || report.originalNative<=0 ||
            !std::isfinite(report.expectedNative) || report.expectedNative>10000)return fail(FieldResult::invalid,"native_baseline");
        if(multiplier!=1) {
            auto a=walk.apply(io,movement,0x6dc,multiplier);
            if(a==FieldResult::applied)++report.writes;
            if(error(a))return fail(a,"walking_field");
            auto b=crouch.apply(io,movement,0x420,multiplier);
            if(b==FieldResult::applied)++report.writes;
            if(error(b))return fail(b,"crouching_field");
            // Native GetMaxSpeed clamps a walking branch using character+0xbf8.
            // Raising only the movement fields leaves this independent ceiling intact.
            auto c=cap.apply(io,character,0xbf8,multiplier);
            if(c==FieldResult::applied)++report.writes;
            if(error(c))return fail(c,"character_cap");
        }
        if(!nativeMax(context,movement,character,report.actualNative))return fail(FieldResult::readFailed,"native_result");
        if(!std::isfinite(report.actualNative) ||
            std::abs(report.actualNative-report.expectedNative)>0.5f+report.expectedNative*0.005f)
            return fail(FieldResult::readbackFailed,"native_ratio_not_met");
        report.nativeRatioVerified=true;report.stage="native_ratio_verified";
        report.result=multiplier==1 ? FieldResult::unchanged : FieldResult::applied;
        return report;
    }
};
}
