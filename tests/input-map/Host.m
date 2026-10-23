#import <UIKit/UIKit.h>

API_AVAILABLE(ios(13.0))
@interface InputSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation InputSceneDelegate
- (void)scene:(UIScene *)scene
	willConnectToSession:(UISceneSession *)session
				 options:(UISceneConnectionOptions *)options
{
	if (![scene isKindOfClass:UIWindowScene.class])
		return;
	self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
	self.window.rootViewController = [UIViewController new];
	[self.window makeKeyAndVisible];
}
@end

@interface InputTestHost : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation InputTestHost
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
	if (@available(iOS 13.0, *))
	{
		// The scene manifest creates the window on current iOS and Catalyst.
	}
	else
	{
		self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
		self.window.rootViewController = [UIViewController new];
		[self.window makeKeyAndVisible];
	}
	return YES;
}
@end
int main(int argc, char **argv)
{
	@autoreleasepool
	{
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(InputTestHost.class));
	}
}
