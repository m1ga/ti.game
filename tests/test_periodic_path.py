#!/usr/bin/env python3
"""Run real Sprite.update and Path.advance through seam crossings on both twins.
Render collaborators are stubs; path interpolation and frame deltas are native.
Run: python3 tests/test_periodic_path.py
"""
from pathlib import Path
import platform, subprocess, tempfile
import test_linear_damping as fixture
ROOT = Path(__file__).resolve().parents[1]

def extract(file, signature):
    return fixture.method(file, signature)

def run():
    java = fixture.JAVA
    java = java.replace('public class DampingCheck {', 'import ti.game.engine.Path;\npublic class DampingCheck {')
    java = java.replace(' static class Path { boolean rotate; boolean advance(float dt,float[] out){return false;} }', '')
    java = java.replace('static class Scene { boolean worldWrapXEnabled; float nearestWorldX(float x,float reference){return x;} }', 'static class Scene { boolean worldWrapXEnabled; float worldWrapWidth(){return 1000;} '+extract('android/src/ti/game/engine/Scene.java','public float nearestWorldX(')+' }')
    java = java.replace('boolean carMode,', 'boolean screenFixed,carMode,')
    start = java.index(' public static void main(')
    java = java[:start] + r'''
 public static void main(String[] args){
 for(float step:new float[]{18,-18,620,-620}) for(boolean wrapped:new boolean[]{false,true}) {
 Sprite s=new Sprite();s.x=step>0?990:10;s.wrapWorldX=wrapped;s.scene=new Scene();s.scene.worldWrapXEnabled=wrapped;
 float original=s.x;s.path=Path.build(new float[]{original,original+step*8},new float[]{0,0},0,false,true,Math.abs(step)*60);
 for(int i=0;i<6;i++) {s.update(1f/60);close(s.frameDeltaX,step,"path delta step="+step+" wrap="+wrapped+" frame="+i);close(s.y,0,"path y");if(wrapped)s.x=(s.x%1000+1000)%1000;}
 }
 Sprite fixed=new Sprite();fixed.x=990;fixed.screenFixed=true;fixed.wrapWorldX=true;fixed.scene=new Scene();fixed.scene.worldWrapXEnabled=true;
 fixed.path=Path.build(new float[]{990,1100},new float[]{0,0},0,false,false,1080);fixed.update(1f/60);close(fixed.x,1008,"screen-fixed path is absolute");
 System.out.println("Java: "+(checks-failures)+"/"+checks+" passed");if(failures>0)System.exit(1);
 }}
'''
    java=java.replace('UPDATE',extract('android/src/ti/game/engine/Sprite.java','public void update(float dt)')).replace('CAR',extract('android/src/ti/game/engine/Sprite.java','private void updateCar(float dt)')).replace('FINISH',extract('android/src/ti/game/engine/Sprite.java','void finishDamping('))
    objc=fixture.OBJC
    start=objc.index('@interface TGPath:');end=objc.index('@interface TGSprite:',start)
    objc=objc[:start]+'#import "TGPath.h"\n'+objc[end:]
    objc=objc.replace('@implementation TGScene\n- (float)nearestWorldX:(float)x reference:(float)reference{return x;}\n@end','@implementation TGScene\n- (float)worldWrapWidth{return 1000;}\n'+extract('ios/Classes/TGScene.m','- (float)nearestWorldX:')+'\n@end')
    start=objc.index('int main(void)')
    objc=objc[:start]+r'''
int main(void){@autoreleasepool {
 for(int d=0;d<4;d++) for(int wrapped=0;wrapped<2;wrapped++) {
 float step=(float[]){18,-18,620,-620}[d];TGSprite *s=sprite();s.x=step>0?990:10;s.wrapWorldX=wrapped;s.scene=[TGScene new];s.scene.worldWrapXEnabled=wrapped;
 float xs[]={s.x,s.x+step*8},ys[]={0,0};s.path=[TGPath buildWithPointsX:xs y:ys count:2 smoothing:0 loop:NO rotate:YES speed:fabsf(step)*60];
 for(int i=0;i<6;i++){[s update:1.0f/60];closeEnough(s.frameDeltaX,step,"periodic path delta");closeEnough(s.y,0,"path y");if(wrapped)s.x=fmodf(fmodf(s.x,1000)+1000,1000);}
 }
 TGSprite *fixed=sprite();fixed.x=990;fixed.screenFixed=YES;fixed.wrapWorldX=YES;fixed.scene=[TGScene new];fixed.scene.worldWrapXEnabled=YES;
 float xs[]={990,1100},ys[]={0,0};fixed.path=[TGPath buildWithPointsX:xs y:ys count:2 smoothing:0 loop:NO rotate:NO speed:1080];[fixed update:1.0f/60];closeEnough(fixed.x,1008,"screen fixed absolute");
 printf("Obj-C: %d/%d passed\n",checks-failures,checks);return failures?1:0;}}
'''
    fields='x y velocityX velocityY rotation angularVelocity thrust gravity gravityX linearDamping maxSpeed throttle enginePower steering turnRate grip drag skidThreshold frameAccelX frameAccelY frameDeltaX frameDeltaY wrapShift wrapX flashRemaining'.split()
    objc=objc.replace('FLOATS','\n'.join('@property float '+f+';' for f in fields)).replace('BOOLS','\n'.join('@property BOOL '+f+';' for f in 'carMode skidMarks drifting wrapWorldX screenFixed'.split()))
    objc=objc.replace('UPDATE',extract('ios/Classes/TGSprite.m','- (void)update:(float)dt')).replace('CAR',extract('ios/Classes/TGSprite.m','- (void)updateCar:(float)dt')).replace('FINISH',extract('ios/Classes/TGSprite.m','- (void)finishDamping'))
    # Repeated float stepping may accumulate sub-millipixel error.
    java=java.replace('<.0001f','<.002f');objc=objc.replace('<.0001f','<.002f')
    with tempfile.TemporaryDirectory(prefix='ti-game-path-') as directory:
        folder=Path(directory);(folder/'DampingCheck.java').write_text(java);(folder/'DampingCheck.m').write_text(objc)
        subprocess.run(['javac','-d',directory,str(ROOT/'android/src/ti/game/engine/Path.java'),str(folder/'DampingCheck.java')],check=True)
        result=[subprocess.run(['java','-cp',directory,'DampingCheck']).returncode]
        if platform.system()=='Darwin':
            subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-I',str(ROOT/'ios/Classes'),str(ROOT/'ios/Classes/TGPath.m'),str(folder/'DampingCheck.m'),'-o',str(folder/'check')],check=True)
            result.append(subprocess.run([str(folder/'check')]).returncode)
        return int(any(result))
if __name__=='__main__':raise SystemExit(run())
