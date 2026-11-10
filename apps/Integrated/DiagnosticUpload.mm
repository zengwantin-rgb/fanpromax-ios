#import "DiagnosticUpload.h"
#import <Security/Security.h>

@interface FanProDiagnosticUpload ()
@property(nonatomic,readwrite) BOOL enabled;
@property(nonatomic,readwrite) BOOL configured;
@property(nonatomic,copy,readwrite) NSString *status;
@property(nonatomic) BOOL foreground;
@property(nonatomic,copy) NSDictionary *pairing;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSData *latest;
@property(nonatomic,strong) NSMutableData *reply;
@property(nonatomic,copy) NSString *sessionID;
@property(nonatomic,copy) NSString *reportID;
@property(nonatomic) NSTimeInterval nextAttempt;
@property(nonatomic) unsigned failures;
@end

@implementation FanProDiagnosticUpload
+ (instancetype)shared {static FanProDiagnosticUpload *value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value;}
+ (NSDictionary *)parsePairing:(NSString *)text {
    if(![text isKindOfClass:NSString.class] || text.length>2048)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    NSString *token=parts.fragment;
    if(![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length || parts.user || parts.password || parts.query || ![parts.path isEqual:@"/v1/diagnostics"] || token.length!=64)return nil;
    NSCharacterSet *hex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    if([token rangeOfCharacterFromSet:hex.invertedSet].location!=NSNotFound)return nil;
    parts.fragment=nil;
    NSURL *url=parts.URL;if(!url)return nil;
    return @{@"endpoint":url.absoluteString,@"token":token};
}
- (NSMutableDictionary *)keychainQuery {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"io.github.zengwantin.fanpro.diagnostics.v1",
        (__bridge id)kSecAttrAccount:@"upload-pairing"} mutableCopy];
}
- (instancetype)init {
    if((self=[super init])) {
        self.status=@"未配对 · 自动回传已关闭";self.foreground=YES;self.sessionID=NSUUID.UUID.UUIDString;
        NSMutableDictionary *query=[self keychainQuery];query[(__bridge id)kSecReturnData]=@YES;
        CFTypeRef found=NULL;
        if(SecItemCopyMatching((__bridge CFDictionaryRef)query,&found)==errSecSuccess) {
            NSData *data=CFBridgingRelease(found);NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            self.pairing=[self.class parsePairing:text];self.configured=self.pairing!=nil;
            if(self.configured)self.status=@"已配对 · 自动回传已关闭";
        }
        NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.URLCache=nil;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;
        config.HTTPShouldSetCookies=NO;config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
        config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=20;config.HTTPMaximumConnectionsPerHost=1;
        self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }return self;
}
- (void)cancelUpload { [self.task cancel];self.task=nil;self.reply=nil;self.reportID=nil; }
- (BOOL)configurePairing:(NSString *)text {
    NSDictionary *pairing=[self.class parsePairing:text];
    if(!pairing){self.status=@"配对串无效，需要完整的 HTTPS 地址和密钥";return NO;}
    NSString *normalized=[NSString stringWithFormat:@"%@#%@",pairing[@"endpoint"],pairing[@"token"]];
    NSData *data=[normalized dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *query=[self keychainQuery];
    NSDictionary *values=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)values);
    if(result==errSecItemNotFound){[query addEntriesFromDictionary:values];result=SecItemAdd((__bridge CFDictionaryRef)query,NULL);}
    if(result!=errSecSuccess){self.status=@"无法安全保存配对，请检查安装签名";return NO;}
    [self cancelUpload];self.enabled=NO;self.pairing=pairing;self.configured=YES;self.failures=0;self.nextAttempt=0;
    self.status=@"已配对 · 开启回传后发送诊断";return YES;
}
- (void)setUploading:(BOOL)enabled {
    self.enabled=enabled && self.configured;[self cancelUpload];self.failures=0;self.nextAttempt=0;
    self.status=self.enabled ? @"等待游戏诊断数据" : (self.configured ? @"已暂停回传" : @"请先设置配对串");
    [self pump];
}
- (void)setForeground:(BOOL)foreground {
    _foreground=foreground;
    if(!foreground){[self cancelUpload];if(self.enabled)self.status=@"游戏不在前台 · 回传暂停";}
    else if(self.enabled){self.nextAttempt=0;self.status=@"等待新的游戏诊断";}
}
- (void)offerSnapshot:(NSData *)snapshot {
    if(!snapshot.length || snapshot.length>450*1024)return;
    self.latest=[snapshot copy];[self pump];
}
- (void)forgetPairing {
    [self setUploading:NO];SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    self.pairing=nil;self.configured=NO;self.latest=nil;self.status=@"已解除配对";
}
- (void)pump {
    if(!self.enabled || !self.foreground || !self.latest || self.task || NSProcessInfo.processInfo.systemUptime<self.nextAttempt)return;
    NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:self.latest options:0 error:nil];
    if(![snapshot isKindOfClass:NSDictionary.class])return;
    self.reportID=NSUUID.UUID.UUIDString;
    NSDictionary *envelope=@{@"schema":@1,@"report_id":self.reportID,@"session_id":self.sessionID,@"snapshot":snapshot};
    NSData *body=[NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    if(!body || body.length>512*1024)return;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.pairing[@"endpoint"]]];
    request.HTTPMethod=@"POST";request.HTTPBody=body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:self.pairing[@"token"]] forHTTPHeaderField:@"Authorization"];
    self.reply=[NSMutableData data];self.task=[self.session dataTaskWithRequest:request];
    self.status=@"正在回传诊断…";[self.task resume];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session;(void)task;(void)response;(void)request;completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;if(task!=self.task)return;
    if(self.reply.length+data.length>4096){[task cancel];return;}[self.reply appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;if(task!=self.task)return;
    NSInteger code=[task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    NSDictionary *reply=self.reply.length ? [NSJSONSerialization JSONObjectWithData:self.reply options:0 error:nil] : nil;
    BOOL accepted=!error && code==201 && [reply isKindOfClass:NSDictionary.class] && [reply[@"accepted"] isEqual:@YES] && [reply[@"report_id"] isEqual:self.reportID] && [reply[@"probe"] isEqual:@NO];
    self.task=nil;self.reply=nil;self.reportID=nil;
    if(accepted){self.failures=0;self.nextAttempt=NSProcessInfo.processInfo.systemUptime+5;NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"HH:mm:ss";self.status=[@"服务器已接收 " stringByAppendingString:[format stringFromDate:NSDate.date]];}
    else if(code==401 || code==403){self.enabled=NO;self.status=@"配对已失效 · 回传关闭";}
    else {self.failures=MIN(self.failures+1,4u);unsigned delay=MIN(5u<<self.failures,60u);self.nextAttempt=NSProcessInfo.processInfo.systemUptime+delay;self.status=[NSString stringWithFormat:@"未收到有效回执 · %u 秒后重试",delay];}
}
@end
