// Configure only declared Objective-C receiver interfaces after window hosting.
// No system instruction scanning, inferred function pointers or run-loop installer.
static void NSPPrepareHUDInput(id application,Class fetcherClass) {
    NSPEventLoopPrepared=NO;
    NSMutableDictionary *report=[NSPEventBootstrapReport mutableCopy]?:[NSMutableDictionary dictionary];
    report[@"system_code_scanned"]=@NO;report[@"runloop_installer_called"]=@NO;
    report[@"runloop_path"]=@"system_plugin_managed";report[@"fetcher_connected"]=@NO;
    @try {
        id dispatcher=[application valueForKey:@"eventDispatcher"];
        report[@"dispatcher_available"]=@(dispatcher!=nil);
        if(!dispatcher) {report[@"reason"]=@"dispatcher_missing";NSPEventBootstrapReport=[report copy];return;}
        id appFetcher=[application valueForKey:@"eventFetcher"];
        id dispatcherFetcher=[dispatcher valueForKey:@"eventFetcher"];
        if(appFetcher && dispatcherFetcher && appFetcher!=dispatcherFetcher) {
            report[@"reason"]=@"existing_receivers_differ";NSPEventBootstrapReport=[report copy];return;
        }
        id fetcher=appFetcher?:dispatcherFetcher;
        report[@"fetcher_reused"]=@(fetcher!=nil);
        if(!fetcher && fetcherClass) {fetcher=[fetcherClass new];report[@"fetcher_created"]=@(fetcher!=nil);}
        if(fetcher) {
            id existingSink=[fetcher valueForKey:@"eventFetcherSink"];
            if(existingSink && existingSink!=dispatcher) {
                report[@"reason"]=@"existing_sink_differs";NSPEventBootstrapReport=[report copy];return;
            }
            if(!existingSink) {
                SEL sink=NSSelectorFromString(@"setEventFetcherSink:");
                NSMethodSignature *signature=[fetcher methodSignatureForSelector:sink];
                if(signature.numberOfArguments!=3 || std::strcmp(signature.methodReturnType,@encode(void)) ||
                   std::strcmp([signature getArgumentTypeAtIndex:2],@encode(id))) {
                    report[@"reason"]=@"sink_interface_unavailable";NSPEventBootstrapReport=[report copy];return;
                }
                NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
                call.target=fetcher;call.selector=sink;[call setArgument:&dispatcher atIndex:2];[call invoke];
            }
            if(!dispatcherFetcher)[dispatcher setValue:fetcher forKey:@"eventFetcher"];
            if(!appFetcher)[application setValue:fetcher forKey:@"eventFetcher"];
            report[@"fetcher_connected"]=@YES;report[@"reason"]=@"receiver_connected_device_delivery_unverified";
        } else report[@"reason"]=@"fetcher_unavailable";
    } @catch (__unused NSException *exception) {report[@"reason"]=@"receiver_setup_exception";}
    NSPEventBootstrapReport=[report copy];
}
#ifdef NSP_UI_PREVIEW
@interface NSPFetcherMock : NSObject
@property(nonatomic,weak) id eventFetcherSink;
@end
@implementation NSPFetcherMock
@end
@interface NSPDispatcherMock : NSObject
@property(nonatomic,strong) id eventFetcher;
@end
@implementation NSPDispatcherMock
@end
@interface NSPBootstrapApplicationMock : NSObject
@property(nonatomic,strong) id eventDispatcher;
@property(nonatomic,strong) id eventFetcher;
@end
@implementation NSPBootstrapApplicationMock
@end
#endif
