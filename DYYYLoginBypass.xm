//
//  DYYYLoginBypass.xm
//  绕过登录 / 游客浏览（结构清晰、可按版本集中维护）
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │ 适配新版本抖音时，只需核对下方各组中的「类名」与「方法名」。   │
//  │ 若某类名在新版被改名，对应分组因 %init 守卫不会命中，          │
//  │ 仅该部分失效而不会导致整个 Tweak 注入崩溃。                   │
//  └─────────────────────────────────────────────────────────────┘
//

#import "DYYYLoginBypass.h"
#import "DYYYConstants.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

NSString *const kDYYYBypassLoginEnabledKey = @"DYYYBypassLoginEnabled";

@implementation DYYYLoginBypass

+ (BOOL)isEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDYYYBypassLoginEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDYYYBypassLoginEnabledKey];
}

@end

#pragma mark - 前向声明（遵循本仓库对未知类的 Hook 约定）
// 仅用于让编译器知晓方法签名；运行时由 objc_getClass 真实解析。
@interface AWEAccountManager : NSObject
- (BOOL)isLogin;
- (BOOL)hasLogin;
@end

@interface AWEUserAccount : NSObject
- (BOOL)isLogin;
@end

@interface AWELoginViewController : UIViewController
@end

@interface AWEPhoneLoginViewController : UIViewController
@end

@interface AWENormalLoginViewController : UIViewController
@end

#pragma mark - 分组一：账户状态
// 让 App 认为当前处于“已登录 / 游客可浏览”状态，
// 从而放行大部分依赖 isLogin 的界面与接口。
%group DYYYLoginBypassAccount

%hook AWEAccountManager
- (BOOL)isLogin {
    if ([DYYYLoginBypass isEnabled]) return YES;
    return %orig;
}
- (BOOL)hasLogin {
    if ([DYYYLoginBypass isEnabled]) return YES;
    return %orig;
}
%end

%hook AWEUserAccount
- (BOOL)isLogin {
    if ([DYYYLoginBypass isEnabled]) return YES;
    return %orig;
}
%end

%end

#pragma mark - 分组二：强制登录弹窗
// 监听登录页生命周期，出现后立刻关闭，回到游客浏览。
// 抖音各版本登录页类名不同，下面列出常见候选，按需增删。
%group DYYYLoginBypassModal

%hook AWELoginViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([DYYYLoginBypass isEnabled]) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}
%end

%hook AWEPhoneLoginViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([DYYYLoginBypass isEnabled]) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}
%end

%hook AWENormalLoginViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([DYYYLoginBypass isEnabled]) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}
%end

%end

#pragma mark - 安装入口
// 仅在「开关开启」且「目标类真实存在」时安装对应分组，
// 最大程度避免类名变更带来的注入崩溃。
%ctor {
    if (![DYYYLoginBypass isEnabled]) {
        return;
    }

    if (objc_getClass("AWEAccountManager") || objc_getClass("AWEUserAccount")) {
        %init(DYYYLoginBypassAccount);
    }

    if (objc_getClass("AWELoginViewController") ||
        objc_getClass("AWEPhoneLoginViewController") ||
        objc_getClass("AWENormalLoginViewController")) {
        %init(DYYYLoginBypassModal);
    }

    NSLog(@"[DYYY] 绕过登录模块已加载");
}
