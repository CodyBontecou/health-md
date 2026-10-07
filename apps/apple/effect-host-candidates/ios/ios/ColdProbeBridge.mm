#import "ColdProbeBridge.h"
#import <React/RCTBridgeModule.h>
#import <ReactCommon/RCTHost.h>
#import <React_RCTAppDelegate/RCTRootViewFactory.h>
#import <React/RCTBundleManager.h>
#import <React/RCTDevMenu.h>
#import <UIKit/UIKit.h>
#import <sys/resource.h>

// All mailbox state belongs to main queue; only private fixed values leave this bridge.
@interface ColdRequest : NSObject
@property NSString *ticket;
@property NSString *raw;
@property NSString *caseID;
@property NSInteger sequence;
@property NSTimeInterval expires;
@property BOOL cancelled;
@property BOOL dispatched;
@property (copy) void (^completion)(NSDictionary *);
@end
@implementation ColdRequest
@end
static NSMutableArray<ColdRequest *> *pending;
static ColdRequest *active;
static NSMutableSet<NSString *> *earlyCancels;
static RCTHost *coldHost;
static void (^starter)(void);
static BOOL loading, ready, quarantined;
static NSTimeInterval engineStartedAt;
static void initializeState(void) { if (!pending) { pending = [NSMutableArray new]; earlyCancels = [NSMutableSet new]; } }
static NSDictionary *report(ColdRequest *r, NSString *code, NSInteger acquired, NSInteger released, NSInteger handles, BOOL ack, BOOL incomplete, BOOL credits) {
  return @{ @"schema": @"healthmd.candidate_cold_intent", @"version": @1, @"case_id": r.caseID ?: @"unknown_schema_before_acquire", @"safe_code": code, @"sequence": @(r.sequence), @"acquired": @(acquired), @"released": @(released), @"active": @(handles), @"ack_before_completion": @(ack), @"mounted_react": @NO, @"window_count": @(UIApplication.sharedApplication.windows.count), @"health_permissions": @0, @"health_reads": @0, @"candidate_persistent_writes": @0, @"pid": @(NSProcessInfo.processInfo.processIdentifier), @"invocation_witness": r.ticket, @"incomplete_during_release": @(incomplete), @"synthetic_credit_verified": @(credits) };
}
static void finish(ColdRequest *r, NSString *code, NSInteger acquired, NSInteger released, NSInteger handles, BOOL ack, BOOL incomplete, BOOL credits);
static void drain(void) {
  if (quarantined || active || !pending.count) return;
  ColdRequest *r = pending.firstObject; [pending removeObjectAtIndex:0]; active = r;
  if (r.cancelled) { finish(r, @"cancelled", 0, 0, 0, YES, NO, NO); return; }
  if (NSProcessInfo.processInfo.systemUptime >= r.expires) { finish(r, @"expired", 0, 0, 0, YES, NO, NO); return; }
  if (!loading) { loading = YES; engineStartedAt = NSProcessInfo.processInfo.systemUptime; if (starter) starter(); else { finish(r, @"runtime_unavailable", 0, 0, 0, NO, NO, NO); return; } }
  if (ready && coldHost) { r.dispatched = YES; [coldHost callFunctionOnJSModule:@"CandidateColdProbe" method:@"invoke" args:@[r.ticket, r.raw]]; }
}
static void finish(ColdRequest *r, NSString *code, NSInteger acquired, NSInteger released, NSInteger handles, BOOL ack, BOOL incomplete, BOOL credits) {
  if (!r.completion) return;
  void (^completion)(NSDictionary *) = r.completion; r.completion = nil;
  if (active == r) active = nil; else [pending removeObject:r];
  if (!ack) quarantined = YES; // Never reuse a host with unacknowledged ownership.
  NSDictionary *value = report(r, code, acquired, released, handles, ack, incomplete, credits);
  completion(value); drain();
}
@implementation ColdProbeBridge
+ (void)configureStarter:(void (^)(void))value { NSAssert(NSThread.isMainThread, @"main_queue"); initializeState(); starter = [value copy]; }
+ (void)initializeAndSetHost:(RCTRootViewFactory *)factory {
  NSAssert(NSThread.isMainThread, @"main_queue");
  [factory initializeReactHostWithLaunchOptions:@{}
                            bundleConfiguration:[RCTBundleConfiguration defaultConfiguration]
                           devMenuConfiguration:[RCTDevMenuConfiguration defaultConfiguration]];
  [self setHost:factory.reactHost];
}
+ (void)setHost:(RCTHost *)host { NSAssert(NSThread.isMainThread, @"main_queue"); coldHost = host; }
+ (void)cancelTicket:(NSString *)ticket {
  dispatch_async(dispatch_get_main_queue(), ^{
    initializeState(); ColdRequest *r = active && [active.ticket isEqual:ticket] ? active : nil;
    if (!r) for (ColdRequest *candidate in pending) if ([candidate.ticket isEqual:ticket]) { r = candidate; break; }
    if (!r) { if (earlyCancels.count < 6) [earlyCancels addObject:ticket]; return; }
    r.cancelled = YES;
    if (r.dispatched) [coldHost callFunctionOnJSModule:@"CandidateColdProbe" method:@"cancel" args:@[ticket]];
    else finish(r, @"cancelled", 0, 0, 0, YES, NO, NO);
  });
}
+ (void)startRequest:(NSString *)raw ticket:(NSString *)ticket startedAt:(NSTimeInterval)startedAt cancelled:(BOOL)cancelled completion:(void (^)(NSDictionary *))completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    initializeState(); ColdRequest *r = [ColdRequest new]; r.ticket = ticket; r.completion = completion;
    // No Foundation JSON number conversion: bounded canonical raw tokens only.
    if ([raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 65536) { finish(r, @"frame_limit", 0, 0, 0, YES, NO, NO); return; }
    NSString *pattern = @"\\A\\{\"schema\":\"healthmd\\.candidate_cold_intent\",\"version\":(0|[1-9][0-9]{0,3}),\"case_id\":\"(actual_ingress_no_view|unknown_schema_before_acquire|expiry_before_acquire|cancel_waits_native_ack|restart_no_grant_expansion)\",\"sequence\":(0|[1-9][0-9]{0,3}),\"deadline_milliseconds\":(0|[1-9][0-9]{0,3})\\}\\z";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
    if (!match || ![raw canBeConvertedToEncoding:NSASCIIStringEncoding]) { finish(r, @"schema_invalid", 0, 0, 0, YES, NO, NO); return; }
    NSInteger version = [[raw substringWithRange:[match rangeAtIndex:1]] integerValue];
    r.caseID = [raw substringWithRange:[match rangeAtIndex:2]]; r.sequence = [[raw substringWithRange:[match rangeAtIndex:3]] integerValue];
    NSInteger deadline = [[raw substringWithRange:[match rangeAtIndex:4]] integerValue];
    if (version != 1 || r.sequence > 1023 || deadline > 5000) { finish(r, @"schema_invalid", 0, 0, 0, YES, NO, NO); return; }
    r.raw = raw; r.expires = startedAt + (double)deadline / 1000;
    r.cancelled = cancelled || [earlyCancels containsObject:ticket]; [earlyCancels removeObject:ticket];
    if (NSProcessInfo.processInfo.systemUptime >= r.expires) { finish(r, @"expired", 0, 0, 0, YES, NO, NO); return; }
    if (quarantined) { finish(r, @"runtime_unavailable", 0, 0, 0, NO, NO, NO); return; }
    if (pending.count >= 4) { finish(r, @"backpressure", 0, 0, 0, YES, NO, NO); return; }
    [pending addObject:r]; drain();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, deadline * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      if (!r.completion) return;
      if (r.dispatched) { r.cancelled = YES; [coldHost callFunctionOnJSModule:@"CandidateColdProbe" method:@"cancel" args:@[ticket]]; }
      else finish(r, @"expired", 0, 0, 0, YES, NO, NO);
      // A stuck engine/finalizer never manufactures a cleanup acknowledgment.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5000 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (r.completion) finish(r, @"runtime_unavailable", 0, 0, 0, NO, NO, NO); });
    });
  });
}
@end

@interface ColdProbeMailbox : NSObject <RCTBridgeModule>
@end
@implementation ColdProbeMailbox
RCT_EXPORT_MODULE(ColdProbeMailbox)
+ (BOOL)requiresMainQueueSetup { return YES; }
- (dispatch_queue_t)methodQueue { return dispatch_get_main_queue(); }
RCT_EXPORT_METHOD(ready) { ready = YES; struct rusage usage; getrusage(RUSAGE_SELF, &usage); printf("COLD_PROBE_METRICS engine_start_ms=%.3f peak_rss_bytes=%ld\n", (NSProcessInfo.processInfo.systemUptime - engineStartedAt) * 1000, usage.ru_maxrss); fflush(stdout); if (active && !active.dispatched) { ColdRequest *r = active; active = nil; [pending insertObject:r atIndex:0]; drain(); } }
RCT_EXPORT_METHOD(admit:(NSString *)ticket resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  if (!active || ![active.ticket isEqual:ticket] || !active.completion) { resolve(@"cancelled"); return; }
  resolve(NSProcessInfo.processInfo.systemUptime >= active.expires ? @"expired" : active.cancelled ? @"cancelled" : @"ready");
}
RCT_EXPORT_METHOD(complete:(NSString *)ticket code:(NSString *)code acquired:(NSInteger)acquired released:(NSInteger)released handles:(NSInteger)handles ack:(BOOL)ack incomplete:(BOOL)incomplete credits:(BOOL)credits) {
  ColdRequest *r = active;
  if (!r || !r.completion || ![r.ticket isEqual:ticket]) return;
  NSSet *codes = [NSSet setWithArray:@[@"ready", @"schema_invalid", @"frame_limit", @"expired", @"backpressure", @"cancelled", @"runtime_unavailable", @"probe_assertion"]];
  if (![codes containsObject:code] || acquired < 0 || acquired > 1 || released < 0 || released > 1 || handles < 0 || handles > 1) code = @"probe_assertion";
  if (NSProcessInfo.processInfo.systemUptime >= r.expires) code = @"expired";
  else if (r.cancelled) code = @"cancelled";
  if (!ack || handles != 0 || acquired != released) code = @"runtime_unavailable";
  finish(r, code, acquired, released, handles, ack, incomplete, credits);
}
@end
