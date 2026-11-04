#!/usr/bin/env python3
"""Apple broadphase build regressions. Run with Python 3 on macOS.

Compiles and links the production implementation with ARC against a small
Sprite fixture, and checks that Xcode does not silently replace source entries.
"""
from collections import Counter
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

SPRITE = r'''
#import <Foundation/Foundation.h>
@interface TGSprite : NSObject
@property float x, y, w, h, frameDeltaX, frameDeltaY;
@property BOOL circleHitbox, wrapWorldX, screenFixed;
@property NSInteger taggedIndex;
@property int broadphaseStamp;
- (void)hitCenter:(float *)out;
- (float)hitRadius;
- (void)computeAABB:(float *)out;
@end
'''

HARNESS = r'''
#import "TGBroadphase.h"
#import "TGSprite.h"
#include <assert.h>
@implementation TGSprite
- (void)hitCenter:(float *)out { out[0] = self.x; out[1] = self.y; }
- (float)hitRadius { return MIN(self.w, self.h) * 0.5f; }
- (void)computeAABB:(float *)out {
    out[0] = self.x - self.w / 2; out[1] = self.y - self.h / 2;
    out[2] = self.x + self.w / 2; out[3] = self.y + self.h / 2;
}
@end
static TGSprite *sprite(float x, float y, float w, float h) {
    TGSprite *s = [TGSprite new]; s.x = x; s.y = y; s.w = w; s.h = h;
    return s;
}
int main(void) { @autoreleasepool {
    TGBroadphase *bp = [TGBroadphase new];
    TGSprite *a = sprite(5, 10, 20, 20), *b = sprite(995, 10, 20, 20);
    a.wrapWorldX = YES; b.wrapWorldX = YES;
    [bp rebuild:@[a, b] wrapWidth:1000];
    NSArray *near = [bp queryShape:a];
    assert([near containsObject:b]);
    assert([NSSet setWithArray:near].count == near.count);
    assert(b.broadphaseStamp == bp.stamp);
    [bp rebuild:@[] wrapWidth:0];
    assert([bp queryShape:a].count == 0);
    NSMutableArray *tagged = [NSMutableArray array];
    for (int i = 0; i < 300; i++)
        [tagged addObject:sprite((i % 20) * 25 - 250, (i / 20) * 25 - 175, 30, 30)];
    [bp rebuild:tagged wrapWidth:0];
    for (TGSprite *s in tagged) {
        near = [bp queryShape:s];
        assert([NSSet setWithArray:near].count == near.count);
        for (TGSprite *t in tagged) {
            if (fabsf(s.x - t.x) <= 30 && fabsf(s.y - t.y) <= 30)
                assert([near containsObject:t]);
        }
    }
    TGSprite *wall = sprite(0, 0, 10, 10);
    TGSprite *fast = sprite(500, 0, 10, 10); fast.frameDeltaX = 500;
    [bp rebuild:@[wall] wrapWidth:0];
    assert([[bp querySwept:fast] containsObject:wall]);
    TGSprite *circle = sprite(-10, -10, 20, 20); circle.circleHitbox = YES;
    TGSprite *neighbor = sprite(0, -10, 10, 10);
    [bp rebuild:@[circle] wrapWidth:0];
    assert([[bp queryShape:neighbor] containsObject:circle]);
    __weak TGSprite *retained;
    @autoreleasepool {
        TGSprite *owned = sprite(0, 0, 10, 10); retained = owned;
        [bp rebuild:@[owned] wrapWidth:0];
    }
    assert(retained != nil);
    assert([[bp queryShape:wall] containsObject:retained]);
    [bp rebuild:@[] wrapWidth:0];
    [bp queryShape:wall];
    assert(retained == nil);
    puts("Apple broadphase: linked and native query/lifetime checks passed");
} return 0; }
'''


class AppleBroadphaseBuildTests(unittest.TestCase):
    def test_xcode_object_identifiers_are_unique(self):
        project = (ROOT / 'ios/ti.game.xcodeproj/project.pbxproj').read_text()
        identifiers = re.findall(r'^\s*([A-F0-9]{24}) /\*.*?\*/ = \{', project, re.M)
        self.assertTrue(identifiers)
        duplicates = {key: n for key, n in Counter(identifiers).items() if n > 1}
        self.assertEqual({}, duplicates, 'Duplicate IDs silently replace Xcode objects')

    @unittest.skipUnless(platform.system() == 'Darwin', 'requires Apple clang/Foundation')
    def test_production_broadphase_compiles_links_and_runs_under_arc(self):
        with tempfile.TemporaryDirectory(prefix='ti-game-apple-broadphase-') as tmp:
            directory = Path(tmp)
            for name in ('TGBroadphase.h', 'TGBroadphase.m'):
                (directory / name).write_text((ROOT / 'ios/Classes' / name).read_text())
            (directory / 'TGSprite.h').write_text(SPRITE)
            (directory / 'main.m').write_text('#include <math.h>\n' + HARNESS)
            executable = directory / 'check'
            compiled = subprocess.run([
                'xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc',
                '-fsanitize=undefined', '-fno-sanitize-recover=undefined',
                '-framework', 'Foundation',
                str(directory / 'TGBroadphase.m'), str(directory / 'main.m'),
                '-o', str(executable),
            ], capture_output=True, text=True)
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            ran = subprocess.run([str(executable)], capture_output=True, text=True)
            self.assertEqual(0, ran.returncode, ran.stdout + ran.stderr)
            print(ran.stdout.strip())


if __name__ == '__main__':
    unittest.main()
