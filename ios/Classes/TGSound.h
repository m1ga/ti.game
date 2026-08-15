//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SoundEngine.java;
//  per-sound playback that SoundProxy delegates to on Android lives here too)
//
#import <Foundation/Foundation.h>

/**
 * Native playback for one sound. Two modes, mirroring Android:
 *
 *   Effect (default): a small pool of AVAudioPlayers over one preloaded
 *   NSData buffer, so rapid plays overlap (jump, hit, collect) — the
 *   SoundPool equivalent.
 *   Music (music = YES): a single streaming AVAudioPlayer; loops
 *   seamlessly and pauses/resumes with the app lifecycle.
 */
@interface TGSound : NSObject

@property (atomic, assign) float volume; // applied live
@property (atomic, assign) BOOL loop;
@property (nonatomic, readonly) BOOL music;

- (instancetype)initWithURL:(NSURL *)url music:(BOOL)music;

- (void)play;
- (void)pause;
- (void)stop;

@end
