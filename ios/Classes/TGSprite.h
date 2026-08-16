//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Sprite.java)
//
#import <Foundation/Foundation.h>

@class TGAnimation;
@class TGScene;
@class TGSprite;
@class TGSpriteSheet;
@class TGTween;
@class TiProxy;

@protocol TGSpriteEventListener <NSObject>
- (void)spriteAnimationComplete:(TGSprite *)sprite animationName:(NSString *)animationName;
- (void)spriteTweenComplete:(TGSprite *)sprite;
- (void)sprite:(TGSprite *)sprite collidedWith:(TGSprite *)other;
- (void)sprite:(TGSprite *)sprite landedOn:(TGSprite *)solid;
@end

/**
 * Native sprite living in the renderer's scene graph. All per-frame state
 * (position, animation, tweens) is owned here so the render loop never has
 * to cross the bridge. The JS-facing TiGameSpriteProxy only writes into
 * this object and receives high-level events back.
 *
 * Coordinate system: top-left origin, y-down, pixels. (x, y) positions the
 * anchor point (default 0.5/0.5 = sprite center). Rotation is in degrees,
 * positive = clockwise on screen.
 *
 * Scalar properties are atomic: written from the main (JS/touch) thread,
 * read every frame from the render thread — the volatile-field pattern of
 * the Android engine.
 */
@interface TGSprite : NSObject

// Transform
@property (atomic, assign) float x;
@property (atomic, assign) float y;
@property (atomic, assign) float width;   // 0 = use sheet frame size
@property (atomic, assign) float height;
@property (atomic, assign) float scaleX;
@property (atomic, assign) float scaleY;
@property (atomic, assign) float rotation; // degrees
@property (atomic, assign) float anchorX;
@property (atomic, assign) float anchorY;
@property (atomic, assign) float opacity;
@property (atomic, assign) BOOL visible;
@property (atomic, assign) int zIndex;

// Tint: multiplies the frame's colors (white = art unchanged) — damage
// flashes, team colors, day/night shading. Parsed 0..1 channels.
@property (atomic, assign) float tintR;
@property (atomic, assign) float tintG;
@property (atomic, assign) float tintB;

// Glow: when glowBlur > 0 a tinted, blurred silhouette of the current
// frame draws behind the sprite (selection highlights, power-ups).
// glowBlur is the blur radius in px; color as parsed 0..1 channels.
@property (atomic, assign) float glowBlur;
@property (atomic, assign) float glowOpacity; // halo strength 0..1
@property (atomic, assign) float glowR;
@property (atomic, assign) float glowG;
@property (atomic, assign) float glowB;

// Depth sorting for top-down scenes: within the same zIndex, ySort
// sprites draw in order of their bottom edge (feet/base).
@property (atomic, assign) BOOL ySort;

// Interaction flags
@property (atomic, assign) BOOL draggable;
@property (atomic, assign) BOOL pinchable;
@property (atomic, assign) BOOL rotatable;

// YES while a finger actively drags this sprite (set by the touch
// controller). Constraints like the rope tether yield at the other
// end instead of fighting the finger.
@property (atomic, assign) BOOL dragged;

// NO = invisible to hit-testing: touches pass through to sprites
// underneath (falling blocks over a button, decorative overlays)
@property (atomic, assign) BOOL touchEnabled;

// Tile the sheet frame across the sprite instead of stretching it (per
// axis). Needs a sheet with repeat=YES whose frame spans the texture.
@property (atomic, assign) BOOL tileRepeatX;
@property (atomic, assign) BOOL tileRepeatY;

// Physics, integrated natively every frame (px/s, px/s^2)
@property (atomic, assign) float velocityX;
@property (atomic, assign) float velocityY;
@property (atomic, assign) float gravity; // applied to velocityY

// Newtonian flight (Asteroids-style)
@property (atomic, assign) float angularVelocity; // deg/s
@property (atomic, assign) float thrust;          // px/s^2 along heading
@property (atomic, assign) BOOL wrapAround;

// Seamless scroll looping: when wrapShift > 0 and x drops below wrapX,
// x jumps right by wrapShift (mirrored for wrapShift < 0 / x > wrapX).
@property (atomic, assign) float wrapX;
@property (atomic, assign) float wrapShift;

// Shrinks the collision AABB around the anchor (1 = full frame).
@property (atomic, assign) float hitboxScale;

// YES = the hitbox is a circle (radius = half the smaller drawn side
// x hitboxScale, centered on the sprite center) — balls, asteroids.
@property (atomic, assign) BOOL circleHitbox;

// Draws debug overlays; TGScene.debugAll enables it for everyone.
@property (atomic, assign) BOOL debug;

// Collision: this sprite's group tag, and the groups it reports hits with
@property (atomic, copy) NSString *collisionGroup;
@property (atomic, copy) NSSet<NSString *> *collidesWith;
@property (nonatomic, readonly) NSMutableSet<TGSprite *> *colliding; // render thread only

// Solid collision: groups whose AABBs block this sprite's movement
@property (atomic, copy) NSSet<NSString *> *solidWith;
@property (atomic, assign) BOOL onGround;

// Bounciness against solids: 0 = stop dead, 0..1 = reflect with damping
@property (atomic, assign) float restitution;

// Top-down car physics (carMode = YES)
@property (atomic, assign) BOOL carMode;
@property (atomic, assign) float throttle;    // -1 (brake/reverse) .. 1 (gas)
@property (atomic, assign) float steering;    // -1 (left) .. 1 (right)
@property (atomic, assign) float enginePower; // forward acceleration, px/s^2
@property (atomic, assign) float maxSpeed;    // px/s (reverse caps at 40%)
@property (atomic, assign) float turnRate;    // deg/s at full steering and speed
@property (atomic, assign) float grip;        // lateral friction, 1/s — lower = more drift
@property (atomic, assign) float drag;        // longitudinal friction, 1/s

// Idle wobble
@property (atomic, assign) BOOL idleAnimation;
@property (atomic, assign) float idleRotation;
@property (atomic, assign) float idleMovement;
@property (atomic, assign) float idleSpeed;

// Skid marks
@property (atomic, assign) BOOL skidMarks;
@property (atomic, assign) float skidThreshold;
@property (atomic, assign) BOOL drifting;  // read-only state for JS

// Sprite sheet / animation
@property (atomic, strong) TGSpriteSheet *sheet;
@property (atomic, assign) int frame;

// Set by TGScene add/remove; lets property setters mark z-order dirty
@property (atomic, weak) TGScene *scene;

// Back-references for firing events. The proxy owns the sprite strongly.
@property (atomic, weak) TiProxy *proxy;
@property (atomic, weak) id<TGSpriteEventListener> eventListener;

- (float)drawWidth;
- (float)drawHeight;

- (void)addAnimation:(TGAnimation *)animation named:(NSString *)name;
- (BOOL)play:(NSString *)name;
- (void)stopAnimation;
- (NSString *)currentAnimationName;

- (void)addTween:(TGTween *)tween;
- (void)clearTweens;
/** Drops only x/y tweens — used when a drag starts, so scale/rotation
 *  effects (e.g. pick-up scale-up) keep running during the drag. */
- (void)clearPositionTweens;

/** Called once per frame from the render thread with the delta in seconds. */
- (void)update:(float)dt;

/** World-space axis-aligned bounding box: out = {minX, minY, maxX, maxY}. */
- (void)computeAABB:(float *)out;

/** Collision radius for circle hitboxes. */
- (float)hitRadius;

/** World position of the sprite's geometric center: out = {x, y}. */
- (void)hitCenter:(float *)out;

/** Hit test in world coordinates, respecting rotation, scale and anchor. */
- (BOOL)hitTestX:(float)px y:(float)py;

@end
