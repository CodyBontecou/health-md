#import <React/RCTBridgeModule.h>
#import <Foundation/Foundation.h>

@interface NativeProbe : NSObject <RCTBridgeModule>
@end

@implementation NativeProbe {
  NSMutableDictionary<NSNumber *, NSNumber *> *_handles;
  NSMutableArray<dispatch_block_t> *_waiting;
  NSMutableDictionary<NSNumber *, dispatch_block_t> *_inspections;
  NSMutableDictionary<NSNumber *, RCTPromiseResolveBlock> *_inspectionResolvers;
  NSInteger _next, _acquired, _released, _inspecting, _releasing, _frames, _acceptedFrames, _acknowledgedFrames, _maxActive, _maxQueued;
  dispatch_queue_t _queue;
}
RCT_EXPORT_MODULE(NativeProbe)
+ (BOOL)requiresMainQueueSetup { return NO; }
- (instancetype)init {
  if ((self = [super init])) {
    _handles = [NSMutableDictionary new]; _waiting = [NSMutableArray new]; _inspections = [NSMutableDictionary new]; _inspectionResolvers = [NSMutableDictionary new];
    _queue = dispatch_queue_create("healthmd.candidate.synthetic", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}
- (dispatch_queue_t)methodQueue { return _queue; }
RCT_EXPORT_METHOD(acquire:(double)delay resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  if (delay < 0 || delay > 1000 || _handles.count > 1) { reject(@"admission_invalid", @"admission_invalid", nil); return; }
  NSNumber *token = @(++_next); _handles[token] = @(delay); _acquired++; resolve(token);
}
RCT_EXPORT_METHOD(inspect:(NSNumber *)token resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSNumber *delay = _handles[token];
  if (!delay) { reject(@"handle_invalid", @"handle_invalid", nil); return; }
  _inspecting++;
  dispatch_block_t work = dispatch_block_create((dispatch_block_flags_t)0, ^{
    [self->_inspections removeObjectForKey:token]; [self->_inspectionResolvers removeObjectForKey:token]; self->_inspecting--; resolve(@"ready");
  });
  _inspections[token] = work;
  _inspectionResolvers[token] = resolve;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_MSEC)), _queue, work);
}
RCT_EXPORT_METHOD(release:(NSNumber *)token resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  if (!_handles[token]) { reject(@"handle_invalid", @"handle_invalid", nil); return; }
  dispatch_block_t inspection = _inspections[token];
  if (inspection) {
    dispatch_block_cancel(inspection); [_inspections removeObjectForKey:token]; _inspecting--;
    RCTPromiseResolveBlock settle = _inspectionResolvers[token]; [_inspectionResolvers removeObjectForKey:token];
    if (settle) settle(@"cancelled");
  }
  _releasing++;
  // Native ownership remains visible until the asynchronous acknowledgment.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), _queue, ^{
    if (!self->_handles[token]) { reject(@"duplicate_release", @"duplicate_release", nil); return; }
    [self->_handles removeObjectForKey:token]; self->_released++; self->_releasing--; resolve(nil);
  });
}
RCT_EXPORT_METHOD(stats:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  resolve(@{@"acquired": @(_acquired), @"released": @(_released), @"active": @(_handles.count), @"inspecting": @(_inspecting), @"unresolved_inspections": @(_inspectionResolvers.count), @"releasing": @(_releasing), @"accepted_frames": @(_acceptedFrames), @"acknowledged_frames": @(_acknowledgedFrames), @"max_active": @(_maxActive), @"max_queued": @(_maxQueued), @"active_frames": @(_frames), @"queued_frames": @(_waiting.count)});
}
RCT_EXPORT_METHOD(reset:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  if (_handles.count || _frames || _waiting.count) { reject(@"busy", @"busy", nil); return; }
  _acquired = 0; _released = 0; _acceptedFrames = 0; _acknowledgedFrames = 0; _maxActive = 0; _maxQueued = 0; resolve(nil);
}
- (void)drain {
  while (_frames < 2 && _waiting.count) {
    dispatch_block_t work = _waiting.firstObject; [_waiting removeObjectAtIndex:0]; work();
  }
}
RCT_EXPORT_METHOD(frame:(NSString *)value resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (bytes.length > 65536) { reject(@"frame_limit", @"frame_limit", nil); return; }
  id frame = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
  BOOL versionIsNumber = [frame isKindOfClass:NSDictionary.class] && [frame[@"version"] isKindOfClass:NSNumber.class] &&
    CFGetTypeID((__bridge CFTypeRef)frame[@"version"]) != CFBooleanGetTypeID();
  BOOL sequenceIsNumber = [frame isKindOfClass:NSDictionary.class] && [frame[@"sequence"] isKindOfClass:NSNumber.class] &&
    CFGetTypeID((__bridge CFTypeRef)frame[@"sequence"]) != CFBooleanGetTypeID();
  if (![frame isKindOfClass:NSDictionary.class] || [frame count] != 4 ||
      ![frame[@"schema"] isEqual:@"healthmd.candidate_host_probe"] ||
      !versionIsNumber || !sequenceIsNumber ||
      ![frame[@"version"] isEqual:@1] || ![frame[@"case_id"] isEqual:@"queue_backpressure"] ||
      ![frame[@"sequence"] isEqual:@0]) { reject(@"schema_invalid", @"schema_invalid", nil); return; }
  if (_frames == 2 && _waiting.count == 4) { reject(@"backpressure", @"backpressure", nil); return; }
  _acceptedFrames++;
  dispatch_block_t work = ^{
    self->_frames++; self->_maxActive = MAX(self->_maxActive, self->_frames);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), self->_queue, ^{
      self->_frames--; self->_acknowledgedFrames++; resolve(@"ack"); [self drain];
    });
  };
  if (_frames < 2) work(); else { [_waiting addObject:work]; _maxQueued = MAX(_maxQueued, _waiting.count); }
}
RCT_EXPORT_METHOD(report:(NSString *)value) {
  // Only this private bounded result schema is emitted, never arbitrary error/payload text.
  NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *result = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
  if (bytes.length < 65536 && [result[@"schema"] isEqual:@"healthmd.candidate_host_probe"] &&
      ([result[@"result"] isEqual:@"passed"] || [result[@"result"] isEqual:@"failed"])) {
    printf("HEALTHMD_CANDIDATE_RESULT %s\n", value.UTF8String); fflush(stdout);
  }
}
@end
