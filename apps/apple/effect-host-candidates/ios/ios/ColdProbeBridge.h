#import <Foundation/Foundation.h>
@class RCTHost;
@class RCTRootViewFactory;
NS_ASSUME_NONNULL_BEGIN
@interface ColdProbeBridge : NSObject
+ (void)configureStarter:(void (^)(void))starter;
+ (void)initializeAndSetHost:(RCTRootViewFactory *)factory;
+ (void)setHost:(RCTHost *)host;
+ (void)startRequest:(NSString *)request ticket:(NSString *)ticket startedAt:(NSTimeInterval)startedAt cancelled:(BOOL)cancelled completion:(void (^)(NSDictionary *))completion;
+ (void)cancelTicket:(NSString *)ticket;
@end
NS_ASSUME_NONNULL_END
