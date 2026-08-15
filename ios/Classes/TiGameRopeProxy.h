//
//  ti.game — iOS twin of android/src/ti/game/RopeProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGRope.h"

/**
 * JS-facing Verlet rope — see the Android twin for the API sketch.
 * Integration, constraints and drawing all run in the native game loop;
 * JS only writes configuration.
 */
@interface TiGameRopeProxy : TiProxy

@property (nonatomic, readonly) TGRope *rope;

@end
