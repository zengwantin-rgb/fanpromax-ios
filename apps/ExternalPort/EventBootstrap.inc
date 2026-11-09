// Configure only declared Objective-C receiver interfaces after window hosting.
// No system instruction scanning, inferred function pointers or run-loop installer.
static const char *NSPUnqualifiedType(const char *type) {
    if(!type)return "";
    while(*type && std::strchr("rnNoORV",*type))++type;
    return type;
}
static BOOL NSPObjectType(const char *type) {
    const char *base=NSPUnqualifiedType(type);
    if(base[0]!='@')return NO;
    if(!base[1])return YES;
    // Objective-C retains optional class/protocol names in method and ivar metadata.
    if(base[1]!='"')return NO; // Blocks (@?) and pointers are not receiver objects.
    size_t length=std::strlen(base);
    return length>=3 && base[length-1]=='"' && std::strchr(base+2,'"')==base+length-1;
}
static BOOL NSPSinkSignature(NSMethodSignature *signature) {
    return signature && signature.numberOfArguments==3 &&
        !std::strcmp(NSPUnqualifiedType(signature.methodReturnType),@encode(void)) &&
        NSPObjectType([signature getArgumentTypeAtIndex:2]);
}
static NSString *NSPTypeLabel(const char *type) {
    if(!type)return @"unavailable";
    return [[NSString alloc] initWithBytes:type length:strnlen(type,160) encoding:NSUTF8StringEncoding]?:@"invalid_encoding";
}
static BOOL NSPConnectSink(id fetcher,id dispatcher,NSMutableDictionary *report) {
    SEL setter=NSSelectorFromString(@"setEventFetcherSink:");
    BOOL available=[fetcher respondsToSelector:setter];
    report[@"sink_setter_available"]=@(available);
    if(available) {
        NSMethodSignature *signature=[fetcher methodSignatureForSelector:setter];
        report[@"sink_argument_count"]=@(signature.numberOfArguments);
        report[@"sink_return_type"]=NSPTypeLabel(signature.methodReturnType);
        if(signature.numberOfArguments>2)report[@"sink_argument_type"]=NSPTypeLabel([signature getArgumentTypeAtIndex:2]);
        if(!NSPSinkSignature(signature)) {report[@"reason"]=@"sink_signature_incompatible";return NO;}
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:signature];
        call.target=fetcher;call.selector=setter;[call setArgument:&dispatcher atIndex:2];[call invoke];
        report[@"sink_connection_path"]=@"declared_setter";
    } else {
        // KVC fallback is limited to an existing object-typed field on our own receiver.
        Ivar slot=class_getInstanceVariable(object_getClass(fetcher),"_eventFetcherSink");
        if(!slot)slot=class_getInstanceVariable(object_getClass(fetcher),"eventFetcherSink");
        const char *type=slot ? ivar_getTypeEncoding(slot) : nullptr;
        report[@"sink_ivar_type"]=NSPTypeLabel(type);
        if(!NSPObjectType(type)) {report[@"reason"]=@"sink_object_ivar_unavailable";return NO;}
        [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
        report[@"sink_connection_path"]=@"object_ivar_kvc";
    }
    BOOL confirmed=[fetcher valueForKey:@"eventFetcherSink"]==dispatcher;
    report[@"sink_readback_confirmed"]=@(confirmed);
    if(!confirmed)report[@"reason"]=@"sink_readback_mismatch";
    return confirmed;
}
static void NSPPrepareHUDInput(id application,Class fetcherClass) {
    NSPEventLoopPrepared=NO;
    // Preserve callback registration facts, but discard any previous receiver attempt's fields.
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    for(NSString *key in @[@"hid_callback_api_found",@"ax_class_available",@"callback_registration_called"])
        if(NSPEventBootstrapReport[key])report[key]=NSPEventBootstrapReport[key];
    report[@"system_code_scanned"]=@NO;report[@"runloop_installer_called"]=@NO;
    report[@"runloop_path"]=@"system_plugin_managed";report[@"fetcher_connected"]=@NO;
    NSString *stage=@"dispatcher_lookup";
    @try {
        id dispatcher=[application valueForKey:@"eventDispatcher"];
        report[@"dispatcher_available"]=@(dispatcher!=nil);
        if(!dispatcher) {report[@"reason"]=@"dispatcher_missing";NSPEventBootstrapReport=[report copy];return;}
        stage=@"fetcher_lookup";
        id appFetcher=[application valueForKey:@"eventFetcher"];
        id dispatcherFetcher=[dispatcher valueForKey:@"eventFetcher"];
        if(appFetcher && dispatcherFetcher && appFetcher!=dispatcherFetcher) {
            report[@"reason"]=@"existing_receivers_differ";NSPEventBootstrapReport=[report copy];return;
        }
        id fetcher=appFetcher?:dispatcherFetcher;
        report[@"fetcher_reused"]=@(fetcher!=nil);
        if(!fetcher && fetcherClass) {stage=@"fetcher_create";fetcher=[fetcherClass new];report[@"fetcher_created"]=@(fetcher!=nil);}
        if(fetcher) {
            report[@"fetcher_class"]=NSStringFromClass(object_getClass(fetcher));
            stage=@"sink_lookup";id existingSink=[fetcher valueForKey:@"eventFetcherSink"];
            if(existingSink && existingSink!=dispatcher) {
                report[@"reason"]=@"existing_sink_differs";NSPEventBootstrapReport=[report copy];return;
            }
            report[@"sink_reused"]=@(existingSink==dispatcher);
            stage=@"sink_connect";
            if(!existingSink && !NSPConnectSink(fetcher,dispatcher,report)) {NSPEventBootstrapReport=[report copy];return;}
            stage=@"dispatcher_connect";if(!dispatcherFetcher)[dispatcher setValue:fetcher forKey:@"eventFetcher"];
            stage=@"application_connect";if(!appFetcher)[application setValue:fetcher forKey:@"eventFetcher"];
            stage=@"receiver_readback";
            BOOL confirmed=[dispatcher valueForKey:@"eventFetcher"]==fetcher && [application valueForKey:@"eventFetcher"]==fetcher;
            report[@"fetcher_connected"]=@(confirmed);
            report[@"reason"]=confirmed ? @"receiver_connected_device_delivery_unverified" : @"receiver_readback_mismatch";
        } else report[@"reason"]=@"fetcher_unavailable";
    } @catch (NSException *exception) {
        report[@"reason"]=@"receiver_setup_exception";report[@"exception_name"]=exception.name?:@"unknown";report[@"exception_stage"]=stage;
    }
    NSPEventBootstrapReport=[report copy];
}
#ifdef NSP_UI_PREVIEW
@interface NSPFetcherMock : NSObject
@property(nonatomic,weak) id eventFetcherSink;
@end
@implementation NSPFetcherMock
@end
@interface NSPQualifiedFetcherMock : NSPFetcherMock
@end
@implementation NSPQualifiedFetcherMock
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(selector==NSSelectorFromString(@"setEventFetcherSink:"))
        return [NSMethodSignature signatureWithObjCTypes:"v24@0:8@\"NSPDispatcherMock\"16"];
    return [super methodSignatureForSelector:selector];
}
@end
@interface NSPKVCSinkMock : NSObject {
@public
    __weak id _eventFetcherSink;
}
@end
@implementation NSPKVCSinkMock
@end
@interface NSPInvalidSinkMock : NSPFetcherMock
@end
@implementation NSPInvalidSinkMock
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(selector==NSSelectorFromString(@"setEventFetcherSink:"))
        return [NSMethodSignature signatureWithObjCTypes:"v24@0:8q16"];
    return [super methodSignatureForSelector:selector];
}
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
