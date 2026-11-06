#!/usr/bin/env python3
"""Compile production idle, tween and zoom timing on Java and Objective-C."""
from pathlib import Path
import platform
import re
import subprocess
import tempfile
from test_rope_pause import method

ROOT = Path(__file__).resolve().parents[1]


def declaration(path, name):
    source = (ROOT / path).read_text()
    for match in re.finditer(r'^\s*(?:private\s+)?(float|double)\s+([^;\n]+);', source, re.M):
        if re.search(r'\b' + name + r'\b', match[2]):
            return match[1] + ' ' + name + ';'
    raise ValueError(name)


JAVA = r'''
package ti.game.engine;
public class ElapsedClockCheck {
 static int checks, failures;
 static void check(boolean ok,String label){checks++;if(!ok){failures++;System.err.println("FAIL Java: "+label);}}
 static class Scene {
  ZOOM_CLOCK
  float zoomFromScale,zoomToScale,zoomLength,zoomRequestScale=2,zoomRequestDuration=3600,cameraScale=.5f;
  String zoomCurve=Easing.LINEAR,zoomRequestEasing=Easing.LINEAR;
  boolean zoomRequested=true,zoomCancelRequested,zoomActive;
  interface CameraListener {void onZoomComplete(float scale);}
  CameraListener cameraListener;
  ZOOM
 }
 public static void main(String[] args)throws Exception {
  java.lang.reflect.Field elapsedField=Tween.class.getDeclaredField("elapsed");elapsedField.setAccessible(true);
  for(int hz:new int[]{30,60,120}) {
   Sprite s=new Sprite();Tween t=new Tween();t.duration=3600;t.toX=100f;t.captureStartValues(s);
   Scene z=new Scene();float dt=1f/hz;double reference=0;
   for(int i=0;i<1800*hz;i++){reference+=dt;s.updateIdle(dt);t.update(s,dt);z.updateZoom(dt);}
   check(Math.abs(s.idleTime-reference)<1e-6,"idle accumulated time "+hz+"Hz");
   check(Math.abs(elapsedField.getDouble(t)-reference)<1e-6,"tween accumulated time "+hz+"Hz");
   check(Math.abs(z.zoomElapsed-reference)<1e-6,"zoom accumulated time "+hz+"Hz");
   double idleBefore=s.idleTime,tweenBefore=elapsedField.getDouble(t),zoomBefore=z.zoomElapsed;
   s.updateIdle(0);t.update(s,0);z.updateZoom(0);
   check(s.idleTime==idleBefore&&elapsedField.getDouble(t)==tweenBefore&&z.zoomElapsed==zoomBefore,"zero delta "+hz+"Hz");
   float w=(float)(Math.PI*2);
   check(Math.abs(s.idleAppliedY-4*Math.sin(reference*w*.43))<.01,"idle output phase "+hz+"Hz");
   z.zoomRequested=true;z.updateZoom(0);check(z.zoomElapsed==0,"zoom restart "+hz+"Hz");
   z.zoomCancelRequested=true;z.updateZoom(dt);check(!z.zoomActive&&z.zoomElapsed==0,"zoom cancel "+hz+"Hz");
   z.zoomRequested=true;z.updateZoom(.2f);double progressed=z.zoomElapsed;float scale=z.cameraScale;
   z.zoomCancelRequested=true;z.updateZoom(.2f);
   check(!z.zoomActive&&z.zoomElapsed==progressed&&z.cameraScale==scale,"zoom cancel after progress "+hz+"Hz");
  }
  Sprite s=new Sprite();Tween t=new Tween();t.duration=.3f;t.delay=.1f;t.toX=10f;t.endFrame=7;t.captureStartValues(s);
  check(!t.update(s,.05f)&&s.x==0,"tween delay");
  check(t.update(s,.4f)&&s.x==10&&s.frame==7,"tween completion");
  Scene z=new Scene();z.zoomRequestDuration=.3f;final int[] events={0};z.cameraListener=scale->events[0]++;
  z.updateZoom(.4f);z.updateZoom(.4f);check(z.cameraScale==2&&!z.zoomActive&&events[0]==1,"zoom completion once");
  System.out.printf("Java elapsed clocks: %d/%d checks passed%n",checks-failures,checks);if(failures>0)System.exit(1);
 }
}
'''
SPRITE = r'''
package ti.game.engine;
class Sprite {
 IDLE_CLOCK
 float x,y,scaleX=1,scaleY=1,rotation,opacity=1,glowOpacity;int frame;
 boolean idleAnimation=true;float idleRotation=3,idleMovement=4,idleSpeed=1,idlePhase=0,idleAppliedRot,idleAppliedX,idleAppliedY;
 IDLE
}
'''
HEADER = r'''
#import <Foundation/Foundation.h>
@interface TGSprite:NSObject { @public
 IDLE_CLOCK
 float _idlePhase,_idleAppliedRot,_idleAppliedX,_idleAppliedY;
}
@property float x,y,scaleX,scaleY,rotation,opacity,glowOpacity;
@property NSInteger frame;
@property BOOL idleAnimation;
@property float idleRotation,idleMovement,idleSpeed;
-(void)updateIdle:(float)dt;
@end
'''
OBJC = r'''
#import <Foundation/Foundation.h>
#import <math.h>
#import "TGSprite.h"
#import "TGTween.h"
#import "TGEasing.h"
@interface TGTween (Probe)
-(double)elapsedForTest;
@end
@implementation TGSprite
 IDLE
@end
@protocol TGSceneCameraListener <NSObject>
-(void)onZoomComplete:(float)scale;
@end
@interface TGScene:NSObject { @public
 ZOOM_CLOCK
 float _zoomFromScale,_zoomToScale,_zoomLength,_zoomRequestScale,_zoomRequestDuration;
 NSString *_zoomCurve,*_zoomRequestEasing;
 BOOL _zoomRequested,_zoomCancelRequested,_zoomActive;
}
@property float cameraScale;
@property id<TGSceneCameraListener> cameraListener;
-(void)updateZoom:(float)dt;
@end
@implementation TGScene
 ZOOM
@end
@interface Listener:NSObject<TGSceneCameraListener>
@property int events;
@end
@implementation Listener
-(void)onZoomComplete:(float)scale{self.events++;}
@end
static int checks,failures;
static void check(BOOL ok,const char *label){checks++;if(!ok){failures++;fprintf(stderr,"FAIL Obj-C: %s\n",label);}}
static TGSprite *sprite(void){TGSprite*s=[TGSprite new];s.idleAnimation=YES;s.idleRotation=3;s.idleMovement=4;s.idleSpeed=1;return s;}
static TGScene *scene(void){TGScene*z=[TGScene new];z.cameraScale=.5f;z->_zoomRequestScale=2;z->_zoomRequestDuration=3600;z->_zoomRequestEasing=TGEasingLinear;z->_zoomRequested=YES;return z;}
int main(void){@autoreleasepool {
 for(int h=0;h<3;h++){
  int hz=(int[]){30,60,120}[h];float dt=1.0f/hz;double reference=0;
  TGSprite*s=sprite();TGTween*t=[TGTween new];t.duration=3600;t.toX=@100;[t captureStartValues:s];TGScene*z=scene();
  for(int i=0;i<1800*hz;i++){reference+=dt;[s updateIdle:dt];[t update:s delta:dt];[z updateZoom:dt];}
  check(fabs(s->_idleTime-reference)<1e-6,"idle accumulated time");
  check(fabs([t elapsedForTest]-reference)<1e-6,"tween accumulated time");
  check(fabs(z->_zoomElapsed-reference)<1e-6,"zoom accumulated time");
  double a=s->_idleTime,b=[t elapsedForTest],c=z->_zoomElapsed;
  [s updateIdle:0];[t update:s delta:0];[z updateZoom:0];
  check(s->_idleTime==a&&[t elapsedForTest]==b&&z->_zoomElapsed==c,"zero delta");
  float w=(float)(M_PI*2);check(fabs(s->_idleAppliedY-4*sin(reference*w*.43))<.01,"idle output phase");
  z->_zoomRequested=YES;[z updateZoom:0];check(z->_zoomElapsed==0,"zoom restart");
  z->_zoomCancelRequested=YES;[z updateZoom:dt];check(!z->_zoomActive&&z->_zoomElapsed==0,"zoom cancel");
  z->_zoomRequested=YES;[z updateZoom:.2f];double progressed=z->_zoomElapsed;float scale=z.cameraScale;
  z->_zoomCancelRequested=YES;[z updateZoom:.2f];
  check(!z->_zoomActive&&z->_zoomElapsed==progressed&&z.cameraScale==scale,"zoom cancel after progress");
 }
 TGSprite*s=sprite();s.idleAnimation=NO;TGTween*t=[TGTween new];t.duration=.3f;t.delay=.1f;t.toX=@10;t.endFrame=@7;[t captureStartValues:s];
 check(![t update:s delta:.05f]&&s.x==0,"tween delay");check([t update:s delta:.4f]&&s.x==10&&s.frame==7,"tween completion");
 TGScene*z=scene();z->_zoomRequestDuration=.3f;Listener*l=[Listener new];z.cameraListener=l;[z updateZoom:.4f];[z updateZoom:.4f];
 check(z.cameraScale==2&&!z->_zoomActive&&l.events==1,"zoom completion once");
 printf("Obj-C elapsed clocks: %d/%d checks passed\n",checks-failures,checks);return failures?1:0;
}}
'''


def run():
    java = JAVA.replace('ZOOM_CLOCK', declaration('android/src/ti/game/engine/Scene.java', 'zoomElapsed')).replace('ZOOM', method('android/src/ti/game/engine/Scene.java', 'private void updateZoom('))
    sprite = SPRITE.replace('IDLE_CLOCK', declaration('android/src/ti/game/engine/Sprite.java', 'idleTime')).replace('IDLE', method('android/src/ti/game/engine/Sprite.java', 'private void updateIdle(').replace('private void', 'void', 1))
    objc = OBJC.replace('ZOOM_CLOCK', declaration('ios/Classes/TGScene.m', '_zoomElapsed')).replace('ZOOM', method('ios/Classes/TGScene.m', '- (void)updateZoom:')).replace('IDLE', method('ios/Classes/TGSprite.m', '- (void)updateIdle:'))
    header = HEADER.replace('IDLE_CLOCK', declaration('ios/Classes/TGSprite.m', '_idleTime'))
    with tempfile.TemporaryDirectory(prefix='ti-game-elapsed-') as folder:
        folder = Path(folder)
        (folder/'ElapsedClockCheck.java').write_text(java)
        (folder/'Sprite.java').write_text(sprite)
        subprocess.run(['javac','-d',str(folder),str(ROOT/'android/src/ti/game/engine/Tween.java'),str(ROOT/'android/src/ti/game/engine/Easing.java'),str(folder/'Sprite.java'),str(folder/'ElapsedClockCheck.java')],check=True)
        results=[subprocess.run(['java','-cp',str(folder),'ti.game.engine.ElapsedClockCheck']).returncode]
        if platform.system()=='Darwin':
            (folder/'TGSprite.h').write_text(header)
            for name in ['TGTween.h','TGEasing.h','TGEasing.m']:
                (folder/name).write_text((ROOT/'ios/Classes'/name).read_text())
            tween=(ROOT/'ios/Classes/TGTween.m').read_text().replace('@end','- (double)elapsedForTest { return _elapsed; }\n@end')
            (folder/'TGTween.m').write_text(tween)
            (folder/'ElapsedClockCheck.m').write_text(objc)
            subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-I',str(folder),str(folder/'TGEasing.m'),str(folder/'TGTween.m'),str(folder/'ElapsedClockCheck.m'),'-o',str(folder/'check')],check=True)
            results.append(subprocess.run([str(folder/'check')]).returncode)
        return int(any(results))


if __name__=='__main__':
    raise SystemExit(run())
