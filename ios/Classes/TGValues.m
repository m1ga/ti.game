#import "TGValues.h"
#import "TiUtils.h"

@implementation TGValues

+ (NSString *)name:(id)value
{
	if (![value isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceCharacterSet]];
	// A percentage is a ratio wearing a string, not a name.
	if (text.length == 0 || [text hasSuffix:@"%"]) {
		return nil;
	}
	return [text lowercaseString];
}

+ (float)ratio:(id)value fallback:(float)fallback
{
	if (value == nil || value == [NSNull null]) {
		return fallback;
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];
		if ([text hasSuffix:@"%"]) {
			NSString *number = [[text substringToIndex:text.length - 1]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			NSScanner *scanner = [NSScanner scannerWithString:number];
			float parsed = 0;
			if ([scanner scanFloat:&parsed] && scanner.isAtEnd) {
				return parsed / 100.0f;
			}
			NSLog(@"[WARN] ti.game: not a percentage: %@", value);
			return fallback;
		}
	}
	return [TiUtils floatValue:value def:fallback];
}

+ (float)anchorX:(id)value fallback:(float)fallback
{
	NSString *name = [self name:value];
	if (name == nil) {
		return [self ratio:value fallback:fallback];
	}
	if ([name isEqualToString:@"left"]) {
		return 0.0f;
	}
	if ([name isEqualToString:@"right"]) {
		return 1.0f;
	}
	if ([name isEqualToString:@"center"] || [name isEqualToString:@"centre"] ||
		[name isEqualToString:@"middle"]) {
		return 0.5f;
	}
	NSLog(@"[WARN] ti.game: unknown anchor: %@", value);
	return fallback;
}

+ (float)anchorY:(id)value fallback:(float)fallback
{
	NSString *name = [self name:value];
	if (name == nil) {
		return [self ratio:value fallback:fallback];
	}
	if ([name isEqualToString:@"top"]) {
		return 0.0f;
	}
	if ([name isEqualToString:@"bottom"]) {
		return 1.0f;
	}
	if ([name isEqualToString:@"center"] || [name isEqualToString:@"centre"] ||
		[name isEqualToString:@"middle"]) {
		return 0.5f;
	}
	NSLog(@"[WARN] ti.game: unknown anchor: %@", value);
	return fallback;
}

+ (BOOL)anchor:(id)value x:(float *)x y:(float *)y
{
	NSString *name = [self name:value];
	if (name == nil) {
		return NO;
	}

	float ax = -1.0f;
	float ay = -1.0f;
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"-_ "];
	for (NSString *part in [name componentsSeparatedByCharactersInSet:separators]) {
		if (part.length == 0) {
			continue;
		}
		if ([part isEqualToString:@"left"]) {
			ax = 0.0f;
		} else if ([part isEqualToString:@"right"]) {
			ax = 1.0f;
		} else if ([part isEqualToString:@"top"]) {
			ay = 0.0f;
		} else if ([part isEqualToString:@"bottom"]) {
			ay = 1.0f;
		} else if (!([part isEqualToString:@"center"] || [part isEqualToString:@"centre"] ||
					 [part isEqualToString:@"middle"])) {
			NSLog(@"[WARN] ti.game: unknown anchor: %@", value);
			return NO;
		}
	}

	*x = ax < 0.0f ? 0.5f : ax;
	*y = ay < 0.0f ? 0.5f : ay;
	return YES;
}

+ (NSString *)anchorNameForX:(float)x y:(float)y
{
	NSString *horizontal = x == 0.0f ? @"left" : (x == 1.0f ? @"right" : (x == 0.5f ? @"center" : nil));
	NSString *vertical = y == 0.0f ? @"top" : (y == 1.0f ? @"bottom" : (y == 0.5f ? @"middle" : nil));
	if (horizontal == nil || vertical == nil) {
		return @"custom";
	}
	if ([horizontal isEqualToString:@"center"] && [vertical isEqualToString:@"middle"]) {
		return @"center";
	}
	return [NSString stringWithFormat:@"%@-%@", vertical, horizontal];
}

@end
