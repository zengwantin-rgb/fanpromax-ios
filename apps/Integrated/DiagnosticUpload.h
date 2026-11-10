#import <Foundation/Foundation.h>

// Main-thread API. Consumes only the module's serialized diagnostics, never arbitrary memory/files.
@interface FanProDiagnosticUpload : NSObject <NSURLSessionDataDelegate>
@property(nonatomic,readonly) BOOL enabled;
@property(nonatomic,readonly) BOOL configured;
@property(nonatomic,copy,readonly) NSString *status;
+ (instancetype)shared;
+ (NSDictionary *)parsePairing:(NSString *)text;
- (BOOL)configurePairing:(NSString *)text;
- (void)setUploading:(BOOL)enabled;
- (void)setForeground:(BOOL)foreground;
- (void)offerSnapshot:(NSData *)snapshot;
- (void)forgetPairing;
@end
