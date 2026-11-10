#import "DiagnosticUpload.h"
#include <cstdlib>

static unsigned requests;
static NSString *mode=@"valid";
static BOOL requestValid=YES;
@interface SyntheticProtocol : NSURLProtocol @end
@implementation SyntheticProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {(void)request;return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {
    ++requests;
    NSData *body=self.request.HTTPBody;
    if(!body && self.request.HTTPBodyStream){NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *read=[NSMutableData data];uint8_t buffer[4096];NSInteger n;while((n=[stream read:buffer maxLength:sizeof buffer])>0)[read appendBytes:buffer length:n];[stream close];body=read;}
    NSDictionary *envelope=body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
    requestValid=requestValid && [self.request.HTTPMethod isEqual:@"POST"] && self.request.URL.fragment==nil && [[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:[@"Bearer " stringByAppendingString:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]]] && [envelope[@"schema"] isEqual:@1];
    BOOL denied=[mode isEqual:@"denied"],wrong=[mode isEqual:@"wrong"];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:denied ? 401 : 201 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"accepted":@YES,@"report_id":wrong ? @"mismatch" : envelope[@"report_id"]?:@"",@"probe":@NO} options:0 error:nil];
    if([mode isEqual:@"large"])data=[NSMutableData dataWithLength:5000];
    [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void check(BOOL passed,const char *name){if(!passed){fprintf(stderr,"FAIL: %s\n",name);std::exit(1);}}
static void finish(FanProDiagnosticUpload *u) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];
    while([u valueForKey:@"task"] && limit.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check([u valueForKey:@"task"]==nil,"network attempt completed");
}
int main(){@autoreleasepool {
    check([NSProcessInfo.processInfo.environment[@"RUNNER_ENVIRONMENT"] isEqual:@"github-hosted"],"hosted only");
    NSString *token=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *pair=[@"https://diagnostics.invalid/v1/diagnostics#" stringByAppendingString:token];
    check([FanProDiagnosticUpload parsePairing:pair]!=nil,"valid pairing");
    for(NSString *bad in @[@"http://diagnostics.invalid/v1/diagnostics#",@"https://user@diagnostics.invalid/v1/diagnostics#",@"https://diagnostics.invalid/other#",@"https://diagnostics.invalid/v1/diagnostics?x=y#"])
        check([FanProDiagnosticUpload parsePairing:[bad stringByAppendingString:token]]==nil,"reject insecure or ambiguous destination");
    FanProDiagnosticUpload *u=[FanProDiagnosticUpload new];check(!u.enabled,"default off");
    [u setValue:[FanProDiagnosticUpload parsePairing:pair] forKey:@"pairing"];[u setValue:@YES forKey:@"configured"];
    NSURLSession *old=[u valueForKey:@"session"];[old invalidateAndCancel];
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.protocolClasses=@[SyntheticProtocol.class];
    NSURLSession *session=[NSURLSession sessionWithConfiguration:config delegate:u delegateQueue:NSOperationQueue.mainQueue];[u setValue:session forKey:@"session"];
    NSData *snapshot=[NSJSONSerialization dataWithJSONObject:@{@"version":@"integrated-test",@"time":@1} options:0 error:nil];
    [u offerSnapshot:snapshot];check(requests==0,"no request while disabled");
    [u setUploading:YES];finish(u);check([u.status hasPrefix:@"服务器已接收"] && requestValid,"acknowledged matching report");
    unsigned count=requests;[u offerSnapshot:snapshot];check(requests==count,"five second throttle");
    [u setForeground:NO];[u setValue:@0 forKey:@"nextAttempt"];[u offerSnapshot:snapshot];check(requests==count,"background does not send");
    [u setForeground:YES];mode=@"wrong";[u offerSnapshot:snapshot];finish(u);check([u.status hasPrefix:@"未收到有效回执"],"reject mismatched report ACK");
    mode=@"large";[u setValue:@0 forKey:@"nextAttempt"];[u offerSnapshot:snapshot];finish(u);check([u.status hasPrefix:@"未收到有效回执"],"bounded response");
    mode=@"denied";[u setValue:@0 forKey:@"nextAttempt"];[u offerSnapshot:snapshot];finish(u);check(!u.enabled,"invalid credential disables upload");
    __block BOOL deniedRedirect=NO;
    NSURL *redirectURL=[NSURL URLWithString:@"https://elsewhere.invalid"];
    NSURLSessionDataTask *redirectTask=[session dataTaskWithURL:redirectURL];
    NSHTTPURLResponse *redirectResponse=[[NSHTTPURLResponse alloc] initWithURL:redirectURL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [u URLSession:session task:redirectTask willPerformHTTPRedirection:redirectResponse newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://elsewhere.invalid"]] completionHandler:^(NSURLRequest *request){deniedRedirect=request==nil;}];
    [redirectTask cancel];
    check(deniedRedirect,"no credentials forwarded through redirects");
    [session invalidateAndCancel];puts("PASS: pairing, no unsolicited transmission, authenticated payload, ACK identity, throttle, background pause, bounded replies and redirect refusal");
}return 0;}
