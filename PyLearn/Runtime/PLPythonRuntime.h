#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface PLPythonRuntime : NSObject
@property (nonatomic, copy, nullable) void (^outputHandler)(NSString *output);
@property (nonatomic, copy, nullable) void (^inputHandler)(NSString *prompt);
+ (instancetype)shared;
- (void)performRequest:(NSString *)json completion:(void (^)(NSString *response))completion;
- (void)submitInput:(NSString *)value;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
