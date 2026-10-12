#!/usr/bin/env python3
"""Compile production swept-overlap methods in scalar Java/Objective-C fixtures.
Run: python3 tests/test_circle_sweep.py [repository]
Requires JDK, and macOS/clang for Objective-C. Sprite geometry is stubbed.
An independent convex-distance oracle checks translation, without rendering.
"""
from pathlib import Path
import math, platform, random, subprocess, sys, tempfile
ROOT = Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]

def method(source, signature):
    start=source.index(signature); brace=source.index('{',start); end=brace+1; depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end]

# Shape (circle=0, AABB=1, OBB=2), centre, radius, half extents, radians, frame delta.
def circle(x,y,r,dx=0,dy=0): return (0,x,y,r,r,r,0,dx,dy)
def box(x,y,hx,hy,dx=0,dy=0,angle=0,oriented=False): return (2 if oriented else 1,x,y,0,hx,hy,angle,dx,dy)
CASES=[]
def case(expected,a,b,name,offset=0): CASES.append((expected,a,b,offset,name))
for r in (5,10,20):
    case(False,circle(r*.9,r*.9,.47,1),circle(0,0,r),'circle corner miss')
    case(True,circle(r+8,0,.47,2*(r+8)),circle(0,0,r),'circle crossing')
    case(False,circle(r+8,r+1,.47,2*(r+8)),circle(0,0,r),'circle parallel miss')
    case(True,circle(r+8,0,.47),circle(0,0,r,-2*(r+8)),'moving circle')
    case(True,circle(r+8,0,.47,2*(r+8)),circle(1000,0,r),'circle periodic',-1000)
    case(False,circle(r+8,0,.47,2),circle(0,0,r),'circle stops short')
for hx,hy,x,y in ((2,8,45,45),(4,14,45,45),(8,16,50,50)):
    a=box(x,y,hx,hy,8); b=circle(0,0,43.52)
    case(False,a,b,'projectile corner miss'); case(False,b,a,'reverse projectile corner miss')
for oriented in (False,True):
    for angle in ((0,.6,1.2) if oriented else (0,)):
        c,s=math.cos(angle),math.sin(angle)
        def world(x,y): return x*c-y*s,x*s+y*c
        for x,y,dx,dy,expected,name in (
            (30,0,60,0,True,'face crossing'),(30,13,60,0,False,'parallel miss'),
            (30,11.9,60,0,True,'shallow face hit'),(9,11,1,0,False,'rounded corner miss'),
            (7,10,1,0,True,'rounded corner hit'),(1,1,20,0,True,'ends inside'),
            (30,0,1,0,False,'stops short'),(30,0,0,0,False,'no relative motion')):
            ex,ey=world(x,y); vx,vy=world(dx,dy)
            a=circle(ex,ey,4,vx,vy); b=box(0,0,5,8,angle=angle,oriented=oriented)
            case(expected,a,b,name); case(expected,b,a,'reverse '+name)
        ex,ey=world(30,0); vx,vy=world(-60,0)
        case(True,circle(ex,ey,4),box(0,0,5,8,vx,vy,angle,oriented),'moving box')
        case(True,box(ex,ey,5,8,-vx,-vy,angle,oriented),circle(1000,0,4),'mixed periodic',-1000)
# Exact face tangency retains the inclusive mixed/AABB sweep boundary.
case(True,circle(30,12,4,60),box(0,0,5,8),'face tangent')
case(False,circle(30,12.01,4,60),box(0,0,5,8),'outside face tangent')
case(True,box(10000,45,2,8,20000),circle(0,0,43.52),'long mixed crossing')
case(False,box(10000,100,2,8,20000),circle(0,0,43.52),'long mixed miss')
case(True,circle(1000,0,4),box(30,0,5,8,60),'reverse periodic',1000)
case(True,box(30,0,2,8,60),box(0,0,4,4),'rect crossing')
case(False,box(30,20,2,8,60),box(0,0,4,4),'rect miss')

def margin(a,b):
    """Minimize point-to-box squared distance; no slab or circle decomposition."""
    ball,rect=(a,b) if a[0]==0 else (b,a)
    x,y=ball[1]-rect[1],ball[2]-rect[2]; dx,dy=ball[7]-rect[7],ball[8]-rect[8]
    c,s=math.cos(rect[6]),math.sin(rect[6])
    if rect[0]==2:
        x,y=x*c+y*s,-x*s+y*c; dx,dy=dx*c+dy*s,-dx*s+dy*c; hx,hy=rect[4:6]
    else: hx,hy=rect[4]*abs(c)+rect[5]*abs(s),rect[4]*abs(s)+rect[5]*abs(c)
    def distance(t): return max(abs(x-dx*(1-t))-hx,0)**2+max(abs(y-dy*(1-t))-hy,0)**2
    lo,hi=0.,1.
    for _ in range(100):
        t1,t2=(2*lo+hi)/3,(lo+2*hi)/3
        if distance(t1)<distance(t2): hi=t2
        else: lo=t1
    return min(distance(0),distance(1),distance((lo+hi)/2))-ball[3]**2
rng=random.Random(20261012)
for i in range(300):
    a=circle(rng.uniform(-80,80),rng.uniform(-80,80),rng.uniform(1,30),rng.uniform(-100,100),rng.uniform(-100,100))
    b=box(rng.uniform(-20,20),rng.uniform(-20,20),rng.uniform(1,20),rng.uniform(1,20),rng.uniform(-20,20),rng.uniform(-20,20),rng.uniform(-math.pi,math.pi),i%2==0)
    m=margin(a,b)
    if abs(m)>.05:
        case(m<0,a,b,'oracle '+str(i)); case(m<0,b,a,'reverse oracle '+str(i))

JAVA=r'''
public class SweepCheck {
 float[] centerA=new float[2],centerB=new float[2],aabbA=new float[4],aabbB=new float[4],boxB=new float[5],sweptResult=new float[2];
 static class Sprite {
  boolean circleHitbox,obbHitbox; float x,y,r,hx,hy,angle,frameDeltaX,frameDeltaY;
  Sprite(float shape,float x,float y,float r,float hx,float hy,float angle,float dx,float dy){circleHitbox=shape==0;obbHitbox=shape==2;this.x=x;this.y=y;this.r=r;this.hx=hx;this.hy=hy;this.angle=angle;frameDeltaX=dx;frameDeltaY=dy;}
  void hitCenter(float[] out){out[0]=x;out[1]=y;} float hitRadius(){return r;}
  void hitBox(float[] out){out[0]=x;out[1]=y;out[2]=hx;out[3]=hy;out[4]=angle;}
  void computeAABB(float[] out){float c=(float)Math.abs(Math.cos(angle)),s=(float)Math.abs(Math.sin(angle));float w=hx*c+hy*s,h=hx*s+hy*c;out[0]=x-w;out[1]=y-h;out[2]=x+w;out[3]=y+h;}
 }
 METHODS
 int checks,failures;
 void check(boolean expected,Sprite a,Sprite b,float offset,String name){checks++;boolean got=sweptShapesOverlap(a,b,offset);if(got!=expected){failures++;System.err.println(name+": expected="+expected+", got="+got);}}
 public static void main(String[] args){SweepCheck t=new SweepCheck();CASES
 System.out.println("Java: "+(t.checks-t.failures)+"/"+t.checks+" passed");if(t.failures>0)System.exit(1);}
}
'''
OBJC=r'''
#import <Foundation/Foundation.h>
#import <math.h>
@interface TGSprite:NSObject
@property BOOL circleHitbox,obbHitbox;
@property float x,y,r,hx,hy,angle,frameDeltaX,frameDeltaY;
@end
@implementation TGSprite
- (void)hitCenter:(float *)out{out[0]=self.x;out[1]=self.y;}
- (float)hitRadius{return self.r;}
- (void)hitBox:(float *)out{out[0]=self.x;out[1]=self.y;out[2]=self.hx;out[3]=self.hy;out[4]=self.angle;}
- (void)computeAABB:(float *)out{float c=fabsf(cosf(self.angle)),s=fabsf(sinf(self.angle));float w=self.hx*c+self.hy*s,h=self.hx*s+self.hy*c;out[0]=self.x-w;out[1]=self.y-h;out[2]=self.x+w;out[3]=self.y+h;}
@end
static TGSprite *sprite(float shape,float x,float y,float r,float hx,float hy,float angle,float dx,float dy){TGSprite *s=[TGSprite new];s.circleHitbox=shape==0;s.obbHitbox=shape==2;s.x=x;s.y=y;s.r=r;s.hx=hx;s.hy=hy;s.angle=angle;s.frameDeltaX=dx;s.frameDeltaY=dy;return s;}
SLAB
@interface TGScene:NSObject {float _centerA[2],_centerB[2],_aabbA[4],_aabbB[4],_boxB[5],_sweptResult[2];}
@end
@implementation TGScene
METHODS
@end
static int checks,failures;
static void check(TGScene *t,BOOL expected,TGSprite *a,TGSprite *b,float offset,const char *name){checks++;BOOL got=[t sweptShapesOverlap:a with:b offsetX:offset];if(got!=expected){failures++;fprintf(stderr,"%s: expected=%d, got=%d\n",name,expected,got);}}
int main(void){@autoreleasepool{TGScene *t=[TGScene new];CASES
printf("Obj-C: %d/%d passed\n",checks-failures,checks);return failures?1:0;}}
'''
def numbers(values): return ','.join(f'{v:.9f}f' for v in values)
def run():
    js=(ROOT/'android/src/ti/game/engine/Scene.java').read_text(); os=(ROOT/'ios/Classes/TGScene.m').read_text()
    jm=['private boolean sweptShapesOverlap(','private float segmentVsCircle(','private boolean sweptHit(','private static boolean segmentVsAabb(','private static void shiftedHitCenter(','private static void shiftedAABB(','private static void shiftedHitBox(']
    om=['- (BOOL)sweptShapesOverlap:','- (float)segmentFromX:','- (BOOL)sweptHitFromX:','- (void)shiftedHitCenter:','- (void)shiftedAABB:','- (void)shiftedHitBox:']
    if 'private boolean sweptCircleBoxOverlap(' in js: jm.append('private boolean sweptCircleBoxOverlap(')
    if '- (BOOL)sweptCircleBoxFromX:' in os: om.append('- (BOOL)sweptCircleBoxFromX:')
    jc=[]; oc=[]
    for expected,a,b,offset,name in CASES:
        jc.append(f't.check({str(expected).lower()},new Sprite({numbers(a)}),new Sprite({numbers(b)}),{offset:.9f}f,"{name}");')
        oc.append(f'check(t,{"YES" if expected else "NO"},sprite({numbers(a)}),sprite({numbers(b)}),{offset:.9f}f,"{name}");')
    failures=[]
    with tempfile.TemporaryDirectory(prefix='ti-game-sweep-') as directory:
        folder=Path(directory)
        java=JAVA.replace('METHODS','\n'.join(method(js,s) for s in jm)).replace('CASES','\n'.join(jc))
        (folder/'SweepCheck.java').write_text(java)
        subprocess.run(['javac',str(folder/'SweepCheck.java')],check=True)
        failures.append(subprocess.run(['java','-cp',directory,'SweepCheck']).returncode)
        if platform.system()=='Darwin':
            start=os.index('static BOOL TGSegmentVsAabb(',os.index('- (BOOL)sweptHitFromX:'))
            objc=OBJC.replace('SLAB',method(os[start:],'static BOOL TGSegmentVsAabb(')).replace('METHODS','\n'.join(method(os,s) for s in om)).replace('CASES','\n'.join(oc))
            (folder/'SweepCheck.m').write_text(objc)
            subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(folder/'SweepCheck.m'),'-o',str(folder/'check')],check=True)
            failures.append(subprocess.run([str(folder/'check')]).returncode)
        else: print('SKIP Obj-C: requires macOS')
    return int(any(failures))
if __name__=='__main__': raise SystemExit(run())
