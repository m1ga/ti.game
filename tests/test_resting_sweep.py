#!/usr/bin/env python3
"""Compile real solid sweeps; preserve tangential motion at float-sized contacts.
Only tile lookup and sprite geometry are stubbed. Both native twins execute.
Run: python3 tests/test_resting_sweep.py
"""
from pathlib import Path
import platform, subprocess, tempfile
import test_circle_sweep as fixture
ROOT=Path(__file__).resolve().parents[1]
def method(source,signature):return fixture.method(source,signature)
def run():
    js=(ROOT/'android/src/ti/game/engine/Scene.java').read_text();os=(ROOT/'ios/Classes/TGScene.m').read_text()
    jm=['private void sweepAgainstSolids(','private float segmentVsCircle(','private boolean sweptHit(','private static boolean segmentVsAabb(','private static void shiftedHitCenter(','private static void shiftedAABB(','private static void shiftedHitBox(']
    om=['- (void)sweepAgainstSolids:','- (float)segmentFromX:','- (BOOL)sweptHitFromX:','- (void)shiftedHitCenter:','- (void)shiftedAABB:','- (void)shiftedHitBox:']
    java=fixture.JAVA[:fixture.JAVA.index(' int checks,failures;')]
    java=java.replace('public class SweepCheck {','import java.util.*;\npublic class SweepCheck {\n List<Sprite> tagged=new ArrayList<>(); static class TileLayer{}\n float periodicOffsetX(Sprite a,Sprite b){return 0;}\n float sweepAgainstTiles(Sprite s,List<TileLayer> l,Set<String> g,float cx,float cy,float dx,float dy,float hw,float hh){return 1;}')
    java=java.replace('static class Sprite {','static class Sprite {\n static final int SOLID_BLOCK=0; int solidMode; boolean visible=true,oneWay; String collisionGroup="wall"; float velocityY;')
    java+=r'''
 int checks,failures;
 void check(float startX,float startY,float dx,float dy,float hx,float hy,boolean rest,String name){
 Sprite wall=new Sprite(1,0,0,0,hx,hy,0,0,0),s=new Sprite(1,startX+dx,startY+dy,0,1,1,0,dx,dy);s.velocityY=dy;
 tagged.clear();tagged.add(wall);float endX=s.x,endY=s.y;
 sweepAgainstSolids(s,tagged,Collections.emptyList(),Collections.singleton("wall"));checks++;
 boolean unchanged=Math.abs(s.x-endX)<.0001f&&Math.abs(s.y-endY)<.0001f;
 if(unchanged!=rest){failures++;System.err.println("FAIL Java "+name+" end="+s.x+","+s.y);}
 }
 public static void main(String[] args){SweepCheck t=new SweepCheck();CASES
 System.out.println("Java: "+(t.checks-t.failures)+"/"+t.checks+" passed");if(t.failures>0)System.exit(1);}}
'''
    objc=fixture.OBJC[:fixture.OBJC.index('static int checks,failures;')]
    objc=objc.replace('#import <math.h>','#import <math.h>\n#import <float.h>\n#define TGSolidBlock 0\n@interface TGTileLayer:NSObject @end')
    objc=objc.replace('@property BOOL circleHitbox,obbHitbox;','@property BOOL circleHitbox,obbHitbox,visible,oneWay;\n@property int solidMode;\n@property NSString *collisionGroup;\n@property float velocityY;')
    objc=objc.replace('@implementation TGScene\n','@implementation TGScene\n- (float)periodicOffsetFrom:(TGSprite *)a to:(TGSprite *)b{return 0;}\n- (float)sweepAgainstTiles:(TGSprite *)s layers:(NSArray *)l groups:(NSSet *)g cx:(float)x cy:(float)y dx:(float)dx dy:(float)dy hw:(float)hw hh:(float)hh{return 1;}\n')
    objc+=r'''
static int checks,failures;
static void check(TGScene *t,float x,float y,float dx,float dy,float hx,float hy,BOOL rest,const char *name){
 TGSprite *wall=sprite(1,0,0,0,hx,hy,0,0,0),*s=sprite(1,x+dx,y+dy,0,1,1,0,dx,dy);wall.visible=YES;wall.collisionGroup=@"wall";s.velocityY=dy;
 float endX=s.x,endY=s.y;[t sweepAgainstSolids:s inList:@[wall] layers:@[] groups:[NSSet setWithObject:@"wall"]];checks++;
 BOOL unchanged=fabsf(s.x-endX)<.0001f&&fabsf(s.y-endY)<.0001f;
 if(unchanged!=rest){failures++;fprintf(stderr,"FAIL Obj-C %s end=%f,%f\n",name,s.x,s.y);}
}
int main(void){@autoreleasepool{TGScene *t=[TGScene new];CASES
printf("Obj-C: %d/%d passed\n",checks-failures,checks);return failures?1:0;}}
'''
    cases=[]
    for eps in (0,0.000001,0.000002):
        cases.extend([(0,-6-eps,10,.1,100,5,True,'floor tangent'),(-6-eps,0,.1,10,5,100,True,'wall tangent'),(0,-6-eps,10,20,100,5,eps==0,'full crossing'),(-6-eps,0,20,10,5,100,eps==0,'wall crossing')])
    cases.extend([(0,-6.000001,10,.5,100,5,True,'shallow depth limit'),(0,-6.000001,10,.5001,100,5,False,'beyond shallow depth limit'),(0,-1.100001,10,5,100,.1,False,'thin solid full crossing'),(0,-1.100001,10,1.8,100,.1,False,'thin solid deep entry'),(0,-6.000001,10,.005,100,5,True,'tiny normal floor'),(-6.000001,0,.005,10,5,100,True,'tiny normal wall'),(0,6.000001,10,-.005,100,5,True,'tiny normal ceiling'),(6.000001,0,-.005,10,5,100,True,'tiny normal right wall'),(0,-6.000001,10,9,100,5,False,'deep end overlap'),(-6.000001,0,9,10,5,100,False,'deep wall overlap'),(0,-7,10,2,100,5,False,'new collision'),(0,-7,10,.1,100,5,True,'clear movement'),(0,-6.01,10,.1,100,5,False,'nontrivial gap')])
    jcases=[];ocases=[]
    for *values,rest,name in cases:
        nums=','.join(str(v)+'f' if '.' in str(v) else str(v)+'.0f' for v in values)
        jcases.append('t.check('+nums+','+str(rest).lower()+',"'+name+'");')
        ocases.append('check(t,'+nums+','+('YES' if rest else 'NO')+',"'+name+'");')
    java=java.replace('METHODS','\n'.join(method(js,s) for s in jm)).replace('CASES','\n'.join(jcases))
    slabStart=os.index('static BOOL TGSegmentVsAabb(',os.index('- (BOOL)sweptHitFromX:'))
    objc=objc.replace('SLAB',method(os[slabStart:],'static BOOL TGSegmentVsAabb(')).replace('METHODS','\n'.join(method(os,s) for s in om)).replace('CASES','\n'.join(ocases))
    result=[]
    with tempfile.TemporaryDirectory(prefix='ti-game-rest-') as directory:
        folder=Path(directory);(folder/'SweepCheck.java').write_text(java)
        subprocess.run(['javac',str(folder/'SweepCheck.java')],check=True);result.append(subprocess.run(['java','-cp',directory,'SweepCheck']).returncode)
        if platform.system()=='Darwin':
            (folder/'SweepCheck.m').write_text(objc);subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(folder/'SweepCheck.m'),'-o',str(folder/'check')],check=True);result.append(subprocess.run([str(folder/'check')]).returncode)
    return int(any(result))
if __name__=='__main__':raise SystemExit(run())
