#!/usr/bin/env python3
"""Run production animation ticking for 30 simulated minutes on both twins.

Uses the actual accumulator declaration, animation class and update method.
Only sprite/proxy/render collaborators are stubs. No real-time sleep required.
"""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

from test_rope_pause import method

ROOT = Path(__file__).resolve().parents[1]

JAVA = r'''
import java.util.*;
import ti.game.engine.Animation;
public class AnimationClockCheck {
 interface SpriteEventListener { void onAnimationComplete(Sprite s,String name); }
 static class Sprite {
  CLOCK
  int frame; boolean playing=true;
  Animation currentAnimation;
  Map<String,Animation> animations=new HashMap<>();
  ArrayDeque<String> animationQueue=new ArrayDeque<>();
  SpriteEventListener eventListener;
  UPDATE
 }
 public static void main(String[] args) {
  int checks=0,failures=0;
  for(int hz:new int[]{30,60,120}) for(float fps:new float[]{4,1000f/167,12}) {
   Sprite s=new Sprite();s.currentAnimation=new Animation("blink",new int[]{10,20,30,40},fps,true,-1);
   float dt=1f/hz;double elapsed=0;int mismatches=0;
   for(int n=0;n<1800*hz;n++) {
    elapsed+=dt;s.updateAnimation(dt);
    if(s.frame!=new int[]{10,20,30,40}[(int)(elapsed*fps)%4])mismatches++;
   }
   double drift=(s.animationTime-elapsed)*1000;
   System.out.printf("Java hz=%d fps=%.6f elapsed=%.6f driftMs=%.6f mismatchedFrames=%d%n",hz,fps,elapsed,drift,mismatches);
   checks++;if(Math.abs(drift)>.001||mismatches!=0)failures++;
   int before=s.frame;s.updateAnimation(0);checks++;if(s.frame!=before)failures++;
  }
  Sprite once=new Sprite();once.currentAnimation=new Animation("once",new int[]{2,7},4,false,-1);
  final int[] events={0};once.eventListener=(s,name)->events[0]++;
  once.updateAnimation(.6f);once.updateAnimation(.6f);
  checks++;if(once.frame!=7||once.playing||events[0]!=1)failures++;
  Sprite chain=new Sprite();chain.currentAnimation=new Animation("a",new int[]{2,7},4,false,-1);
  chain.animations.put("b",new Animation("b",new int[]{8,9},4,true,-1));chain.animationQueue.add("b");
  chain.updateAnimation(.6f);checks++;if(chain.frame!=8||chain.animationTime!=0)failures++;
  System.out.printf("Java: %d/%d checks passed%n",checks-failures,checks);
  if(failures>0)System.exit(1);
 }
}
'''

OBJC = r'''
#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <math.h>
#import "TGAnimation.h"
@class TGSprite;
@protocol TGSpriteEventListener <NSObject>
- (void)spriteAnimationComplete:(TGSprite *)sprite animationName:(NSString *)name;
@end
@interface TGSprite : NSObject { @public
 CLOCK
 BOOL _playing;
 atomic_bool _animationActive;
 TGAnimation *_currentAnimation;
 NSMutableDictionary<NSString *,TGAnimation *> *_animations;
 NSMutableArray<NSString *> *_animationQueue;
}
@property NSInteger frame;
@property id<TGSpriteEventListener> eventListener;
- (void)updateAnimation:(float)dt;
@end
@implementation TGSprite
 UPDATE
@end
static TGSprite *sprite(float fps) {
 TGSprite *s=[TGSprite new];s->_playing=YES;atomic_init(&s->_animationActive,true);
 s->_currentAnimation=[[TGAnimation alloc]initWithName:@"blink" frames:@[@10,@20,@30,@40] fps:fps loop:YES];
 s->_animations=[NSMutableDictionary dictionary];s->_animationQueue=[NSMutableArray array];return s;
}
int main(void){@autoreleasepool {
 int failures=0,checks=0;
 for(int h=0;h<3;h++)for(int f=0;f<3;f++) {
  int hz=(int[]){30,60,120}[h];float fps=(float[]){4,1000.0f/167,12}[f],dt=1.0f/hz;
  TGSprite *s=sprite(fps);double elapsed=0;int mismatches=0;
  for(int n=0;n<1800*hz;n++) {
   elapsed+=dt;[s updateAnimation:dt];
   if(s.frame!=(int[]){10,20,30,40}[(NSInteger)(elapsed*fps)%4])mismatches++;
  }
  double drift=(s->_animationTime-elapsed)*1000;
  printf("Obj-C hz=%d fps=%.6f elapsed=%.6f driftMs=%.6f mismatchedFrames=%d\n",hz,fps,elapsed,drift,mismatches);
  checks++;if(fabs(drift)>.001||mismatches!=0)failures++;
  NSInteger before=s.frame;[s updateAnimation:0];checks++;if(s.frame!=before)failures++;
 }
 TGSprite *s=sprite(4);s->_currentAnimation=[[TGAnimation alloc]initWithName:@"once" frames:@[@2,@7] fps:4 loop:NO];
 [s updateAnimation:.6f];[s updateAnimation:.6f];checks++;if(s.frame!=7||s->_playing)failures++;
 TGSprite *chain=sprite(4);chain->_currentAnimation=[[TGAnimation alloc]initWithName:@"a" frames:@[@2,@7] fps:4 loop:NO];
 chain->_animations[@"b"]=[[TGAnimation alloc]initWithName:@"b" frames:@[@8,@9] fps:4 loop:YES];[chain->_animationQueue addObject:@"b"];
 [chain updateAnimation:.6f];checks++;if(chain.frame!=8||chain->_animationTime!=0)failures++;
 printf("Obj-C: %d/%d checks passed\n",checks-failures,checks);return failures?1:0;
}}
'''


def run():
    java_source = (ROOT / 'android/src/ti/game/engine/Sprite.java').read_text()
    objc_source = (ROOT / 'ios/Classes/TGSprite.m').read_text()
    java_clock = re.search(r'private (?:float|double) animationTime = [^;]+;', java_source).group()
    objc_clock = re.search(r'(?:float|double) _animationTime;', objc_source).group()
    java = JAVA.replace('CLOCK', java_clock).replace('UPDATE', method('android/src/ti/game/engine/Sprite.java', 'private synchronized void updateAnimation('))
    objc = OBJC.replace('CLOCK', objc_clock).replace('UPDATE', method('ios/Classes/TGSprite.m', '- (void)updateAnimation:'))
    with tempfile.TemporaryDirectory(prefix='ti-game-animation-clock-') as folder:
        folder = Path(folder)
        (folder / 'AnimationClockCheck.java').write_text(java)
        (folder / 'AnimationClockCheck.m').write_text(objc)
        subprocess.run(['javac', '-d', str(folder), str(ROOT / 'android/src/ti/game/engine/Animation.java'), str(folder / 'AnimationClockCheck.java')], check=True)
        results = [subprocess.run(['java', '-cp', str(folder), 'AnimationClockCheck']).returncode]
        if platform.system() == 'Darwin':
            subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(ROOT / 'ios/Classes'), str(ROOT / 'ios/Classes/TGAnimation.m'), str(folder / 'AnimationClockCheck.m'), '-o', str(folder / 'check')], check=True)
            results.append(subprocess.run([str(folder / 'check')]).returncode)
        return int(any(results))


if __name__ == '__main__':
    raise SystemExit(run())
