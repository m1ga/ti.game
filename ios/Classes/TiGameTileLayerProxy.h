//
//  ti.game — iOS twin of android/src/ti/game/TileLayerProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGTileLayer.h"

/**
 * JS-facing tile map layer — see the Android twin for the API sketch.
 * Drawing and collision run in the native game loop; JS only writes
 * the grid and configuration.
 */
@interface TiGameTileLayerProxy : TiProxy

@property (nonatomic, readonly) TGTileLayer *layer;

@end
