//
//  ti.game — 2D sprite game engine module for Titanium SDK (iOS twin of
//  the Android module; same JS API, see README.md).
//
//  Architecture: the entire game loop is native. JS is a scene-description
//  and event API — create sprites, configure animations, enable behaviors
//  (draggable/pinchable/rotatable) and receive high-level events. The
//  bridge is never crossed per frame.
//
#import <TitaniumKit/TitaniumKit.h>

@interface TiGameModule : TiModule

@end
