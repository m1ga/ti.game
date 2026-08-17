//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SoundEngine.java;
//  per-sound playback that SoundProxy delegates to on Android lives here too)
//
#import <Foundation/Foundation.h>

/**
 * Native playback for one sound. Two modes, mirroring Android:
 *
 *   Effect (default): a small pool of AVAudioPlayerNodes over one predecoded
 *   PCM buffer on the module's shared AVAudioEngine, so rapid plays overlap
 *   without creating or starting an AudioQueue on the JavaScript call path.
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
