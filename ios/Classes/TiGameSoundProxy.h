//
//  ti.game — iOS twin of android/src/ti/game/SoundProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGSound.h"

/**
 * Native sound playback: createSound({ url: 'assets/jump.wav' }).
 * Effect mode (default) pools players for overlapping low-latency plays;
 * music: true streams longer tracks and pauses/resumes with the app.
 */
@interface TiGameSoundProxy : TiProxy

@end
