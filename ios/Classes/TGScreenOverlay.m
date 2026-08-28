#import "TGScreenOverlay.h"
#import <string.h>

/** Column-major orthographic projection, like the renderer's own orthoM. */
static void orthoM(float *m, float left, float right, float bottom, float top,
				   float near, float far)
{
	memset(m, 0, sizeof(float) * 16);
	m[0] = 2.0f / (right - left);
	m[5] = 2.0f / (top - bottom);
	m[10] = -2.0f / (far - near);
	m[12] = -(right + left) / (right - left);
	m[13] = -(top + bottom) / (top - bottom);
	m[14] = -(far + near) / (far - near);
	m[15] = 1.0f;
}

@implementation TGScreenOverlay {
	float _projection[16];
}

- (void)surfaceChangedWithWidth:(int)width height:(int)height
{
	orthoM(_projection, 0.0f, width, height, 0.0f, -1.0f, 1.0f);
}

- (const float *)projection
{
	return _projection;
}

+ (int)cornerFromName:(NSString *)name fallback:(int)fallback
{
	if ([@"topLeft" isEqualToString:name]) {
		return TGOverlayCornerTopLeft;
	}
	if ([@"topRight" isEqualToString:name]) {
		return TGOverlayCornerTopRight;
	}
	if ([@"bottomLeft" isEqualToString:name]) {
		return TGOverlayCornerBottomLeft;
	}
	if ([@"bottomRight" isEqualToString:name]) {
		return TGOverlayCornerBottomRight;
	}
	return fallback;
}

+ (NSString *)cornerName:(int)corner
{
	switch (corner) {
		case TGOverlayCornerTopRight:
			return @"topRight";
		case TGOverlayCornerBottomLeft:
			return @"bottomLeft";
		case TGOverlayCornerBottomRight:
			return @"bottomRight";
		default:
			return @"topLeft";
	}
}

+ (void)resolveOrigin:(int)corner
		 contentWidth:(float)contentWidth
		contentHeight:(float)contentHeight
		 surfaceWidth:(float)surfaceWidth
		surfaceHeight:(float)surfaceHeight
			   margin:(float)margin
				  out:(float *)out
{
	BOOL right = (corner == TGOverlayCornerTopRight || corner == TGOverlayCornerBottomRight);
	BOOL bottom = (corner == TGOverlayCornerBottomLeft || corner == TGOverlayCornerBottomRight);
	out[0] = right ? surfaceWidth - margin - contentWidth : margin;
	out[1] = bottom ? surfaceHeight - margin - contentHeight : margin;
}

@end
