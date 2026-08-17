//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/ParticleEmitter.java)
//
#import <Foundation/Foundation.h>

@class TGSprite;
@class TGSpriteBatch;
@class TGSpriteSheet;

/**
 * Native particle emitter, ticked and drawn entirely in the game loop —
 * zero bridge traffic while running. Configuration properties are atomic
 * (main thread writes, render thread reads); the particle pool itself is
 * render thread only.
 *
 * Continuous mode spawns `rate` particles per second while `emitting`;
 * emit(n) queues a one-shot burst on top (explosions). Particles fly from
 * the emitter position (or the followed target sprite, plus offset) in a
 * cone of `spread` degrees around `angle` (0 = up, clockwise), with speed
 * randomized between 50% and 100% of `speed`. Over each particle's
 * lifetime, scale and opacity interpolate start → end.
 */
@interface TGParticleEmitter : NSObject

@property (atomic, strong) TGSpriteSheet *sheet;
@property (atomic, assign) int frame;
@property (atomic, assign) float x;
@property (atomic, assign) float y;
@property (atomic, assign) float offsetX;
@property (atomic, assign) float offsetY;
@property (atomic, assign) int zIndex;
@property (atomic, assign) float rate;          // particles per second
@property (atomic, assign) float lifetime;      // seconds
@property (atomic, assign) float speed;         // px/s (randomized 50%..100%)
@property (atomic, assign) float angle;         // base direction, 0 = up, clockwise degrees
@property (atomic, assign) float spread;        // cone width in degrees
@property (atomic, assign) float gravity;       // px/s^2
@property (atomic, assign) float size;          // base particle width in px; 0 = frame size
@property (atomic, assign) float startScale;
@property (atomic, assign) float endScale;
@property (atomic, assign) float startOpacity;
@property (atomic, assign) float endOpacity;
@property (atomic, assign) float tintR;
@property (atomic, assign) float tintG;
@property (atomic, assign) float tintB;
// Additive blending: particles brighten the backdrop instead of
// covering it (fire, sparks, magic). One batch flush per mode change.
@property (atomic, assign) BOOL additiveBlend;
@property (atomic, assign) BOOL emitting;
@property (atomic, strong) TGSprite *target;    // follow this sprite instead of x/y
@property (atomic, assign) int maxParticles;    // clamped to [1, 1000]

/** Queues a one-shot burst of n particles (main thread safe). */
- (void)emit:(int)n;

/** Kills all live particles on the next frame (main thread safe). */
- (void)clearParticles;

/** Spawn, integrate and age all particles. Render thread, once per frame. */
- (void)update:(float)dt;

/** Draws all live particles through the shared batcher. Render thread. */
- (void)draw:(TGSpriteBatch *)batch;

@end
