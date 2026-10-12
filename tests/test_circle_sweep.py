"""Compile and exercise the actual Java sweptShapesOverlap method in isolation.
Usage: python3 tests/test_circle_sweep.py /path/ti.game [--projectiles]
Requires javac/java. Fixtures supply only Sprite geometry; no Android runtime.
"""
from pathlib import Path
import subprocess, sys, tempfile

root = Path(sys.argv[1])
projectiles = '--projectiles' in sys.argv[2:]
source = (root / 'android/src/ti/game/engine/Scene.java').read_text()
start = source.index('private boolean sweptShapesOverlap(')
opening = source.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end]
harness = '''
public class CircleSweepCheck {
  float[] centerA=new float[2], centerB=new float[2], aabbA=new float[4], aabbB=new float[4];
  static class Sprite {
    boolean circleHitbox=true;
    float x,y,r,frameDeltaX,frameDeltaY,hw,hh;
    Sprite(float x,float y,float r,float dx,float dy) {this.x=x;this.y=y;this.r=r;frameDeltaX=dx;frameDeltaY=dy;}
    void hitCenter(float[] out) {out[0]=x;out[1]=y;}
    float hitRadius(){return r;}
    Sprite(float x,float y,float hw,float hh,float dx,float dy) {
      this(x,y,0,dx,dy);circleHitbox=false;this.hw=hw;this.hh=hh;
    }
    void computeAABB(float[] out){float w=circleHitbox?r:hw,h=circleHitbox?r:hh;
      out[0]=x-w;out[1]=y-h;out[2]=x+w;out[3]=y+h;}
  }
  void shiftedHitCenter(Sprite s,float shift,float[] out){s.hitCenter(out);out[0]+=shift;}
  void shiftedAABB(Sprite s,float shift,float[] out){s.computeAABB(out);out[0]+=shift;out[2]+=shift;}
  boolean sweptHit(float cx,float cy,float dx,float dy,float x0,float y0,float x1,float y1) {
    float lo=0,hi=1;
    float[] p={cx,cy},d={dx,dy},min={x0,y0},max={x1,y1};
    for(int axis=0;axis<2;axis++) {
      if(d[axis]==0) {if(p[axis]<min[axis] || p[axis]>max[axis])return false;}
      else {float a=(min[axis]-p[axis])/d[axis],b=(max[axis]-p[axis])/d[axis];
        lo=Math.max(lo,Math.min(a,b));hi=Math.min(hi,Math.max(a,b));if(lo>hi)return false;}
    }
    return true;
  }
  METHOD
  void check(boolean expected,Sprite mover,Sprite target,float shift,String name) {
    if(sweptShapesOverlap(mover,target,shift)!=expected)throw new AssertionError(name);
  }
  void diagnose(String name,Sprite mover,Sprite target,boolean exact) {
    boolean nativeResult=sweptShapesOverlap(mover,target,0);
    if(nativeResult!=true || exact!=false)throw new AssertionError("Diagnostic no longer reproduces: "+name);
    System.out.println(name+": native=true, exact=false (bounding-box corner false positive)");
  }
  public static void main(String[] args) {
    CircleSweepCheck c=new CircleSweepCheck();
    for(float radius:new float[]{5,10,20}) {
      // Short segment inside the old bounding-square corner but outside the circle.
      c.check(false,new Sprite(radius*.9f,radius*.9f,.47f,1,0),new Sprite(0,0,radius,0,0),0,"corner miss radius "+radius);
      c.check(true,new Sprite(radius+8,0,.47f,2*(radius+8),0),new Sprite(0,0,radius,0,0),0,"fast pass through");
      c.check(false,new Sprite(radius+8,radius+1,.47f,2*(radius+8),0),new Sprite(0,0,radius,0,0),0,"parallel miss");
      c.check(true,new Sprite(radius+8,0,.47f,0,0),new Sprite(0,0,radius,-2*(radius+8),0),0,"moving target");
      c.check(true,new Sprite(radius+8,0,.47f,2*(radius+8),0),new Sprite(1000,0,radius,0,0),-1000,"periodic seam");
      c.check(false,new Sprite(radius+8,0,.47f,2,0),new Sprite(0,0,radius,0,0),0,"short segment stops before target");
    }
    System.out.println("18 native circular sweep cases passed");
    PROJECTILES
  }
}
'''.replace('METHOD', method).replace('PROJECTILES', '''
    // Horizontal paths: their swept rectangles are exact unions, so distance
    // to the nearest point gives the true rectangle-vs-circle answer.
    float r=43.52f;
    Sprite rock=new Sprite(0,0,r,0,0);
    c.diagnose("single 4x16 at (45,45)",new Sprite(45,45,2,8,8,0),rock,35*35+37*37<r*r);
    c.diagnose("laser 8x28 at (45,45)",new Sprite(45,45,4,14,8,0),rock,33*33+31*31<r*r);
    c.diagnose("missile 16x32 at (50,50)",new Sprite(50,50,8,16,8,0),rock,34*34+34*34<r*r);
    c.check(false,new Sprite(45,45,4.8f,8,0),rock,0,"plasma corner remains circular");
    System.out.println("Plasma circular corner miss verified; mixed-shape limitation reproduced, not fixed.");
''' if projectiles else '')
with tempfile.TemporaryDirectory(prefix='asteroids-circle-') as directory:
    path = Path(directory) / 'CircleSweepCheck.java'
    path.write_text(harness)
    subprocess.run(['javac', str(path)], check=True)
    subprocess.run(['java', '-cp', directory, 'CircleSweepCheck'], check=True)
