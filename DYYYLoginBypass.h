//
//  DYYYLoginBypass.h
//  绕过登录 / 游客浏览（集中维护，按版本适配）
//
//  设计目标：把“绕过登录”相关的所有 Hook 收敛到单一模块，
//  并仅在目标类真实存在时才安装对应分组，避免抖音改版后
//  类名被改名导致 Tweak 注入崩溃（这也是老版本“失效/闪退”的常见原因）。
//
#ifndef DYYYLoginBypass_h
#define DYYYLoginBypass_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 设置项中“绕过登录 / 游客浏览”的总开关键
extern NSString *const kDYYYBypassLoginEnabledKey;

@interface DYYYLoginBypass : NSObject

/// 是否启用了绕过登录
+ (BOOL)isEnabled;

/// 设置是否启用绕过登录
+ (void)setEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END

#endif /* DYYYLoginBypass_h */
