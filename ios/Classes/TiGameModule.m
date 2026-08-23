#import "TiGameModule.h"
#import "TGEasing.h"
#import "TiGameGameView.h"

@implementation TiGameModule

#pragma mark Internal

- (void)startup
{
	[super startup];
	[TiGameGameView installLiveViewRestartHook];
	[TiGameGameView activateRuntimeContext:self.pageContext];
}

- (void)contextWasShutdown:(id<TiEvaluator>)context
{
	[TiGameGameView shutdownViewsForRuntimeContext:context];
	[super contextWasShutdown:context];
}

- (id)moduleGUID
{
	return @"6dadd1f9-b40b-4f8d-807d-f433997953ab";
}

- (NSString *)moduleId
{
	return @"ti.game";
}

#pragma mark Constants

// Easing constants for sprite.animate({ easing: Game.EASE_OUT, ... }).
// createGameView / createSprite / createSpriteSheet resolve dynamically to
// TiGameGameViewProxy / TiGameSpriteProxy / TiGameSpriteSheetProxy.

- (NSString *)EASE_LINEAR
{
	return TGEasingLinear;
}

- (NSString *)EASE_IN
{
	return TGEasingEaseIn;
}

- (NSString *)EASE_OUT
{
	return TGEasingEaseOut;
}

- (NSString *)EASE_IN_OUT
{
	return TGEasingEaseInOut;
}

- (NSString *)EASE_BOUNCE
{
	return TGEasingBounce;
}

- (NSString *)EASE_ELASTIC
{
	return TGEasingElastic;
}

@end
