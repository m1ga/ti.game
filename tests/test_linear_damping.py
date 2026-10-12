#!/usr/bin/env python3
"""Compile unchanged production update methods in scalar Java/Obj-C fixtures.

Run: python3 tests/test_linear_damping.py
Requires a JDK; the Objective-C fixture additionally requires macOS/clang.
Rendering, animation and path collaborators are stubs. No Titanium SDK needed.
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
public class DampingCheck {
 static class Scene { boolean worldWrapXEnabled; }
 static class Path { boolean rotate; boolean advance(float dt,float[] out){return false;} }
 interface SpriteEventListener { void onPathComplete(Sprite s); }
 static class Sprite {
 float x,y,velocityX,velocityY,rotation,angularVelocity,thrust,gravity,gravityX,linearDamping;
 float maxSpeed=500,throttle,enginePower=600,steering,turnRate=200,grip=4,drag=.6f,skidThreshold;
 float frameAccelX,frameAccelY,frameDeltaX,frameDeltaY,wrapShift,wrapX,flashRemaining;
 boolean carMode,skidMarks,drifting,wrapWorldX;
 Scene scene; Path path; SpriteEventListener eventListener; float[] pathOut=new float[3];
 void updateAnimation(float dt){} void updateTweens(float dt){} void updateIdle(float dt){}
 void emitSkidMarks(float a,float b,float c,float d,float e,float f){}
 UPDATE
 CAR
 }
 static int failures=0,checks=0;
 static void check(boolean ok,String name){checks++;if(!ok){failures++;System.err.println("FAIL Java: "+name);}}
 static void close(float got,float want,String name){check(Math.abs(got-want)<.0001f,name);}
 public static void main(String[] args){
 for(int fps:new int[]{30,60,120}) for(float thrust:new float[]{100,220}){
 Sprite s=new Sprite();s.thrust=thrust;s.linearDamping=1.2f;float dt=1f/fps;s.update(dt);
 close(s.velocityY,-thrust*dt*(1-1.2f*dt),"powered launch "+fps+"/"+thrust);
 for(int i=1;i<fps;i++)s.update(dt);
 check(s.y < -1,"accumulates motion "+fps+"/"+thrust);
 }
 Sprite g=new Sprite();g.gravity=30;g.linearDamping=1.2f;g.update(1f/120);check(g.velocityY>0,"vertical acceleration from rest");
 Sprite w=new Sprite();w.gravityX=-30;w.linearDamping=1.2f;w.update(1f/120);check(w.velocityX<0,"horizontal acceleration from rest");
 Sprite car=new Sprite();car.carMode=true;car.throttle=1;car.enginePower=120;car.linearDamping=1.2f;car.update(1f/120);check(car.velocityY<0,"car throttle from rest");
 Sprite coast=new Sprite();coast.velocityX=3;coast.linearDamping=1.2f;coast.update(1f/60);close(coast.velocityX,0,"coasting still stops below4");
 Sprite fast=new Sprite();fast.velocityX=100;fast.linearDamping=1.2f;fast.update(1f/60);close(fast.velocityX,98,"damping rate unchanged");
 Sprite released=new Sprite();released.thrust=220;released.linearDamping=1.2f;released.update(1f/120);released.thrust=0;released.update(1f/120);close(released.velocityY,0,"release restores rest cutoff");
 Sprite reverse=new Sprite();reverse.thrust=-100;reverse.linearDamping=1.2f;reverse.update(1f/120);check(reverse.velocityY>0,"negative thrust accelerates");
 Sprite still=new Sprite();still.linearDamping=1.2f;still.update(1f/60);close(still.x,0,"stationary x");close(still.y,0,"stationary y");
 Sprite cap=new Sprite();cap.velocityX=600;cap.thrust=100;cap.linearDamping=1.2f;cap.update(1f/60);check(Math.hypot(cap.velocityX,cap.velocityY)<=500,"speed cap retained");
 System.out.println("Java: "+(checks-failures)+"/"+checks+" passed");if(failures>0)System.exit(1);
 }
}
"""

OBJC = r"""
#import <Foundation/Foundation.h>
#import <math.h>
@class TGSprite;
@protocol TGSpriteEventListener <NSObject>
- (void)spritePathComplete:(TGSprite *)s;
@end
@interface TGScene:NSObject
@property BOOL worldWrapXEnabled;
@end
@implementation TGScene
@end
@interface TGPath:NSObject
@property BOOL rotate;
- (BOOL)advance:(float)dt out:(float *)out;
@end
@implementation TGPath
- (BOOL)advance:(float)dt out:(float *)out{return NO;}
@end
@interface TGSprite:NSObject { float _pathOut[3]; }
FLOATS
BOOLS
@property TGScene *scene;
@property TGPath *path;
@property id<TGSpriteEventListener> eventListener;
- (void)update:(float)dt;
- (void)updateCar:(float)dt;
@end
@implementation TGSprite
- (void)updateAnimation:(float)dt{} - (void)updateTweens:(float)dt{} - (void)updateIdle:(float)dt{}
- (void)emitSkidMarksFwdX:(float)a fwdY:(float)b rightX:(float)c rightY:(float)d vLateral:(float)e threshold:(float)f{}
UPDATE
CAR
@end
static int failures=0,checks=0;
static void check(BOOL ok,const char *name){checks++;if(!ok){failures++;fprintf(stderr,"FAIL Obj-C: %s\n",name);}}
static void closeEnough(float got,float want,const char *name){check(fabsf(got-want)<.0001f,name);}
static TGSprite *sprite(void){TGSprite *s=[TGSprite new];s.maxSpeed=500;s.enginePower=600;s.turnRate=200;s.grip=4;s.drag=.6f;return s;}
int main(void){@autoreleasepool {
 for(int fps=30;fps<=120;fps*=2)for(int thrust=100;thrust<=220;thrust+=120){
 TGSprite *s=sprite();s.thrust=thrust;s.linearDamping=1.2f;float dt=1.0f/fps;[s update:dt];
 closeEnough(s.velocityY,-thrust*dt*(1-1.2f*dt),"powered first step");
 for(int i=1;i<fps;i++)[s update:dt];check(s.y < -1,"accumulates powered motion");
 }
 TGSprite *g=sprite();g.gravity=30;g.linearDamping=1.2f;[g update:1.0f/120];check(g.velocityY>0,"vertical acceleration");
 TGSprite *w=sprite();w.gravityX=-30;w.linearDamping=1.2f;[w update:1.0f/120];check(w.velocityX<0,"horizontal acceleration");
 TGSprite *car=sprite();car.carMode=YES;car.throttle=1;car.enginePower=120;car.linearDamping=1.2f;[car update:1.0f/120];check(car.velocityY<0,"car throttle");
 TGSprite *coast=sprite();coast.velocityX=3;coast.linearDamping=1.2f;[coast update:1.0f/60];closeEnough(coast.velocityX,0,"coasting cutoff");
 TGSprite *fast=sprite();fast.velocityX=100;fast.linearDamping=1.2f;[fast update:1.0f/60];closeEnough(fast.velocityX,98,"damping rate");
 TGSprite *released=sprite();released.thrust=220;released.linearDamping=1.2f;[released update:1.0f/120];released.thrust=0;[released update:1.0f/120];closeEnough(released.velocityY,0,"release cutoff");
 TGSprite *reverse=sprite();reverse.thrust=-100;reverse.linearDamping=1.2f;[reverse update:1.0f/120];check(reverse.velocityY>0,"negative thrust");
 TGSprite *still=sprite();still.linearDamping=1.2f;[still update:1.0f/60];closeEnough(still.x,0,"stationary x");closeEnough(still.y,0,"stationary y");
 TGSprite *cap=sprite();cap.velocityX=600;cap.thrust=100;cap.linearDamping=1.2f;[cap update:1.0f/60];check(hypotf(cap.velocityX,cap.velocityY)<=500,"speed cap");
 printf("Obj-C: %d/%d passed\n",checks-failures,checks);return failures?1:0;
}}
"""


def run():
    failures = []
    with tempfile.TemporaryDirectory(prefix='ti-game-damping-') as directory:
        folder = Path(directory)
        java = JAVA.replace('UPDATE', method('android/src/ti/game/engine/Sprite.java', 'public void update(float dt)')).replace('CAR', method('android/src/ti/game/engine/Sprite.java', 'private void updateCar(float dt)'))
        (folder / 'DampingCheck.java').write_text(java)
        subprocess.run(['javac', str(folder / 'DampingCheck.java')], check=True)
        failures.append(subprocess.run(['java', '-cp', directory, 'DampingCheck']).returncode)
        if platform.system() == 'Darwin':
            fields = 'x y velocityX velocityY rotation angularVelocity thrust gravity gravityX linearDamping maxSpeed throttle enginePower steering turnRate grip drag skidThreshold frameAccelX frameAccelY frameDeltaX frameDeltaY wrapShift wrapX flashRemaining'.split()
            objc = OBJC.replace('FLOATS', '\n'.join('@property float '+f+';' for f in fields)).replace('BOOLS', '\n'.join('@property BOOL '+f+';' for f in 'carMode skidMarks drifting wrapWorldX'.split()))
            objc = objc.replace('UPDATE', method('ios/Classes/TGSprite.m', '- (void)update:(float)dt')).replace('CAR', method('ios/Classes/TGSprite.m', '- (void)updateCar:(float)dt'))
            (folder / 'DampingCheck.m').write_text(objc)
            subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(folder / 'DampingCheck.m'), '-o', str(folder / 'check')], check=True)
            failures.append(subprocess.run([str(folder / 'check')]).returncode)
        else:
            print('SKIP Obj-C: requires macOS')
    return 1 if any(failures) else 0


if __name__ == '__main__':
    raise SystemExit(run())
