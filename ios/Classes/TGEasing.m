#import "TGEasing.h"
#import <math.h>

NSString *const TGEasingLinear = @"linear";
NSString *const TGEasingEaseIn = @"easeIn";
NSString *const TGEasingEaseOut = @"easeOut";
NSString *const TGEasingEaseInOut = @"easeInOut";
NSString *const TGEasingBounce = @"bounce";
NSString *const TGEasingElastic = @"elastic";

static float bounceOut(float t)
{
	float n1 = 7.5625f;
	float d1 = 2.75f;
	if (t < 1.0f / d1) {
		return n1 * t * t;
	} else if (t < 2.0f / d1) {
		t -= 1.5f / d1;
		return n1 * t * t + 0.75f;
	} else if (t < 2.5f / d1) {
		t -= 2.25f / d1;
		return n1 * t * t + 0.9375f;
	} else {
		t -= 2.625f / d1;
		return n1 * t * t + 0.984375f;
	}
}

float TGEasingApply(NSString *name, float t)
{
	if (name == nil) {
		return t;
	}
	if ([name isEqualToString:TGEasingEaseIn]) {
		return t * t * t;
	}
	if ([name isEqualToString:TGEasingEaseOut]) {
		float u = 1.0f - t;
		return 1.0f - u * u * u;
	}
	if ([name isEqualToString:TGEasingEaseInOut]) {
		return (t < 0.5f) ? 4.0f * t * t * t : 1.0f - powf(-2.0f * t + 2.0f, 3.0f) / 2.0f;
	}
	if ([name isEqualToString:TGEasingBounce]) {
		return bounceOut(t);
	}
	if ([name isEqualToString:TGEasingElastic]) {
		if (t <= 0.0f || t >= 1.0f) {
			return t;
		}
		double c4 = (2.0 * M_PI) / 3.0;
		return (float)(pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0);
	}
	return t;
}
