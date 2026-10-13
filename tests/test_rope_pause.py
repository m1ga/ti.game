#!/usr/bin/env python3
"""Compile production Rope update/rebuild methods in Java and Obj-C fixtures.

Run: python3 tests/test_rope_pause.py
Requires a JDK; the Objective-C fixture additionally requires macOS/clang.
The fixture exposes node arrays for assertions and omits rendering.
"""
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def method(file, signature):
    source = (ROOT / file).read_text()
    start = source.index(signature)
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


JAVA = r"""
public class RopePauseCheck {
 static class Sprite { float x,y,velocityX,velocityY; boolean dragged; }
 static class Rope {
 static final int MAX_SEGMENTS=200;
 int segments=1,pointCount=0,iterations=1;
 float x,y,maxLength,gravity=1500,damping=.985f,segmentLength=10,endX,endY;
 Sprite head,tail;
 float[] px,py,prevX,prevY;
 UPDATE
 REBUILD
 }
 static int failures=0,checks=0;
 static void check(boolean ok,String name){checks++;if(!ok){failures++;System.err.println("FAIL Java: "+name);}}
 static Rope seeded(){Rope r=new Rope();r.pointCount=2;r.px=new float[]{0,10};r.py=new float[]{0,0};r.prevX=new float[]{0,10};r.prevY=new float[]{0,-1};r.endX=10;return r;}
 public static void main(String[] args){
 Rope r=seeded();for(int i=0;i<120;i++)r.update(0);
 check(r.px[1]==10&&r.py[1]==0,"zero dt preserves nodes");
 check(r.prevX[1]==10&&r.prevY[1]==-1,"zero dt preserves history");
 check(r.endX==10&&r.endY==0,"zero dt preserves endpoint");
 Rope constraint=seeded();constraint.px[1]=100;constraint.prevX[1]=100;constraint.prevY[1]=0;constraint.endX=100;constraint.update(0);
 check(constraint.px[1]==100,"zero dt does not relax constraints");
 Rope tether=seeded();tether.head=new Sprite();tether.tail=new Sprite();tether.tail.x=20;tether.tail.velocityX=3;tether.maxLength=10;tether.update(0);
 check(tether.head.x==0&&tether.tail.x==20,"zero dt does not reposition tether ends");
 check(tether.tail.velocityX==3,"zero dt does not cancel outward velocity");
 Rope negative=seeded();negative.update(-.01f);check(negative.px[1]==10&&negative.py[1]==0,"negative dt does not advance");
 Rope resume=seeded();resume.update(0);resume.update(1f/60);check(resume.py[1]>0,"positive dt resumes existing motion");
 Rope fresh=new Rope();fresh.x=3;fresh.y=4;fresh.update(0);
 check(fresh.pointCount==2,"zero dt initializes new geometry");
 check(fresh.endX==3&&fresh.endY==14,"new endpoint is readable at zero dt");
 Rope positive=seeded();positive.update(1f/60);check(positive.py[1]>0,"positive dt still integrates");
 System.out.println("Java: "+(checks-failures)+"/"+checks+" passed");if(failures>0)System.exit(1);
 }
}
"""

OBJC = r"""
#import <Foundation/Foundation.h>
#import <math.h>
#import <stdlib.h>
static const int kMaxSegments=200;
@interface TGSprite:NSObject
@property float x,y,velocityX,velocityY;
@property BOOL dragged;
@end
@implementation TGSprite
@end
@interface TGRope:NSObject { @public float *_px,*_py,*_prevX,*_prevY; int _pointCount; }
@property int segments,iterations;
@property float x,y,maxLength,gravity,damping,segmentLength,endX,endY;
@property TGSprite *head,*tail;
- (void)update:(float)dt;
- (void)rebuild:(int)count headX:(float)headX headY:(float)headY;
@end
@implementation TGRope
- (void)dealloc{free(_px);free(_py);free(_prevX);free(_prevY);}
UPDATE
REBUILD
@end
static int failures=0,checks=0;
static void check(BOOL ok,const char *name){checks++;if(!ok){failures++;fprintf(stderr,"FAIL Obj-C: %s\n",name);}}
static TGRope *fresh(void){TGRope *r=[TGRope new];r.segments=1;r.iterations=1;r.gravity=1500;r.damping=.985f;r.segmentLength=10;return r;}
static TGRope *seeded(void){TGRope *r=fresh();[r rebuild:2 headX:0 headY:0];r->_px[1]=10;r->_py[1]=0;r->_prevX[1]=10;r->_prevY[1]=-1;r.endX=10;r.endY=0;return r;}
int main(void){@autoreleasepool {
 TGRope *r=seeded();for(int i=0;i<120;i++)[r update:0];
 check(r->_px[1]==10&&r->_py[1]==0,"zero dt preserves nodes");
 check(r->_prevX[1]==10&&r->_prevY[1]==-1,"zero dt preserves history");
 check(r.endX==10&&r.endY==0,"zero dt preserves endpoint");
 TGRope *constraint=seeded();constraint->_px[1]=100;constraint->_prevX[1]=100;constraint->_prevY[1]=0;constraint.endX=100;[constraint update:0];check(constraint->_px[1]==100,"zero dt does not relax constraints");
 TGRope *tether=seeded();tether.head=[TGSprite new];tether.tail=[TGSprite new];tether.tail.x=20;tether.tail.velocityX=3;tether.maxLength=10;[tether update:0];
 check(tether.head.x==0&&tether.tail.x==20,"zero dt preserves tether ends");
 check(tether.tail.velocityX==3,"zero dt preserves outward velocity");
 TGRope *negative=seeded();[negative update:-.01f];check(negative->_px[1]==10&&negative->_py[1]==0,"negative dt does not advance");
 TGRope *resume=seeded();[resume update:0];[resume update:1.0f/60];check(resume->_py[1]>0,"positive dt resumes motion");
 TGRope *init=fresh();init.x=3;init.y=4;[init update:0];check(init->_pointCount==2,"zero dt initializes geometry");check(init.endX==3&&init.endY==14,"new endpoint is readable");
 TGRope *positive=seeded();[positive update:1.0f/60];check(positive->_py[1]>0,"positive dt still integrates");
 printf("Obj-C: %d/%d passed\n",checks-failures,checks);return failures?1:0;
}}
"""


def run():
    failures = []
    with tempfile.TemporaryDirectory(prefix='ti-game-rope-') as directory:
        folder = Path(directory)
        java = JAVA.replace('UPDATE', method('android/src/ti/game/engine/Rope.java', 'public void update(float dt)')).replace('REBUILD', method('android/src/ti/game/engine/Rope.java', 'private void rebuild(int count, float headX, float headY)'))
        (folder / 'RopePauseCheck.java').write_text(java)
        subprocess.run(['javac', str(folder / 'RopePauseCheck.java')], check=True)
        failures.append(subprocess.run(['java', '-cp', directory, 'RopePauseCheck']).returncode)
        if platform.system() == 'Darwin':
            objc = OBJC.replace('UPDATE', method('ios/Classes/TGRope.m', '- (void)update:(float)dt')).replace('REBUILD', method('ios/Classes/TGRope.m', '- (void)rebuild:(int)count headX:(float)headX headY:(float)headY'))
            (folder / 'RopePauseCheck.m').write_text(objc)
            subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(folder / 'RopePauseCheck.m'), '-o', str(folder / 'check')], check=True)
            failures.append(subprocess.run([str(folder / 'check')]).returncode)
        else:
            print('SKIP Obj-C: requires macOS')
    return 1 if any(failures) else 0


if __name__ == '__main__':
    raise SystemExit(run())
