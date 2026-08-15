//
//  ti.game — iOS twin of android/src/ti/game/EmitterProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGParticleEmitter.h"

/**
 * JS-facing particle emitter — see the Android twin for the API sketch.
 * Everything per-frame (spawning, integration, fading, drawing) runs
 * natively; JS only writes configuration and triggers bursts.
 */
@interface TiGameEmitterProxy : TiProxy

@property (nonatomic, readonly) TGParticleEmitter *emitter;

@end
