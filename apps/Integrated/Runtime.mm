#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include "CollisionRuntimeRead.hpp"
#include "FieldLease.hpp"
#include "FlightLease.hpp"
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
bool restoringFields{};uint64_t writeRevision{};
std::atomic<unsigned> speedTenths{10};
std::atomic<bool> pendingTask{false};
std::atomic<uint64_t> requestRevision{0};
fanpro::FieldLease walkLease,crouchLease;
uint64_t currentWorld{};
NSString *lastOutcome=@"尚未修改";
NSString *profileError;
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
    if(!restoringFields && (!speedRequested.load() || writeRevision!=requestRevision.load()))return false;
    return vm_write(mach_task_self(),address,reinterpret_cast<vm_offset_t>(&value),sizeof value)==KERN_SUCCESS;
}
fanpro::Access fieldAccess{nullptr,live,readFloat,writeFloat};
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
    return live(nullptr,key) && isA(memory,memory.encodedPointer(key.object+0x30),memory.pointer(memory.base+0x80b05a8)) &&
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
static bool currentVehicle(const CollisionContext &target,fanpro::Identity &root) {
    uint64_t rider=memory.pointer(target.pawn+0x1a88),owner=rider ? memory.pointer(rider+0xa0) : 0;
    uint64_t pawnRoot=owner ? memory.pointer(owner+0x278) : 0,parent=pawnRoot ? memory.pointer(pawnRoot+0x230) : 0;
    uint64_t vehicle=parent ? memory.pointer(parent+0xa0) : 0;
    bool vehicleType=false;
    for(uint64_t slot:{0x7f8b4a0ULL,0x7f33a70ULL,0x7f33b00ULL,0x7f195c8ULL})
        if(vehicle && isA(memory,memory.encodedPointer(vehicle+0x30),memory.pointer(memory.base+slot)))vehicleType=true;
    if(!vehicleType || owner!=target.pawn)return false;
    uint64_t component=memory.pointer(vehicle+0x278);
    if(!identity(component,target.world,root) || !primitive(root))return false;
    return memory.pointer(target.pawn+0x1a88)==rider && memory.pointer(rider+0xa0)==owner &&
        memory.pointer(owner+0x278)==pawnRoot && memory.pointer(pawnRoot+0x230)==parent &&
        memory.pointer(parent+0xa0)==vehicle && memory.pointer(vehicle+0x278)==component;
}
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
    NSDictionary *value=@{@"version":@"integrated-i1",@"phase":phase,@"time":@(NSDate.date.timeIntervalSince1970),
        @"profile_ready":@(ready),@"profile_error":profileError?:@"",@"speed_requested":@(speedRequested.load()),
        @"selected_multiplier":@(speedTenths.load()/10.0),@"speed_field_outcome":lastOutcome?:@"",
        @"flight_requested":@(flightRequested.load()),@"flight_outcome":flightOutcome?:@"",
        @"flight_calls":@(flightCalls),@"flight_lease_active":@(flightLease.active()),
        @"invincibility_implemented":@NO,@"damage_reduction_implemented":@NO,
        @"task_count":@(taskCount),@"speed_field_writes_confirmed":@(speedWrites),
        @"walking_lease_active":@(walkLease.active()),@"crouching_lease_active":@(crouchLease.active()),
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
static void perform(uint64_t revision) {
    ++taskCount;writeRevision=revision;restoringFields=false;CollisionContext target;
    const auto observation=observeCollision(memory,textBegin,textEnd,&target);
    currentWorld=target.world;
    uint8_t dead{};
    bool valid=observation.stage==CollisionObservation::Stage::ready && target.generationsValid &&
        target.pawn && memory.get(target.pawn+0x930,dead) && !(dead&1);
    bool wanted=speedRequested.load() && revision==requestRevision.load() && valid && observation.movementMode==1;
    if(!wanted) {
        restoringFields=true;auto a=walkLease.restore(fieldAccess),b=crouchLease.restore(fieldAccess);
        lastOutcome=valid ? [NSString stringWithFormat:@"%s / %s",resultName(a),resultName(b)] : @"等待有效步行角色";
    } else {
        fanpro::Identity key{target.movement,target.items[1],target.world,target.serials[1]};
        float multiplier=speedTenths.load()/10.0f;
        auto a=walkLease.apply(fieldAccess,key,0x6dc,multiplier);
        auto b=failed(a) ? fanpro::FieldResult::off : crouchLease.apply(fieldAccess,key,0x420,multiplier);
        if(a==fanpro::FieldResult::applied)++speedWrites;
        if(b==fanpro::FieldResult::applied)++speedWrites;
        lastOutcome=[NSString stringWithFormat:@"%s / %s",resultName(a),resultName(b)];
        if(failed(a) || failed(b)) {speedRequested.store(false);restoringFields=true;walkLease.restore(fieldAccess);crouchLease.restore(fieldAccess);}
    }
    fanpro::Identity vehicleRoot;
    bool flightWanted=flightRequested.load() && revision==requestRevision.load() && valid;
    if(flightWanted && currentVehicle(target,vehicleRoot)) {
        auto result=flightLease.apply(physics,vehicleRoot,flightDirection.load());flightOutcome=@(resultName(result));
        if(failed(result)){flightRequested.store(false);flightLease.restore(physics);}
    } else {
        auto result=flightLease.restore(physics);
        flightOutcome=flightWanted ? @"等待当前乘坐载具" : @(resultName(result));
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
        [self.content addArrangedSubview:label(@"FanProMAX · 内置试验 i1")];
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
            dispatch_async(dispatch_get_main_queue(),^{FanProIntegratedPanel *panel=weak;if(panel){panel.speed.on=requested;panel.flight.on=flying;panel.status.text=outcome;}pendingTask.store(false);});}
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
