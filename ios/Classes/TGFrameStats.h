//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/FrameStats.java)
//
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

/** One closed window's worth of numbers. */
typedef struct {
	double fps;
	double averageCpuMs;
	double p95CpuMs;
	double maxCpuMs;
	double averageUpdateMs;
	double averageTexturePrepareMs;
	double averageBatchMs;
	double averagePresentMs; // iOS only — see the class comment
	int droppedFrames;
	int presentFailures;     // iOS only
	int sprites;
	int visibleSprites;
	int emitters;
	int particles;
	int drawCalls;
	int textureSwitches;
} TGFrameStatsSnapshot;

/**
 * One second of render telemetry: frame CPU cost (average, p95, peak),
 * dropped frames, per-phase timings and the batcher's counters. Feeds both
 * the on-screen debug HUD and the 'performance' event.
 *
 * Everything here is off unless `enabled` is set, and the renderer reads
 * that flag before it touches a clock — with the HUD off and no
 * 'performance' listener the engine pays for no measurement at all.
 *
 * Written and read on the render thread only; `enabled` is the single
 * field that crosses threads.
 *
 * Two metrics this platform can report and Android cannot: average present
 * time and present failures, both taken around presentRenderbuffer.
 * GLSurfaceView swaps buffers inside its own GLThread after onDrawFrame
 * returns, so the Android twin has no point at which to time them; it
 * omits both from the HUD and from the event payload rather than
 * reporting zeros.
 */
@interface TGFrameStats : NSObject

/** Master switch — HUD on, or a 'performance' listener attached. */
@property (atomic, assign) BOOL enabled;

// --- Per-frame slots, filled by the renderer before addFrame ------------
@property (nonatomic, assign) double updateMs;
@property (nonatomic, assign) double texturePrepareMs;
@property (nonatomic, assign) double batchMs;
@property (nonatomic, assign) int sprites;
@property (nonatomic, assign) int visibleSprites;
@property (nonatomic, assign) int emitters;
@property (nonatomic, assign) int particles;
@property (nonatomic, assign) int drawCalls;
@property (nonatomic, assign) int textureSwitches;

- (void)reset;

/**
 * Records one frame. `cpuMs` is the renderer's own cost. The interval
 * between consecutive display-link timestamps against the expected one
 * gives the dropped-frame count.
 */
- (void)addFrameCpuMs:(double)cpuMs
			presentMs:(double)presentMs
			presented:(BOOL)presented
				  now:(CFTimeInterval)now
			 interval:(CFTimeInterval)interval
			   target:(CFTimeInterval)target;

- (BOOL)windowClosed:(CFTimeInterval)now;

/** Averages the window, starts a new one, and returns the numbers. */
- (TGFrameStatsSnapshot)closeWindow:(CFTimeInterval)now;

@end
