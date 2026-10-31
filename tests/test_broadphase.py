#!/usr/bin/env python3
"""Compile the production Broadphase against a stub Sprite and compare its
candidates with an exact pair scan.
Run: python3 tests/test_broadphase.py [repository]
Requires a JDK. The Objective-C twin (TGBroadphase.m) is a line-for-line port
and is not compiled here. Checks, over random scenes with and without world
wrap: every exactly overlapping pair is a candidate (queryShape, querySwept,
and the rect query), candidates are unique and stamped, and the guarantee
survives moving every sprite by its own frame delta plus the slack after the
build (the push-out case the inflation exists for).
"""
from pathlib import Path
import subprocess, sys, tempfile
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]

STUB = r'''
package ti.game.engine;
public class Sprite {
	public float x, y, w, h;
	public boolean circleHitbox, wrapWorldX, screenFixed;
	public float frameDeltaX, frameDeltaY;
	int taggedIndex = -1;
	int broadphaseStamp = 0;
	public void hitCenter(float[] out) { out[0] = x; out[1] = y; }
	public float hitRadius() { return Math.min(w, h) * 0.5f; }
	public void computeAABB(float[] out) {
		out[0] = x - w / 2f; out[1] = y - h / 2f; out[2] = x + w / 2f; out[3] = y + h / 2f;
	}
	public void shape(float[] out) {
		if (circleHitbox) { float r = hitRadius(); out[0] = x - r; out[1] = y - r; out[2] = x + r; out[3] = y + r; }
		else computeAABB(out);
	}
}
'''

HARNESS = r'''
package ti.game.engine;
import java.util.*;
public class Harness {
	static final float MARGIN = 4f;
	static boolean overlaps(float[] a, float[] b, float bShiftX) {
		return a[0] <= b[2] + bShiftX && a[2] >= b[0] + bShiftX && a[1] <= b[3] && a[3] >= b[1];
	}
	static float nearestShift(float ax, float bx, float w) {
		return w > 0f ? (float) Math.floor((ax - bx) / w + 0.5f) * w : 0f;
	}
	static int failures = 0;
	static void check(String what, boolean ok) { if (!ok) { failures++; System.out.println("FAIL " + what); } }
	public static void main(String[] args) {
		Random rnd = new Random(7);
		long candidateSum = 0, pairSum = 0, queries = 0;
		for (int trial = 0; trial < 60; trial++) {
			float wrapWidth = (trial % 3 == 0) ? 0f : 3000f;
			int n = 1 + rnd.nextInt(trial < 10 ? 12 : 220);
			List<Sprite> tagged = new ArrayList<>();
			for (int i = 0; i < n; i++) {
				Sprite s = new Sprite();
				boolean huge = rnd.nextInt(40) == 0;
				s.w = huge ? 4000f + rnd.nextFloat() * 4000f : 2f + rnd.nextFloat() * 180f;
				s.h = huge ? 300f : 2f + rnd.nextFloat() * 180f;
				s.circleHitbox = rnd.nextInt(3) == 0;
				s.wrapWorldX = wrapWidth > 0f && rnd.nextInt(4) != 0;
				s.screenFixed = rnd.nextInt(30) == 0;
				s.x = s.wrapWorldX ? rnd.nextFloat() * wrapWidth : -1500f + rnd.nextFloat() * 6000f;
				s.y = -500f + rnd.nextFloat() * 2500f;
				s.frameDeltaX = rnd.nextInt(3) == 0 ? (rnd.nextFloat() - 0.5f) * 120f : 0f;
				s.frameDeltaY = rnd.nextInt(3) == 0 ? (rnd.nextFloat() - 0.5f) * 120f : 0f;
				tagged.add(s);
			}
			Broadphase bp = new Broadphase();
			bp.rebuild(tagged, wrapWidth);
			for (int pass = 0; pass < 2; pass++) {
				if (pass == 1) {
					// Everything drifts by at most its own inflation after the build
					for (Sprite s : tagged) {
						s.x += (rnd.nextFloat() * 2f - 1f) * (Math.abs(s.frameDeltaX) + MARGIN);
						s.y += (rnd.nextFloat() * 2f - 1f) * (Math.abs(s.frameDeltaY) + MARGIN);
					}
				}
				float[] a = new float[4], b = new float[4], q = new float[4];
				for (Sprite s : tagged) {
					for (int mode = 0; mode < 3; mode++) {
						s.shape(a);
						List<Sprite> near;
						if (mode == 0) {
							near = bp.queryShape(s);
							System.arraycopy(a, 0, q, 0, 4);
						} else if (mode == 1) {
							near = bp.querySwept(s);
							q[0] = Math.min(a[0], a[0] - s.frameDeltaX); q[1] = Math.min(a[1], a[1] - s.frameDeltaY);
							q[2] = Math.max(a[2], a[2] - s.frameDeltaX); q[3] = Math.max(a[3], a[3] - s.frameDeltaY);
						} else {
							s.computeAABB(q);
							near = bp.query(s, q[0], q[1], q[2], q[3]);
						}
						queries++;
						candidateSum += near.size();
						Set<Sprite> set = new HashSet<>(near);
						check("duplicates", set.size() == near.size());
						int stamp = bp.stamp();
						for (Sprite c : near) check("stamp", c.broadphaseStamp == stamp);
						for (Sprite t : tagged) {
							t.shape(b);
							boolean periodic = wrapWidth > 0f && s.wrapWorldX && t.wrapWorldX && !s.screenFixed && !t.screenFixed;
							float shift = periodic ? nearestShift(s.x, t.x, wrapWidth) : 0f;
							if (overlaps(q, b, shift)) {
								pairSum++;
								check("missing candidate (trial " + trial + ", pass " + pass + ", mode " + mode + ")", set.contains(t));
							} else if (!set.contains(t) && t != s) {
								check("stale stamp", t.broadphaseStamp != stamp);
							}
						}
					}
				}
			}
		}
		System.out.printf("queries=%d avgCandidates=%.1f avgExactPairs=%.2f%n", queries,
			candidateSum / (double) queries, pairSum / (double) queries);
		if (failures > 0) { System.out.println(failures + " failures"); System.exit(1); }
		System.out.println("broadphase ok");
	}
}
'''

def main():
    src = (ROOT / 'android/src/ti/game/engine/Broadphase.java').read_text()
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / 'ti/game/engine'
        d.mkdir(parents=True)
        (d / 'Broadphase.java').write_text(src)
        (d / 'Sprite.java').write_text(STUB)
        (d / 'Harness.java').write_text(HARNESS)
        subprocess.run(['javac', '-d', tmp, str(d / 'Broadphase.java'), str(d / 'Sprite.java'),
                        str(d / 'Harness.java')], check=True)
        out = subprocess.run(['java', '-cp', tmp, 'ti.game.engine.Harness'], capture_output=True, text=True)
        print(out.stdout.strip())
        if out.returncode != 0:
            print(out.stderr.strip())
            sys.exit(1)

if __name__ == '__main__':
    main()
