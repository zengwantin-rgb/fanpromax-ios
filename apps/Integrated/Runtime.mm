#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include "CollisionRuntimeRead.hpp"
#include "FieldLease.hpp"
#include "SpeedPolicyLease.hpp"
#include "FlightLease.hpp"
#include "LocalController.hpp"
#include "VehicleTarget.hpp"
#include "MotionWindow.hpp"
#ifndef FANPRO_UI_PREVIEW
#include "VerifiedProfile.hpp"
#else
namespace fanpro {inline bool verifyProfile(const nsport::Memory &){return false;}}
#endif
#include <atomic>
#include <mutex>

namespace {
using namespace nsport;
using namespace collision_runtime;
std::atomic<bool> speedRequested{false},flightRequested{false};
std::atomic<int> flightDirection{0};
fanpro::FlightLease flightLease;
NSString *flightOutcome=@"等待载具";
uint64_t flightCalls{};
uint64_t writeRevision{};
std::atomic<unsigned> speedTenths{10};
std::atomic<bool> pendingTask{false};
std::atomic<uint64_t> requestRevision{0};
fanpro::SpeedPolicyLease speedPolicy;
uint64_t currentWorld{};
NSString *lastOutcome=@"尚未修改";
NSString *profileError;
fanpro::MotionWindow motionWindow;NSDictionary *lastMotionWindow;NSMutableArray *motionWindows;
NSDictionary *contextDiagnostics;NSString *cleanupOutcome=@"none";
NSTimeInterval lastSpeedWriteTime{};
uint64_t localVerifiedFrames{},characterReadyFrames{},eligibleSpeedFrames{};
NSString *lastFailure;NSTimeInterval lastFailureTime{};
uint64_t taskCount{},speedWrites{};
NSTimeInterval lastLog{};
NSString *folder;
BOOL ready{};
static bool live(void *,const fanpro::Identity &key) {
    struct Item {uint64_t reserved,object;uint32_t flags;int32_t serial;};Item item{};
    return key.world && key.world==currentWorld && key.serial && memory.get(key.item,item) &&
        item.object==key.object && item.serial==key.serial && !(item.flags&0x30000000);
}
static bool readFloat(void *,uint64_t address,float &value){return memory.get(address,value);}
static bool writeFloat(void *,uint64_t address,float value) {
    if(!speedRequested.load() || writeRevision!=requestRevision.load())return false;
    return vm_write(mach_task_self(),address,reinterpret_cast<vm_offset_t>(&value),sizeof value)==KERN_SUCCESS;
}
static bool restoreFloat(void *,uint64_t address,float value) {
    return vm_write(mach_task_self(),address,reinterpret_cast<vm_offset_t>(&value),sizeof value)==KERN_SUCCESS;
}
fanpro::Access fieldAccess{nullptr,live,readFloat,writeFloat};
fanpro::Access restoreAccess{nullptr,live,readFloat,restoreFloat};
static bool nativeSpeed(void *,const fanpro::Identity &movement,const fanpro::Identity &character,float &value) {
    if(!live(nullptr,movement) || !live(nullptr,character) || memory.pointer(movement.object+0x188)!=character.object)return false;
    uint64_t table=memory.pointer(movement.object),getter=table ? memory.pointer(table+0x480) : 0;
    if(table!=memory.base+0x7127e10 || getter!=memory.base+0x1c6cc90)return false;
    value=reinterpret_cast<float (*)(void *)>(getter)(reinterpret_cast<void *>(movement.object));
    return std::isfinite(value) && value>=0 && value<=10000;
}
static bool identity(uint64_t object,uint64_t world,fanpro::Identity &out) {
    struct Item {uint64_t reserved,object;uint32_t flags;int32_t serial;};
    std::array<uint32_t,3> words{};int32_t count{};
    if(!object || !memory.get(object+0x20,words) || !memory.get(memory.base+0x8174538,count) || count<=0 || count>2000000)return false;
    uint32_t index=decodeSerial(words);if(index>=uint32_t(count))return false;
    uint64_t table=memory.pointer(memory.base+0x8174520),chunk=table ? memory.pointer(table+uint64_t(index>>16)*8) : 0;
    if(!chunk)return false;
    uint64_t at=chunk+uint64_t(index&0xffff)*sizeof(Item);Item item{};
    if(!memory.get(at,item) || item.object!=object || !item.serial || (item.flags&0x30000000))return false;
    out={object,at,world,item.serial};return true;
}
static bool primitive(const fanpro::Identity &key) {
    uint8_t registered{};
    return live(nullptr,key) && isA(memory,memory.encodedPointer(key.object+0x30),memory.pointer(memory.base+0x80ae820)) &&
        memory.get(key.object+0x84,registered) && (registered&1);
}
static uint64_t method(const fanpro::Identity &key,uint64_t offset) {
    if(!primitive(key))return 0;
    uint64_t table=memory.pointer(key.object),target=table ? memory.pointer(table+offset) : 0;
    return target>=memory.base+textBegin && target<memory.base+textEnd && target%4==0 ? target : 0;
}
static bool gravity(void *,const fanpro::Identity &key,bool &value) {
    uint64_t target=method(key,0x820);if(!target)return false;
    value=reinterpret_cast<bool (*)(void *)>(target)(reinterpret_cast<void *>(key.object));return true;
}
static bool setGravity(void *,const fanpro::Identity &key,bool value) {
    uint64_t target=method(key,0x818);if(!target)return false;
    reinterpret_cast<void (*)(void *,bool)>(target)(reinterpret_cast<void *>(key.object),value);return true;
}
static bool velocity(void *,const fanpro::Identity &key,fanpro::Velocity &value) {
    if(!primitive(key))return false;
    value=reinterpret_cast<fanpro::Velocity (*)(void *,uint64_t)>(memory.base+0x5517194)(reinterpret_cast<void *>(key.object),0);return true;
}
static bool setVelocity(void *,const fanpro::Identity &key,fanpro::Velocity value) {
    uint64_t target=method(key,0x690);if(!target)return false;
    reinterpret_cast<void (*)(void *,fanpro::Velocity,bool,uint64_t)>(target)(reinterpret_cast<void *>(key.object),value,false,0);++flightCalls;return true;
}
fanpro::PhysicsAccess physics{nullptr,live,gravity,setGravity,velocity,setVelocity};
static const char *resultName(fanpro::FieldResult result) {
    using R=fanpro::FieldResult;
    switch(result){case R::off:return "restored";case R::applied:return "written_readback_confirmed";
        case R::unchanged:return "unchanged";case R::invalid:return "invalid_value";case R::stale:return "object_invalidated";
        case R::readFailed:return "read_failed";case R::writeFailed:return "write_failed";
        case R::readbackFailed:return "readback_failed";case R::conflict:return "game_value_changed";}
    return "unknown";
}
static bool failed(fanpro::FieldResult result){return result!=fanpro::FieldResult::off && result!=fanpro::FieldResult::applied && result!=fanpro::FieldResult::unchanged;}
static void record(NSString *phase) {
    if(!folder)return;
    NSDictionary *value=@{@"version":@"integrated-i4-review",@"phase":phase,@"time":@(NSDate.date.timeIntervalSince1970),
        @"context":contextDiagnostics?:@{},@"last_motion_window":lastMotionWindow?:@{},@"motion_windows":motionWindows?:@[],@"cleanup_outcome":cleanupOutcome,
        @"last_speed_write_time":@(lastSpeedWriteTime),@"local_verified_frames":@(localVerifiedFrames),
        @"character_ready_frames":@(characterReadyFrames),@"eligible_speed_frames":@(eligibleSpeedFrames),
        @"profile_ready":@(ready),@"last_failure":lastFailure?:@"",@"last_failure_time":@(lastFailureTime),@"profile_error":profileError?:@"",@"speed_requested":@(speedRequested.load()),
        @"selected_multiplier":@(speedTenths.load()/10.0),@"speed_field_outcome":lastOutcome?:@"",
        @"flight_requested":@(flightRequested.load()),@"flight_outcome":flightOutcome?:@"",
        @"flight_calls":@(flightCalls),@"flight_lease_active":@(flightLease.active()),
        @"invincibility_implemented":@NO,@"damage_reduction_implemented":@NO,
        @"task_count":@(taskCount),@"speed_field_writes_confirmed":@(speedWrites),
        @"walking_lease_active":@(speedPolicy.walkingActive()),@"crouching_lease_active":@(speedPolicy.crouchingActive()),@"character_cap_lease_active":@(speedPolicy.capActive()),
        @"measured_speed_multiplier_verified":@NO,@"server_acceptance_verified":@NO,
        @"aim_included":@NO,@"recoil_included":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[folder stringByAppendingPathComponent:@"integrated-status.json"] atomically:YES];
}
static bool taskMethod(Class cls,SEL selector,uint64_t rva,const char *types,bool classMethod) {
    Method method=classMethod ? class_getClassMethod(cls,selector) : class_getInstanceMethod(cls,selector);
    return method && reinterpret_cast<uint64_t>(method_getImplementation(method))==memory.base+rva &&
        !std::strcmp(method_getTypeEncoding(method),types);
}
static bool validTaskClass(Class cls) {
    return cls && taskMethod(cls,sel_registerName("CreateTaskWithBlock:"),0x3b7804c,"v24@0:8@?16",true) &&
        taskMethod(cls,sel_registerName("ProcessAsyncTasks"),0x3b780d4,"v16@0:8",true) &&
        taskMethod(cls,sel_registerName("CheckForCompletion"),0x3b7809c,"B16@0:8",false);
}
static bool ownedCharacter(const local::LocalController &local,CollisionContext &out) {
    if(!local.verified)return false;
    for(uint64_t field:{0x370ULL,0x2e0ULL}) {
        uint64_t pawn=memory.encodedPointer(local.controller+field);uint8_t dead{};fanpro::Identity key;
        if(!pawn || !isA(memory,memory.encodedPointer(pawn+0x30),memory.pointer(memory.base+0x7f2c5b0)) ||
            !identity(pawn,local.world,key) || !memory.get(pawn+0x930,dead) || (dead&1))continue;
        if(memory.encodedPointer(local.controller+field)!=pawn)continue;
        out.world=local.world;out.controller=local.controller;out.pawn=pawn;return true;
    }
    return false;
}
static void perform(uint64_t revision) {
    ++taskCount;cleanupOutcome=@"none";writeRevision=revision;CollisionContext target;
    const auto owner=local::readLocalController(memory);
    CollisionObservation observation;
    if(owner.verified)observation=observeCollision(memory,textBegin,textEnd,&target,owner.controller);
    // Losing a transient ownership observation must not discard restoration baselines.
    currentWorld=owner.verified ? owner.world : 0;
    uint8_t dead{};bool aliveReadable=target.pawn && memory.get(target.pawn+0x930,dead);
    bool valid=owner.verified && observation.stage==CollisionObservation::Stage::ready && target.generationsValid && aliveReadable && !(dead&1);
    if(owner.verified)++localVerifiedFrames;
    if(valid)++characterReadyFrames;
    bool wanted=speedRequested.load() && revision==requestRevision.load() && valid && observation.movementMode==1;
    NSMutableDictionary *details=[@{@"local_controller_verified":@(owner.verified),@"local_controller_reason":@(owner.reason),
        @"controllers_seen":@(owner.controllers),@"owned_controllers":@(owner.ownedControllers),
        @"character_stage":owner.verified ? @(collisionStageName(observation.stage)) : @"not_observed_without_owned_controller",
        @"character_generations_valid":@(target.generationsValid),@"alive_readable":@(aliveReadable),
        @"character_alive":@(aliveReadable && !(dead&1)),@"movement_mode":@(observation.movementMode),
        @"speed_eligible":@(wanted)} mutableCopy];
    contextDiagnostics=details;
    if(!wanted) {
        if(owner.verified) {
            auto result=speedPolicy.restore(restoreAccess);
            cleanupOutcome=[NSString stringWithFormat:@"speed %s",resultName(result)];
        } else cleanupOutcome=@"deferred_until_local_identity_returns";
        if(!speedRequested.load())lastOutcome=@"speed_disabled";
        else if(!owner.verified)lastOutcome=[@"waiting_local_player: " stringByAppendingString:@(owner.reason)];
        else if(!valid)lastOutcome=[NSString stringWithFormat:@"character_not_ready: %s; generations=%d; alive=%d",collisionStageName(observation.stage),target.generationsValid,aliveReadable && !(dead&1)];
        else lastOutcome=[NSString stringWithFormat:@"movement_mode_%u_or_request_changed",unsigned(observation.movementMode)];
    } else {
        ++eligibleSpeedFrames;
        fanpro::Identity key{target.movement,target.items[1],target.world,target.serials[1]};
        float multiplier=speedTenths.load()/10.0f;
        fanpro::Identity actor{target.pawn,target.items[0],target.world,target.serials[0]};
        auto result=speedPolicy.apply(fieldAccess,restoreAccess,key,actor,multiplier,nullptr,nativeSpeed);
        speedWrites+=result.writes;
        if(result.writes)lastSpeedWriteTime=NSDate.date.timeIntervalSince1970;
        details[@"original_native_speed_cm_s"]=@(result.originalNative);
        details[@"requested_native_speed_cm_s"]=@(result.expectedNative);
        details[@"result_native_speed_cm_s"]=@(result.actualNative);
        details[@"native_speed_ratio_verified"]=@(result.nativeRatioVerified);
        details[@"native_speed_verification_scope"]=@"same-task original and modified client policy; not actual displacement or server acceptance";
        lastOutcome=[NSString stringWithFormat:@"%s: %s",result.stage,resultName(result.result)];
        if(failed(result.result)) {
            lastFailure=[@"speed: " stringByAppendingString:lastOutcome];lastFailureTime=NSDate.date.timeIntervalSince1970;
            speedRequested.store(false);auto cleanup=speedPolicy.restore(restoreAccess);
            cleanupOutcome=[NSString stringWithFormat:@"speed %s / %s",resultName(result.cleanup),resultName(cleanup)];record(@"speed_failure");
        }
    }
    // Keep the same end-of-window observation with historical motion, including after entering a vehicle.
    if(valid) {
        float field{};
        if(memory.get(target.movement+0x6dc,field) && std::isfinite(field))details[@"walking_speed_field"]=@(field);
        if(memory.get(target.movement+0x420,field) && std::isfinite(field))details[@"crouching_speed_field"]=@(field);
        if(memory.get(target.pawn+0xbf0,field) && std::isfinite(field))details[@"character_speed_base_candidate_cm_s"]=@(field);
        if(memory.get(target.pawn+0xbf8,field) && std::isfinite(field))details[@"character_speed_cap_candidate_cm_s"]=@(field);
        if(memory.get(target.movement+0x17e8,field) && std::isfinite(field))details[@"movement_override_speed_candidate_cm_s"]=@(field);
        uint64_t table=memory.pointer(target.movement),getter=table ? memory.pointer(table+0x480) : 0;
        details[@"native_speed_getter_available"]=@(table==memory.base+0x7127e10 && getter==memory.base+0x1c6cc90);
        if([details[@"native_speed_getter_available"] boolValue]) {
            float value=reinterpret_cast<float (*)(void *)>(getter)(reinterpret_cast<void *>(target.movement));
            if(std::isfinite(value) && value>=0 && value<=10000)details[@"native_max_speed_cm_s"]=@(value);
        }
    }
    // Read actual local velocity and displacement; never export world coordinates.
    details[@"motion_available"]=@NO;
    if(valid && observation.rootIsCapsule) {
        Vec3 position{},linear{};
        if(memory.get(target.capsule+0x150,position) && memory.get(target.movement+0xbfc,linear) &&
            std::isfinite(position.x) && std::isfinite(position.y) && std::isfinite(linear.x) && std::isfinite(linear.y)) {
            details[@"motion_available"]=@YES;details[@"local_velocity_mps"]=@(std::hypot(double(linear.x),double(linear.y))/100);
            fanpro::Identity actor{target.pawn,target.items[0],target.world,target.serials[0]};
            auto measured=motionWindow.add(actor,speedRequested.load() ? speedTenths.load() : 10,
                NSProcessInfo.processInfo.systemUptime,position.x,position.y);
            if(measured.valid) {lastMotionWindow=@{@"time":@(NSDate.date.timeIntervalSince1970),@"seconds":@(measured.seconds),
                @"net_meters":@(measured.netMeters),@"path_meters":@(measured.pathMeters),@"net_mps":@(measured.netMPS),
                @"path_mps":@(measured.pathMPS),@"samples":@(measured.samples),@"selected_multiplier":@(measured.tenths/10.0),
                @"end_sample_context":[details copy],
                @"scope":@"local root displacement; straight-line comparison required; no server acceptance inferred"};
                if(!motionWindows)motionWindows=[NSMutableArray array];
                [motionWindows addObject:lastMotionWindow];if(motionWindows.count>90)[motionWindows removeObjectAtIndex:0];
            }
        } else motionWindow.reset();

    } else motionWindow.reset();
    fanpro::Identity vehicleRoot;CollisionContext carrier;
    bool flightWanted=flightRequested.load() && revision==requestRevision.load() && owner.verified;
    bool carrierReady=ownedCharacter(owner,carrier);
    const auto vehicle=fanpro::readVehicleTarget(memory,owner);vehicleRoot=vehicle.body;
    details[@"flight_target_ready"]=@(vehicle.ready);details[@"flight_target_reason"]=@(vehicle.reason);details[@"flight_target_route"]=@(vehicle.route);
    details[@"flight_carrier_ready"]=@(carrierReady);
    details[@"flight_velocity_readback_confirmed"]=@NO;
    details[@"flight_readback_scope"]=@"immediate local physics velocity only; no sustained flight or server acceptance inferred";
    if(flightWanted && vehicle.ready) {
        if(!flightLease.active())record(@"flight_first_call_begin");
        auto result=flightLease.apply(physics,vehicleRoot,flightDirection.load());flightOutcome=@(resultName(result));
        details[@"flight_velocity_readback_confirmed"]=@(result==fanpro::FieldResult::applied);
        if(failed(result)){lastFailure=[@"flight: " stringByAppendingString:flightOutcome];lastFailureTime=NSDate.date.timeIntervalSince1970;flightRequested.store(false);flightLease.restore(physics);record(@"flight_failure");}
    } else {
        if(owner.verified) {
            if(flightLease.active())record(@"flight_restore_begin");
            auto result=flightLease.restore(physics);cleanupOutcome=[cleanupOutcome stringByAppendingFormat:@"; flight %s",resultName(result)];
        }
        if(!flightRequested.load())flightOutcome=@"flight_disabled";
        else if(!owner.verified)flightOutcome=[@"waiting_local_player: " stringByAppendingString:@(owner.reason)];
        else if(!vehicle.ready)flightOutcome=[@"waiting_vehicle: " stringByAppendingString:@(vehicle.reason)];
        else if(revision!=requestRevision.load())flightOutcome=@"request_changed";
        else flightOutcome=@"waiting_ridden_vehicle";
    }
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(now-lastLog>=1){lastLog=now;record(@"game_task_returned");}
}
}

@interface FanProIntegratedPanel : UIView
@property(nonatomic,strong) UIButton *launcher;
@property(nonatomic,strong) UIStackView *content;
@property(nonatomic,strong) UIScrollView *card;
@property(nonatomic,strong) UISwitch *speed;
@property(nonatomic,strong) UISwitch *flight;
@property(nonatomic,strong) UILabel *multiplierLabel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation FanProIntegratedPanel
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.launcher=[UIButton buttonWithType:UIButtonTypeSystem];[self.launcher setTitle:@"F" forState:UIControlStateNormal];
        self.launcher.frame=CGRectMake(40,70,48,48);self.launcher.backgroundColor=UIColor.systemTealColor;
        [self.launcher setTitleColor:UIColor.blackColor forState:UIControlStateNormal];self.launcher.layer.cornerRadius=24;
        [self.launcher addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [self.launcher addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];[self addSubview:self.launcher];
        self.content=[UIStackView new];self.content.axis=UILayoutConstraintAxisVertical;self.content.spacing=10;
        self.content.layoutMargins=UIEdgeInsetsMake(14,14,14,14);self.content.layoutMarginsRelativeArrangement=YES;
        self.card=[UIScrollView new];self.card.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.95];self.card.layer.cornerRadius=16;self.card.hidden=YES;
        [self.card addSubview:self.content];[self addSubview:self.card];[self bringSubviewToFront:self.launcher];
        UILabel *(^label)(NSString *)=^UILabel *(NSString *text){UILabel *l=[UILabel new];l.text=text;l.textColor=UIColor.whiteColor;l.numberOfLines=0;l.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];l.adjustsFontForContentSizeCategory=YES;return l;};
        [self.content addArrangedSubview:label(@"FanProMAX · 内置试验 i4")];
        UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionEqualSpacing;
        [row addArrangedSubview:label(@"人物加速（待实测）")];self.speed=[UISwitch new];self.speed.enabled=ready;
        [self.speed addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:self.speed];
        [self.content addArrangedSubview:row];
        self.multiplierLabel=label(@"请求倍率 1.0×");[self.content addArrangedSubview:self.multiplierLabel];
        UISlider *slider=[UISlider new];slider.minimumValue=1;slider.maximumValue=3;slider.value=1;
        [slider addTarget:self action:@selector(multiplierChanged:) forControlEvents:UIControlEventValueChanged];[self.content addArrangedSubview:slider];
        self.status=label(@"字段写入与实际对局速度分别验证");[self.content addArrangedSubview:self.status];
        UIStackView *flightRow=[UIStackView new];flightRow.axis=UILayoutConstraintAxisHorizontal;flightRow.distribution=UIStackViewDistributionEqualSpacing;
        [flightRow addArrangedSubview:label(@"飞车（待实测）")];self.flight=[UISwitch new];self.flight.enabled=ready;
        [self.flight addTarget:self action:@selector(flightChanged:) forControlEvents:UIControlEventValueChanged];[flightRow addArrangedSubview:self.flight];[self.content addArrangedSubview:flightRow];
        UISegmentedControl *vertical=[[UISegmentedControl alloc] initWithItems:@[@"下降",@"悬停",@"上升"]];vertical.selectedSegmentIndex=1;
        [vertical addTarget:self action:@selector(verticalChanged:) forControlEvents:UIControlEventValueChanged];[self.content addArrangedSubview:vertical];
        [self.content addArrangedSubview:label(@"无敌与减伤：尚未实现\n自瞄与压枪：不包含")];
        UIButton *share=[UIButton buttonWithType:UIButtonTypeSystem];[share setTitle:@"导出诊断" forState:UIControlStateNormal];
        [share addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside];[self.content addArrangedSubview:share];
        __weak FanProIntegratedPanel *weak=self;
        self.timer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer){(void)timer;[weak tick];}];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
    }return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {UIView *hit=[super hitTest:point withEvent:event];return hit==self ? nil : hit;}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat width=MIN(290,self.bounds.size.width-24);
    self.launcher.center=CGPointMake(MAX(30,MIN(self.bounds.size.width-30,self.launcher.center.x)),MAX(30,MIN(self.bounds.size.height-30,self.launcher.center.y)));
    CGSize size=[self.content systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat visibleHeight=MIN(size.height,self.bounds.size.height-24);
    self.card.frame=CGRectMake(MAX(12,MIN(self.bounds.size.width-width-12,self.launcher.frame.origin.x)),MAX(12,MIN(self.bounds.size.height-visibleHeight-12,self.launcher.frame.origin.y+54)),width,visibleHeight);
    self.content.frame=CGRectMake(0,0,width,size.height);self.card.contentSize=size;
}
- (void)togglePanel {self.card.hidden=!self.card.hidden;[self setNeedsLayout];}
- (void)drag:(UIPanGestureRecognizer *)pan {CGPoint p=[pan translationInView:self];self.launcher.center=CGPointMake(self.launcher.center.x+p.x,self.launcher.center.y+p.y);[pan setTranslation:CGPointZero inView:self];[self setNeedsLayout];}
- (void)speedChanged:(UISwitch *)sender {if(!ready){sender.on=NO;return;}speedRequested.store(sender.on);++requestRevision;}
- (void)flightChanged:(UISwitch *)sender {if(!ready){sender.on=NO;return;}flightRequested.store(sender.on);++requestRevision;}
- (void)verticalChanged:(UISegmentedControl *)sender {flightDirection.store(int(sender.selectedSegmentIndex)-1);++requestRevision;}
- (void)multiplierChanged:(UISlider *)sender {unsigned value=unsigned(std::round(sender.value*10));speedTenths.store(value);self.multiplierLabel.text=[NSString stringWithFormat:@"请求倍率 %.1f×",value/10.0];++requestRevision;}
- (void)background {speedRequested.store(false);flightRequested.store(false);++requestRevision;self.speed.on=NO;self.flight.on=NO;[self tick];}
- (void)tick {
    if(!ready || pendingTask.exchange(true))return;
    Class cls=objc_getClass("FIOSAsyncTask");
    if(!validTaskClass(cls)){pendingTask.store(false);self.status.text=@"游戏任务接口不匹配，未修改";return;}
    uint64_t revision=requestRevision.load();__weak FanProIntegratedPanel *weak=self;
    bool (^block)(void)=^bool {
        @autoreleasepool {perform(revision);NSString *outcome=[NSString stringWithFormat:@"人物：%@\n载具：%@",lastOutcome,flightOutcome];BOOL requested=speedRequested.load(),flying=flightRequested.load();
            dispatch_async(dispatch_get_main_queue(),^{FanProIntegratedPanel *panel=weak;if(panel){panel.speed.on=requested;panel.flight.on=flying;panel.status.text=outcome;[panel setNeedsLayout];}pendingTask.store(false);});}
        return true;
    };
    reinterpret_cast<void (*)(id,SEL,bool (^)(void))>(objc_msgSend)(cls,sel_registerName("CreateTaskWithBlock:"),block);
}
- (void)share {
    UIViewController *controller=self.window.rootViewController;while(controller.presentedViewController)controller=controller.presentedViewController;
    NSURL *file=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"integrated-status.json"]];
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.launcher;share.popoverPresentationController.sourceRect=self.launcher.bounds;
    [controller presentViewController:share animated:YES completion:nil];
}
@end

[[maybe_unused]] static void FanProStart(void) {
    folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FanProMAX"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSBundle *bundle=NSBundle.mainBundle;
    ready=[bundle.bundleIdentifier isEqual:@"com.pubg.newstate"] && [bundle.infoDictionary[@"CFBundleShortVersionString"] isEqual:@"0.9.98"] &&
        [bundle.infoDictionary[@"CFBundleVersion"] isEqual:@"804"] && identify();
    if(!ready)profileError=@"游戏版本或UUID不匹配";
    if(ready && !fanpro::verifyProfile(memory)){ready=NO;profileError=@"原生接口指纹不匹配";}
    record(@"module_loaded");
    static FanProIntegratedPanel *panel;
    [[maybe_unused]] static NSTimer *attachTimer;
    attachTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        (void)timer;UIWindow *window=nil;
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive)
            for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow)window=candidate;
        if(!window)return;
        if(!panel)panel=[[FanProIntegratedPanel alloc] initWithFrame:window.bounds];
        if(panel.superview!=window){panel.frame=window.bounds;[window addSubview:panel];}
        [window bringSubviewToFront:panel];
    }];
}
#ifndef FANPRO_UI_PREVIEW
__attribute__((constructor)) static void FanProEntry(void){dispatch_async(dispatch_get_main_queue(),^{FanProStart();});}
#else
@interface FanProPreviewDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation FanProPreviewDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app;(void)options;self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller=[UIViewController new];controller.view.backgroundColor=UIColor.darkGrayColor;self.window.rootViewController=controller;
    FanProIntegratedPanel *panel=[[FanProIntegratedPanel alloc] initWithFrame:self.window.bounds];panel.card.hidden=NO;[controller.view addSubview:panel];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        NSMutableArray *failures=[NSMutableArray array];
        void (^check)(BOOL,NSString *)=^(BOOL value,NSString *name){if(!value)[failures addObject:name];};
        [panel layoutIfNeeded];
        check(!panel.speed.enabled && !panel.flight.enabled && !panel.speed.on && !panel.flight.on,@"unverified profile cannot enable changes");
        panel.speed.on=YES;[panel speedChanged:panel.speed];check(!speedRequested.load() && !panel.speed.on,@"programmatic request cannot bypass profile gating");
        [panel.launcher sendActionsForControlEvents:UIControlEventTouchUpInside];check(panel.card.hidden,@"launcher collapses panel");
        [panel.launcher sendActionsForControlEvents:UIControlEventTouchUpInside];check(!panel.card.hidden,@"launcher reopens panel");
        for(NSValue *value in @[[NSValue valueWithCGSize:CGSizeMake(852,393)],[NSValue valueWithCGSize:CGSizeMake(393,852)]]) {
            panel.frame=(CGRect){CGPointZero,value.CGSizeValue};[panel setNeedsLayout];[panel layoutIfNeeded];
            check(CGRectContainsRect(panel.bounds,panel.card.frame),@"panel fits landscape and portrait");
            check(panel.card.contentSize.height>=panel.card.bounds.size.height,@"overflow content remains scrollable");
            check([panel hitTest:CGPointMake(panel.bounds.size.width-2,panel.bounds.size.height-2) withEvent:nil]==nil,@"gameplay area passes through touches");
        }
        panel.frame=self.window.bounds;[panel setNeedsLayout];[panel layoutIfNeeded];
        NSDictionary *report=@{@"passed":@(failures.count==0),@"failures":failures,@"scope":@"Simulator UIKit profile gating, panel actions, portrait/landscape scrolling and touch passthrough; no game or native physics invoked"};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"integrated-ui.json"] atomically:YES];
    });return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(FanProPreviewDelegate.class));}}
#endif
