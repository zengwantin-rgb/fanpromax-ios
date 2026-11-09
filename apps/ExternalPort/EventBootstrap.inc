// Event dispatcher/fetcher setup adapted from Lessica/TrollSpeed (MIT), pinned
// a609be260c8261ead36509c3bc4ded8479da9c40/sources/HUDMainApplication.mm.
// Operates only on our own UIApplication/UIKit; no game calls, hooks or input injection.
static void *NSPReadableCode(void *pointer) {
#if defined(__arm64e__)
    return pointer ? ptrauth_strip(pointer,ptrauth_key_function_pointer) : nullptr;
#else
    return pointer;
#endif
}
static void *NSPCallableCode(void *pointer) {
#if defined(__arm64e__)
    return pointer ? ptrauth_sign_unauthenticated(ptrauth_strip(pointer,ptrauth_key_function_pointer),ptrauth_key_function_pointer,0) : nullptr;
#else
    return pointer;
#endif
}
static bool NSPReadOwnCode(void *,uintptr_t address,void *output,size_t size) {
    vm_size_t copied{};
    return vm_read_overwrite(mach_task_self(),vm_address_t(address),vm_size_t(size),vm_address_t(output),&copied)==KERN_SUCCESS && copied==size;
}
static bool NSPUIKitImage(void *,uintptr_t run,uintptr_t target) {
    Dl_info a{},b{};
    if(!dladdr((const void *)run,&a) || !dladdr((const void *)target,&b) || a.dli_fbase!=b.dli_fbase || !a.dli_fname)return false;
    return std::strstr(a.dli_fname,"/UIKitCore.framework/") || std::strstr(a.dli_fname,"/UIKit.framework/");
}
static void NSPPrepareHUDInput(id application,Class fetcherClass,BOOL allowRuntimeLookup) {
    NSPEventLoopPrepared=NO;NSMutableDictionary *report=[NSMutableDictionary dictionary];BOOL installed=NO,fetcherReady=NO;
    @try {
        id dispatcher=[application valueForKey:@"eventDispatcher"];
        report[@"dispatcher_available"]=@(dispatcher!=nil);
        if(!dispatcher) {report[@"reason"]=@"dispatcher_missing";NSPEventBootstrapReport=report;return;}
        SEL install=NSSelectorFromString(@"_installEventRunLoopSources:");
        if([dispatcher respondsToSelector:install]) {
            NSMethodSignature *signature=[dispatcher methodSignatureForSelector:install];
            if(signature.numberOfArguments==3 && !std::strcmp(signature.methodReturnType,@encode(void))) {
                NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];CFRunLoopRef loop=CFRunLoopGetMain();
                call.target=dispatcher;call.selector=install;[call setArgument:&loop atIndex:2];[call invoke];installed=YES;
                report[@"runloop_path"]=@"selector";
            } else report[@"runloop_path"]=@"selector_signature_invalid";
        } else if(allowRuntimeLookup && [application isKindOfClass:UIApplication.class]) {
            IMP imp=class_getMethodImplementation(UIApplication.class,NSSelectorFromString(@"_run"));
            const auto result=fanport::findEventLoopInstaller((uintptr_t)NSPReadableCode((void *)imp),NSPReadOwnCode,NSPUIKitImage,nullptr);
            report[@"runloop_path"]=@(result.reason);report[@"pattern_candidates"]=@(result.candidates);
            if(result.target) {
                using Install=void (*)(id,SEL,CFRunLoopRef);
                auto invoke=reinterpret_cast<Install>(NSPCallableCode((void *)result.target));
                invoke(dispatcher,install,CFRunLoopGetMain());installed=YES;
            }
        } else report[@"runloop_path"]=@"selector_unavailable";
        // Always set up the fetcher, even when the run-loop selector is hidden.
        id fetcher=fetcherClass ? [fetcherClass new] : nil;
        report[@"fetcher_available"]=@(fetcher!=nil);
        if(fetcher) {
            [dispatcher setValue:fetcher forKey:@"eventFetcher"];
            SEL sink=NSSelectorFromString(@"setEventFetcherSink:");
            if([fetcher respondsToSelector:sink]) {
                NSMethodSignature *signature=[fetcher methodSignatureForSelector:sink];
                if(signature.numberOfArguments!=3 || std::strcmp(signature.methodReturnType,@encode(void)))
                    @throw [NSException exceptionWithName:@"FetcherSignature" reason:nil userInfo:nil];
                NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
                call.target=fetcher;call.selector=sink;[call setArgument:&dispatcher atIndex:2];[call invoke];
            } else [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
            [application setValue:fetcher forKey:@"eventFetcher"];fetcherReady=YES;
        }
    } @catch (__unused NSException *exception) {report[@"reason"]=@"setup_exception";}
    report[@"runloop_installed"]=@(installed);report[@"fetcher_installed"]=@(fetcherReady);
    NSPEventLoopPrepared=installed && fetcherReady;NSPEventBootstrapReport=[report copy];
}
@interface NSPHUDApplication : UIApplication
@end
@implementation NSPHUDApplication
- (instancetype)init {
    if((self=[super init]))NSPPrepareHUDInput(self,NSClassFromString(@"UIEventFetcher"),YES);
    return self;
}
@end
#ifdef NSP_UI_PREVIEW
@interface NSPFetcherMock : NSObject
@property(nonatomic,weak) id eventFetcherSink;
@end
@implementation NSPFetcherMock
@end
@interface NSPDispatcherMock : NSObject
@property(nonatomic,strong) id eventFetcher;
@property(nonatomic) BOOL installed;
- (void)_installEventRunLoopSources:(CFRunLoopRef)loop;
@end
@implementation NSPDispatcherMock
- (void)_installEventRunLoopSources:(CFRunLoopRef)loop {self.installed=loop==CFRunLoopGetMain();}
@end
@interface NSPHiddenDispatcherMock : NSObject
@property(nonatomic,strong) id eventFetcher;
@end
@implementation NSPHiddenDispatcherMock
@end
@interface NSPBootstrapApplicationMock : NSObject
@property(nonatomic,strong) id eventDispatcher;
@property(nonatomic,strong) id eventFetcher;
@end
@implementation NSPBootstrapApplicationMock
@end
#endif
