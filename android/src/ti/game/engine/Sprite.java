package ti.game.engine;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.CopyOnWriteArrayList;

import org.appcelerator.kroll.KrollProxy;

/**
 * Native sprite living in the renderer's scene graph. All per-frame state
 * (position, animation, tweens) is owned here so the render loop never has
 * to cross the Kroll bridge. The JS-facing SpriteProxy only writes into
 * this object and receives high-level events back.
 *
 * Coordinate system: top-left origin, y-down, pixels. (x, y) positions the
 * anchor point (default 0.5/0.5 = sprite center). Rotation is in degrees,
 * positive = clockwise on screen.
 */
public class Sprite
{
	// Transform
	public volatile float x = 0f;
	public volatile float y = 0f;
	public volatile float width = 0f;   // 0 = use sheet frame size
	public volatile float height = 0f;
	public volatile float scaleX = 1f;
	public volatile float scaleY = 1f;
	public volatile float rotation = 0f; // degrees
	public volatile float anchorX = 0.5f;
	public volatile float anchorY = 0.5f;
	public volatile float opacity = 1f;
	public volatile boolean visible = true;
	// Snap only the rendered anchor to the framebuffer pixel grid. Physics,
	// collisions and the live x/y values remain subpixel floats.
	public volatile boolean pixelSnap = false;
	public volatile int zIndex = 0;

	// Screen-fixed: (x, y) are surface coordinates and the sprite ignores
	// camera position, zoom and shake — HUD scores, buttons, overlays.
	// Touch input maps back automatically.
	public volatile boolean screenFixed = false;

	// Parallax: how much camera travel (and shake) moves this sprite —
	// 1 = normal world sprite, 0.5 = half-speed background layer, 0 =
	// pinned to the view (but still zooming around the view center,
	// unlike screenFixed). Affects rendering and touch mapping only;
	// x/y, physics and collisions stay in plain world coordinates.
	public volatile float scrollFactor = 1f;

	// Attachment: while attachTarget is set, this sprite is pinned to the
	// target natively — each frame, after physics and solid resolution, its
	// x/y are driven from the target's final position plus the offset, so a
	// name tag or health bar tracks its owner with no per-frame JS. With
	// attachRotate the sprite also copies the target's rotation and the
	// offset swings around it (turrets, hats). Direct x/y writes, velocity
	// and position tweens are overwritten while attached; an active drag
	// wins over the attachment, like it does over moving platforms. The
	// target's opacity multiplies into attached sprites (attachOpacity),
	// so fades cascade down a chain. Removing the target from the scene
	// removes its attached sprites too (Scene.removeWithAttachments).
	// Applied by Scene.applyAttachments.
	public volatile Sprite attachTarget;
	public volatile float attachOffsetX = 0f;
	public volatile float attachOffsetY = 0f;
	public volatile boolean attachRotate = false;
	// Inherited opacity: the target's effective opacity, copied by
	// Scene.applyAttachments each frame and multiplied with the sprite's
	// own opacity wherever it is drawn or hit-tested — a fade on the
	// owner fades its tags too, without clobbering their own opacity.
	// 1 while not attached (reset on every detach path).
	public volatile float attachOpacity = 1f;

	/** Own opacity times the attached target's (chained). */
	public float effectiveOpacity()
	{
		return opacity * attachOpacity;
	}

	// Tint: multiplies the frame's colors (white = art unchanged) — damage
	// flashes, team colors, day/night shading. Parsed 0..1 channels.
	public volatile float tintR = 1f;
	public volatile float tintG = 1f;
	public volatile float tintB = 1f;

	// Flash: a solid-color overlay on the sprite's silhouette that fades
	// out over flashDuration (damage hits, invincibility blinks). Set via
	// flash(); flashRemaining counts down natively each frame, 0 = off.
	public volatile float flashR = 1f;
	public volatile float flashG = 1f;
	public volatile float flashB = 1f;
	public volatile float flashDuration = 0f;  // seconds
	public volatile float flashRemaining = 0f; // seconds

	// Blend mode (SpriteBatch.BLEND_*): add for glows/fire/lasers,
	// multiply for shadows/darkening, screen for soft light. The batcher
	// flushes once per blend-mode change, so group same-blend sprites by
	// zIndex.
	public volatile int blendMode = SpriteBatch.BLEND_NORMAL;

	// Glow: when glowBlur > 0 a tinted, blurred silhouette of the current
	// frame draws behind the sprite (selection highlights, power-ups).
	// glowBlur is the blur radius in px; color as parsed 0..1 channels.
	public volatile float glowBlur = 0f;
	public volatile float glowOpacity = 1f; // halo strength 0..1
	public volatile float glowR = 1f;
	public volatile float glowG = 1f;
	public volatile float glowB = 1f;

	// Depth sorting for top-down scenes: within the same zIndex, ySort
	// sprites draw in order of their bottom edge (feet/base), so a player
	// below a tree renders in front of it and above renders behind.
	public volatile boolean ySort = false;

	// Interaction flags
	public volatile boolean draggable = false;

	// True while a finger actively drags this sprite (set by the touch
	// controller). Constraints like the rope tether yield at the other
	// end instead of fighting the finger.
	public volatile boolean dragged = false;
	public volatile boolean pinchable = false;
	public volatile boolean rotatable = false;

	// false = invisible to hit-testing: touches pass through to sprites
	// underneath (falling blocks over a button, decorative overlays)
	public volatile boolean touchEnabled = true;

	// Tile the sheet frame across the sprite instead of stretching it
	// (per axis). Needs a sheet with repeat=true whose frame spans the
	// whole texture.
	public volatile boolean tileRepeatX = false;
	public volatile boolean tileRepeatY = false;

	// Mirror the frame's texture (facing left/right, upside down) without
	// touching the transform: position, anchor, physics and hit testing are
	// unaffected, unlike a negative scale.
	public volatile boolean flipX = false;
	public volatile boolean flipY = false;

	// Physics, integrated natively every frame (px/s, px/s^2)
	public volatile float velocityX = 0f;
	public volatile float velocityY = 0f;
	public volatile float gravity = 0f; // applied to velocityY

	// Constant horizontal acceleration in px/s², the sibling of `gravity`
	// (wind, a conveyor, a sideways pull, a top-down game whose "down" is
	// a direction). `gravity` keeps its exact meaning: it is the vertical
	// one, not a vector.
	public volatile float gravityX = 0f;

	// Newtonian flight (Asteroids-style): angularVelocity spins the sprite
	// (deg/s); thrust accelerates along the current heading (px/s^2, speed
	// capped at maxSpeed); wrapAround teleports the sprite to the opposite
	// screen edge when it fully leaves the surface.
	public volatile float angularVelocity = 0f;
	public volatile float thrust = 0f;
	public volatile boolean wrapAround = false;

	// Opts this world sprite into GameView.worldWrapX. Scene owns the
	// normalization, rendering and seam-aware collision behavior.
	public volatile boolean wrapWorldX = false;

	// Seamless scroll looping: when wrapShift > 0 and x drops below wrapX,
	// x jumps right by wrapShift (and mirrored for wrapShift < 0 / x > wrapX).
	// Handled natively so parallax layers never stutter on JS latency.
	public volatile float wrapX = 0f;
	public volatile float wrapShift = 0f;

	// Shrinks the collision AABB around the anchor (1 = full frame). Sprite
	// art rarely fills its frame; smaller values make collisions feel fair.
	public volatile float hitboxScale = 1f;

	// Per-axis correction on top of hitboxScale, for art whose useful part
	// fills its frame by a different fraction on each axis. example/assets/
	// adventurer.png is a 20x44 drawing in a 32x48 frame, so no single scale
	// describes him: 0.62 matches his width but ends 7 px above his feet,
	// and 0.92 reaches the feet but is 47% wider than he is.
	//
	// They multiply hitboxScale rather than replace it, so hitboxScale stays
	// the overall adjustment and these two are per-axis corrections on top of
	// it -- the same relationship hitboxScale already has with scaleX/scaleY.
	// Both default to 1, so a sprite that never sets them is unaffected and 0
	// keeps meaning zero, as it does everywhere else in the engine.
	//
	// Ignored by circle hitboxes: a circle has no axes, so its radius keeps
	// using hitboxScale alone.
	public volatile float hitboxScaleX = 1f;
	public volatile float hitboxScaleY = 1f;

	// Swept AABB collision: the sprite's movement this frame is tested as
	// a path, not just at the end position, so fast movers (bullets)
	// can't tunnel through thin targets or solids between frames. Applies
	// to collidesWith events and solidWith blocking; circle hitboxes
	// sweep as their bounding box.
	public volatile boolean swept = false;

	// true = the hitbox is a circle (radius = half the smaller drawn side
	// x hitboxScale, centered on the sprite center) — balls, asteroids.
	// Collision events test circle-vs-circle/AABB; against solids, the
	// ball is pushed out along the contact normal, so it bounces off
	// corners naturally instead of like a box.
	public volatile boolean circleHitbox = false;

	// Oriented hitbox (hitboxShape: 'rotatedRect'): the collision rect turns
	// with the sprite instead of being re-boxed axis-aligned every frame, so
	// a tilted platform or a diamond post is hit on its real face and the
	// contact normal comes out perpendicular to it. An axis-aligned rect is
	// still the default — this only matters once rotation is non-zero.
	public volatile boolean obbHitbox = false;

	// Draws debug overlays: collision AABB (green), sprite/touch bounds
	// (blue), anchor point (orange). Scene.debugAll enables it for everyone.
	public volatile boolean debug = false;

	// Collision: this sprite's group tag, and the groups it reports hits with
	public volatile String collisionGroup;
	public volatile Set<String> collidesWith;
	final Set<Sprite> colliding = new HashSet<>(); // overlap-enter tracking, GL thread only

	// Solid collision: groups whose AABBs block this sprite's movement
	// (platformer floors/walls). Resolved natively each frame; landing on
	// top sets onGround and fires the 'land' event.
	public volatile Set<String> solidWith;
	public volatile boolean onGround = false;

	// Pressed against a solid's side this frame: -1 = wall on the left,
	// 1 = wall on the right, 0 = free. Any sideways push-out counts — a
	// rect resolved horizontally, or a circle/OBB contact whose normal is
	// mostly horizontal. JS reads it as onWallLeft/onWallRight; the
	// transition into a wall (or flipping sides) fires 'wallhit'.
	public volatile int wallSide = 0;

	// Wall slide: while pressed against a wall, downward velocity is capped
	// at this many px/s (0 = off, fall at full speed). Applied by the solid
	// resolver right after the wall contact is known, so JS never runs per
	// frame for it.
	public volatile float wallSlideSpeed = 0f;

	// One-way platform: as a solid, this sprite only catches riders
	// falling onto its top edge — they jump up through it and are never
	// blocked sideways or from below (pass-through floors).
	public volatile boolean oneWay = false;

	// As a solid: how this sprite acts on the bodies that hit it.
	//   BLOCK   — immovable wall (the default, and what every solid did
	//             before this existed)
	//   CONTAIN — inward circular boundary: circles matched to it are kept
	//             *inside* its circumference instead of outside (drums,
	//             bowls, lottery cages). Circle-on-circle only.
	//   PUSH    — a body in its own right: a matched circle and this one
	//             share the separation and exchange momentum along the
	//             contact normal (equal masses). Circle-on-circle only.
	public static final int SOLID_BLOCK = 0;
	public static final int SOLID_CONTAIN = 1;
	public static final int SOLID_PUSH = 2;
	public volatile int solidMode = SOLID_BLOCK;

	// Fraction of speed shed per second to the surface (0 = none, the
	// default; ~0.6 ≈ a pool ball on felt). Proportional, like the car
	// model's `drag` but for ordinary sprites and outside carMode: a fast
	// body sheds a lot and a slow one very little, which is what a ball
	// trickling to a halt actually looks like. A constant deceleration was
	// tried here instead and stops slow bodies dead, which reads as wrong.
	// The trade is that a proportion never reaches zero on its own, so a
	// body creeping below a twentieth of a pixel per frame is stopped
	// outright rather than left crawling down an asymptote.
	public volatile float linearDamping = 0f;

	// As a solid: whether riders inherit this sprite's per-frame movement
	// (moving platforms). Turn off for world-scroll terrain that moves
	// while the player is meant to stay put (endless runners — the skate
	// demo's raised road).
	public volatile boolean carryRiders = true;

	// How far update() moved this sprite this frame (velocity, tweens,
	// idle wobble — wrap teleports excluded). The solid resolver applies
	// the ground's delta to its rider, so moving platforms carry.
	// GL thread only.
	public float frameDeltaX = 0f;
	public float frameDeltaY = 0f;

	// Velocity added by the native movement model during update(), captured
	// after carMode/thrust/gravity/damping and before position integration.
	// Solid-impact intensity subtracts this contribution so gravity and a
	// long frame do not masquerade as an incoming hit.
	public float frameAccelX = 0f;
	public float frameAccelY = 0f;

	// The solid this sprite stood on last frame (GL thread only).
	public Sprite groundSprite;

	// The solid this sprite was pressed against last frame, null for a
	// tile-layer wall (GL thread only).
	public Sprite wallSprite;

	// Bounciness against solids: 0 = stop dead (platformer feet),
	// 0..1 = reflect velocity with damping (balls). Tiny bounces come to rest.
	public volatile float restitution = 0f;

	// Discrete physical-contact event. The proxy keeps the listener flag in
	// native state so the resolver can skip every gate/contact calculation
	// for sprites nobody is listening to. Gates are render-thread-only and
	// allocated lazily, one per other-sprite identity.
	public volatile float impactThreshold = 40f;
	public volatile boolean solidImpactListening = false;
	private WeakHashMap<Sprite, ImpactGate> impactGates;
	private int impactPruneThreshold = 16;
	private final AtomicBoolean impactGatesStale = new AtomicBoolean(false);
	private static final double IMPACT_REARM_DELAY = 0.1d;
	private static final double IMPACT_TIME_EPSILON = 1e-9d;

	private static final class ImpactGate
	{
		boolean armed = true;
		double lastSeenPhysicsTime = Double.NEGATIVE_INFINITY;
	}

	// Top-down car physics (carMode = true). JS sets throttle/steering from
	// the controls; everything else runs natively per frame. Rotation 0 =
	// facing up. Lateral grip lower than infinite = the car drifts when
	// cornering fast.
	public volatile boolean carMode = false;
	public volatile float throttle = 0f;      // -1 (brake/reverse) .. 1 (gas)
	public volatile float steering = 0f;      // -1 (left) .. 1 (right)
	public volatile float enginePower = 600f; // forward acceleration, px/s^2
	public volatile float maxSpeed = 500f;    // px/s (reverse caps at 40%)
	public volatile float turnRate = 200f;    // deg/s at full steering and speed
	public volatile float grip = 4f;          // lateral friction, 1/s — lower = more drift
	public volatile float drag = 0.6f;        // longitudinal friction, 1/s

	// Idle animation: a gentle organic wobble — rotation and position
	// oscillate by up to idleRotation degrees / idleMovement px around the
	// sprite's base transform. Applied as per-frame deltas, so it composes
	// with tweens and drags and unwinds cleanly when disabled.
	public volatile boolean idleAnimation = false;
	public volatile float idleRotation = 3f;   // degrees of wobble
	public volatile float idleMovement = 4f;   // px of drift
	public volatile float idleSpeed = 1f;      // frequency multiplier
	private static final java.util.concurrent.atomic.AtomicInteger IDLE_SEQ =
		new java.util.concurrent.atomic.AtomicInteger();
	private final float idlePhase = IDLE_SEQ.getAndIncrement() * 1.7f;
	private float idleTime = 0f;
	private float idleAppliedRot = 0f;
	private float idleAppliedX = 0f;
	private float idleAppliedY = 0f;

	// Skid marks: while drifting, the rear tires leave fading trail
	// segments in the scene's SkidTrail. Threshold 0 = auto (20% of maxSpeed).
	public volatile boolean skidMarks = false;
	public volatile float skidThreshold = 0f;   // lateral px/s that counts as drifting
	public volatile boolean drifting = false;   // read-only state for JS
	private final float[] lastTireX = new float[2];
	private final float[] lastTireY = new float[2];
	private boolean skidActive = false;

	// Sprite sheet / animation
	public volatile SpriteSheet sheet;
	public volatile int frame = 0;
	private final Map<String, Animation> animations = new HashMap<>();
	private Animation currentAnimation;
	private float animationTime = 0f;
	private boolean playing = false;
	// Chained follow-ups (play(name, { then: ... })): each queued name
	// auto-plays as the previous non-looping animation finishes.
	private final java.util.ArrayDeque<String> animationQueue = new java.util.ArrayDeque<>();

	// Path following (followPath): a precomputed polyline walked at
	// constant speed each frame; null = not following. The walk happens in
	// update(), so path movement counts into frameDelta (path platforms
	// carry riders) and composes with idle wobble like any other motion.
	public volatile Path path;
	private final float[] pathOut = new float[3];

	// Active tweens, ticked by the render loop
	private final CopyOnWriteArrayList<Tween> tweens = new CopyOnWriteArrayList<>();

	// Set by Scene.add/remove; lets property setters mark z-order dirty
	public volatile Scene scene;

	// Back-reference for firing events (dragend, animationcomplete, ...)
	public volatile KrollProxy proxy;
	public volatile SpriteEventListener eventListener;

	public interface SpriteEventListener {
		void onAnimationComplete(Sprite sprite, String animationName);
		void onTweenComplete(Sprite sprite);
		void onPathComplete(Sprite sprite);
		void onCollision(Sprite sprite, Sprite other);
		void onCollisionEnd(Sprite sprite, Sprite other);
		void onLand(Sprite sprite, Sprite solid);
		void onWallHit(Sprite sprite, Sprite solid, int side);
		void onSolidImpact(Sprite sprite, Sprite other, float contactX, float contactY,
			float normalX, float normalY, float speed, float restitution);
	}

	/** Marks the render-thread gate map for cleanup without touching it from
	 *  Kroll or a scene-mutation thread. */
	public void markImpactGatesStale()
	{
		impactGatesStale.set(true);
	}

	/** Called by the proxy when the first listener is added or the last one
	 *  is removed. Cleanup is deferred to the owning render thread. */
	public void setSolidImpactListening(boolean listening)
	{
		solidImpactListening = listening;
		if (!listening) {
			markImpactGatesStale();
		}
	}

	/** Clears stale gates only for the render thread that currently owns this
	 *  sprite. A previous scene may still hold it in an in-flight snapshot. */
	public void consumeImpactGatesStale(Scene owner)
	{
		if (!impactGatesStale.get() || scene != owner) {
			return;
		}
		synchronized (this) {
			// The owner can change while an old render thread waits for this lock.
			if (scene != owner || !impactGatesStale.getAndSet(false)) {
				return;
			}
			if (impactGates != null) {
				impactGates.clear();
				impactGates = null;
			}
			impactPruneThreshold = 16;
		}
	}

	/** Updates this receiver's per-pair separation gate and returns whether its
	 *  listener should receive the current physical impact. Render thread. */
	public synchronized boolean shouldEmitSolidImpact(Sprite other, float speed,
			double physicsTime, Scene owner)
	{
		if (scene != owner || !solidImpactListening) {
			return false;
		}
		consumeImpactGatesStale(owner);
		if (impactGates == null) {
			impactGates = new WeakHashMap<>();
		}
		ImpactGate gate = impactGates.get(other);
		if (gate == null) {
			gate = new ImpactGate();
			impactGates.put(other, gate);
		}
		if (!gate.armed
				&& physicsTime - gate.lastSeenPhysicsTime
					> IMPACT_REARM_DELAY + IMPACT_TIME_EPSILON) {
			gate.armed = true;
		}
		gate.lastSeenPhysicsTime = physicsTime;

		float threshold = Math.max(0f, impactThreshold);
		boolean emit = speed > 0f && speed >= threshold && gate.armed;
		if (emit) {
			gate.armed = false;
		}

		if (impactGates.size() > impactPruneThreshold) {
			pruneImpactGates(physicsTime, owner);
		}
		return emit;
	}

	private void pruneImpactGates(double physicsTime, Scene owner)
	{
		for (Iterator<Map.Entry<Sprite, ImpactGate>> it = impactGates.entrySet().iterator();
				it.hasNext();) {
			Map.Entry<Sprite, ImpactGate> entry = it.next();
			Sprite other = entry.getKey();
			ImpactGate gate = entry.getValue();
			if (other == null || other.scene != owner
					|| physicsTime - gate.lastSeenPhysicsTime
						> IMPACT_REARM_DELAY + IMPACT_TIME_EPSILON) {
				it.remove();
			}
		}
		impactPruneThreshold = Math.max(16, impactGates.size() + 16);
	}

	public float drawWidth()
	{
		if (width > 0) {
			return width;
		}
		SpriteSheet s = sheet;
		return (s != null) ? s.frameWidth(frame) : 0f;
	}

	public float drawHeight()
	{
		if (height > 0) {
			return height;
		}
		SpriteSheet s = sheet;
		return (s != null) ? s.frameHeight(frame) : 0f;
	}

	public synchronized void addAnimation(String name, Animation animation)
	{
		animations.put(name, animation);
	}

	public synchronized boolean play(String name)
	{
		return play(name, null);
	}

	/** Plays `name` now and queues `then` names to auto-play as each
	 *  non-looping animation finishes — a looping animation never
	 *  finishes, so it ends the chain. Replaces any previous queue. */
	public synchronized boolean play(String name, String[] then)
	{
		Animation a = animations.get(name);
		if (a == null || a.frames.length == 0) {
			return false;
		}
		animationQueue.clear();
		if (then != null) {
			for (String next : then) {
				if (next != null) {
					animationQueue.add(next);
				}
			}
		}
		currentAnimation = a;
		animationTime = 0f;
		playing = true;
		frame = a.frames[0];
		return true;
	}

	public synchronized void stop()
	{
		playing = false;
		animationQueue.clear();
	}

	public synchronized String currentAnimationName()
	{
		return (currentAnimation != null) ? currentAnimation.name : null;
	}

	public void addTween(Tween tween)
	{
		tween.captureStartValues(this);
		tweens.add(tween);
	}

	public void clearTweens()
	{
		tweens.clear();
	}

	/** Drops only x/y tweens — used when a drag starts, so scale/rotation
	 *  effects (e.g. pick-up scale-up) keep running during the drag. */
	public void clearPositionTweens()
	{
		for (Tween t : tweens) {
			if (t.toX != null || t.toY != null) {
				tweens.remove(t);
			}
		}
	}

	/** Called once per frame from the GL thread with the delta time in seconds. */
	public void update(float dt)
	{
		float startX = x;
		float startY = y;
		float startVelocityX = velocityX;
		float startVelocityY = velocityY;
		if (carMode) {
			updateCar(dt);
		}
		if (angularVelocity != 0f) {
			rotation += angularVelocity * dt;
		}
		if (thrust != 0f) {
			double rad = Math.toRadians(rotation);
			velocityX += (float) Math.sin(rad) * thrust * dt;
			velocityY += -(float) Math.cos(rad) * thrust * dt;
			float speed = (float) Math.sqrt(velocityX * velocityX + velocityY * velocityY);
			if (speed > maxSpeed && speed > 0f) {
				velocityX *= maxSpeed / speed;
				velocityY *= maxSpeed / speed;
			}
		}
		// Semi-implicit Euler: accelerate first, then move
		if (gravity != 0f) {
			velocityY += gravity * dt;
		}
		if (gravityX != 0f) {
			velocityX += gravityX * dt;
		}
		if (linearDamping > 0f && (velocityX != 0f || velocityY != 0f)) {
			// Clamped so a long frame can't reverse the sprite instead of
			// slowing it
			float keep = 1f - Math.min(1f, linearDamping * dt);
			velocityX *= keep;
			velocityY *= keep;
			if (velocityX * velocityX + velocityY * velocityY < 16f) {
				velocityX = 0f; // under 4 px/s: invisible, so stop for real
				velocityY = 0f;
			}
		}
		frameAccelX = velocityX - startVelocityX;
		frameAccelY = velocityY - startVelocityY;
		if (velocityX != 0f) {
			x += velocityX * dt;
		}
		if (velocityY != 0f) {
			y += velocityY * dt;
		}
		boolean sceneWrapX = wrapWorldX && scene != null && scene.worldWrapXEnabled;
		if (!sceneWrapX && wrapShift > 0f && x < wrapX) {
			x += wrapShift;
			startX += wrapShift; // teleport, not movement — keep it out of frameDelta
		} else if (!sceneWrapX && wrapShift < 0f && x > wrapX) {
			x += wrapShift;
			startX += wrapShift;
		}
		// Path following overrides the position absolutely; between the
		// startX capture and the frameDelta computation, so path platforms
		// still carry their riders.
		Path p = path;
		if (p != null) {
			boolean finished = p.advance(dt, pathOut);
			x = pathOut[0];
			y = pathOut[1];
			if (p.rotate) {
				rotation = pathOut[2];
			}
			if (finished) {
				path = null;
				SpriteEventListener listener = eventListener;
				if (listener != null) {
					listener.onPathComplete(this);
				}
			}
		}
		float flashLeft = flashRemaining;
		if (flashLeft > 0f) {
			flashRemaining = Math.max(0f, flashLeft - dt);
		}
		updateAnimation(dt);
		updateTweens(dt);
		updateIdle(dt);
		frameDeltaX = x - startX;
		frameDeltaY = y - startY;
	}

	/**
	 * Idle wobble: three slightly detuned sine waves (rotation, x, y) give
	 * an organic float instead of a metronome. Only the CHANGE in offset is
	 * applied each frame, so the base transform stays writable underneath.
	 */
	private void updateIdle(float dt)
	{
		float newRot = 0f;
		float newX = 0f;
		float newY = 0f;
		if (idleAnimation && (idleRotation != 0f || idleMovement != 0f)) {
			idleTime += dt;
			float w = (float) (Math.PI * 2.0) * idleSpeed;
			newRot = idleRotation * (float) Math.sin(idleTime * w * 0.50 + idlePhase);
			newX = idleMovement * 0.6f * (float) Math.sin(idleTime * w * 0.37 + idlePhase * 1.3f);
			newY = idleMovement * (float) Math.sin(idleTime * w * 0.43 + idlePhase * 2.1f);
		} else if (idleAppliedRot == 0f && idleAppliedX == 0f && idleAppliedY == 0f) {
			return;
		}
		rotation += newRot - idleAppliedRot;
		x += newX - idleAppliedX;
		y += newY - idleAppliedY;
		idleAppliedRot = newRot;
		idleAppliedX = newX;
		idleAppliedY = newY;
	}

	/**
	 * Arcade top-down car model. Velocity is split into forward and lateral
	 * components along the car's heading; the engine accelerates forward,
	 * drag damps forward speed, and grip damps lateral speed. Steering
	 * effectiveness scales with forward speed (and its sign, so reversing
	 * steers naturally). Because grip is finite, hard cornering at speed
	 * leaves residual lateral velocity — the drift.
	 */
	private void updateCar(float dt)
	{
		double rad = Math.toRadians(rotation);
		float fwdX = (float) Math.sin(rad);
		float fwdY = -(float) Math.cos(rad);
		float rightX = (float) Math.cos(rad);
		float rightY = (float) Math.sin(rad);

		float vForward = velocityX * fwdX + velocityY * fwdY;
		float vLateral = velocityX * rightX + velocityY * rightY;

		float steerFactor = Math.max(-1f, Math.min(1f, vForward / (maxSpeed * 0.25f)));
		rotation += steering * turnRate * steerFactor * dt;

		vForward += throttle * enginePower * dt;
		vForward -= vForward * Math.min(1f, drag * dt);
		vLateral -= vLateral * Math.min(1f, grip * dt);

		if (vForward > maxSpeed) {
			vForward = maxSpeed;
		} else if (vForward < -maxSpeed * 0.4f) {
			vForward = -maxSpeed * 0.4f;
		}

		// Recompose along the (updated) heading
		rad = Math.toRadians(rotation);
		fwdX = (float) Math.sin(rad);
		fwdY = -(float) Math.cos(rad);
		rightX = (float) Math.cos(rad);
		rightY = (float) Math.sin(rad);
		velocityX = fwdX * vForward + rightX * vLateral;
		velocityY = fwdY * vForward + rightY * vLateral;

		float threshold = (skidThreshold > 0f) ? skidThreshold : maxSpeed * 0.2f;
		drifting = Math.abs(vLateral) > threshold;
		if (skidMarks) {
			emitSkidMarks(fwdX, fwdY, rightX, rightY, vLateral, threshold);
		}
	}

	/** Appends one trail segment per rear tire while drifting. GL thread. */
	private void emitSkidMarks(float fwdX, float fwdY, float rightX, float rightY,
							   float vLateral, float threshold)
	{
		Scene sc = scene;
		if (!drifting || sc == null) {
			skidActive = false; // break the ribbon so no segment bridges the gap
			return;
		}
		float w = drawWidth() * Math.abs(scaleX);
		float h = drawHeight() * Math.abs(scaleY);
		float axleX = x - fwdX * h * 0.28f;
		float axleY = y - fwdY * h * 0.28f;
		float trackX = rightX * w * 0.3f; // half the rear track width
		float trackY = rightY * w * 0.3f;
		float intensity = Math.min(1f, Math.abs(vLateral) / (threshold * 3f));
		float alpha = 0.15f + 0.3f * intensity;
		float markHalf = Math.max(1.5f, w * 0.07f);

		for (int i = 0; i < 2; i++) {
			float side = (i == 0) ? -1f : 1f;
			float tireX = axleX + side * trackX;
			float tireY = axleY + side * trackY;
			if (skidActive) {
				sc.skidTrail.add(lastTireX[i], lastTireY[i], tireX, tireY, markHalf, alpha);
			}
			lastTireX[i] = tireX;
			lastTireY[i] = tireY;
		}
		skidActive = true;
	}

	/** Collision radius for circle hitboxes. */
	public float hitRadius()
	{
		float w = drawWidth() * Math.abs(scaleX);
		float h = drawHeight() * Math.abs(scaleY);
		// hitboxScaleX/Y are deliberately absent: a circle has no axes.
		return Math.min(w, h) * 0.5f * hitboxScale;
	}

	/** World position of the sprite's geometric center: out = {x, y}. */
	public void hitCenter(float[] out)
	{
		float w = drawWidth();
		float h = drawHeight();
		float lx = (w / 2f - anchorX * w) * scaleX;
		float ly = (h / 2f - anchorY * h) * scaleY;
		double rad = Math.toRadians(rotation);
		float cos = (float) Math.cos(rad);
		float sin = (float) Math.sin(rad);
		out[0] = x + lx * cos - ly * sin;
		out[1] = y + lx * sin + ly * cos;
	}

	/**
	 * Oriented hitbox: out = {centerX, centerY, halfWidth, halfHeight,
	 * rotationRadians}. Same rect computeAABB() boxes — same scales, same
	 * hitboxScale shrink around the anchor — but kept as a turned rectangle
	 * instead of being re-boxed to the axes.
	 */
	public void hitBox(float[] out)
	{
		float w = drawWidth();
		float h = drawHeight();
		float sx = scaleX * hitboxScale * hitboxScaleX;
		float sy = scaleY * hitboxScale * hitboxScaleY;
		float lcx = (w / 2f - anchorX * w) * sx;
		float lcy = (h / 2f - anchorY * h) * sy;
		double rad = Math.toRadians(rotation);
		float cos = (float) Math.cos(rad);
		float sin = (float) Math.sin(rad);
		out[0] = x + lcx * cos - lcy * sin;
		out[1] = y + lcx * sin + lcy * cos;
		out[2] = Math.abs(w * sx) / 2f;
		out[3] = Math.abs(h * sy) / 2f;
		out[4] = (float) rad;
	}

	/** World-space axis-aligned bounding box: out = {minX, minY, maxX, maxY}. */
	public void computeAABB(float[] out)
	{
		float w = drawWidth();
		float h = drawHeight();
		float ax = anchorX * w;
		float ay = anchorY * h;
		double rad = Math.toRadians(rotation);
		float cos = (float) Math.cos(rad);
		float sin = (float) Math.sin(rad);
		float sx = scaleX * hitboxScale * hitboxScaleX;
		float sy = scaleY * hitboxScale * hitboxScaleY;
		out[0] = out[1] = Float.MAX_VALUE;
		out[2] = out[3] = -Float.MAX_VALUE;
		for (int i = 0; i < 4; i++) {
			float lx = (((i & 1) == 0) ? -ax : w - ax) * sx;
			float ly = ((i < 2) ? -ay : h - ay) * sy;
			float wx = x + lx * cos - ly * sin;
			float wy = y + lx * sin + ly * cos;
			out[0] = Math.min(out[0], wx);
			out[1] = Math.min(out[1], wy);
			out[2] = Math.max(out[2], wx);
			out[3] = Math.max(out[3], wy);
		}
	}

	private synchronized void updateAnimation(float dt)
	{
		if (!playing || currentAnimation == null) {
			return;
		}
		animationTime += dt;
		Animation a = currentAnimation;
		int frameIndex = (int) (animationTime * a.fps);
		if (frameIndex >= a.frames.length) {
			if (a.loop) {
				frameIndex = frameIndex % a.frames.length;
			} else {
				// Chained follow-up (play(name, { then })): start the next
				// queued animation instead of holding the end frame.
				Animation next = null;
				while (!animationQueue.isEmpty()) {
					Animation candidate = animations.get(animationQueue.poll());
					if (candidate != null && candidate.frames.length > 0) {
						next = candidate;
						break;
					}
				}
				if (next != null) {
					currentAnimation = next;
					animationTime = 0f;
					frame = next.frames[0];
				} else {
					frame = (a.endFrame >= 0) ? a.endFrame : a.frames[a.frames.length - 1];
					playing = false;
				}
				SpriteEventListener listener = eventListener;
				if (listener != null) {
					listener.onAnimationComplete(this, a.name);
				}
				return;
			}
		}
		frame = a.frames[frameIndex];
	}

	private void updateTweens(float dt)
	{
		for (Tween t : tweens) {
			if (t.update(this, dt)) {
				tweens.remove(t);
				SpriteEventListener listener = eventListener;
				if (listener != null) {
					listener.onTweenComplete(this);
				}
			}
		}
	}

	/**
	 * Hit test in world coordinates, respecting rotation, scale and anchor.
	 * The touch point is transformed into the sprite's local space instead
	 * of rotating a bounding box.
	 */
	public boolean hitTest(float px, float py)
	{
		if (!visible || effectiveOpacity() <= 0f || !touchEnabled) {
			return false;
		}
		// Screen-fixed sprites live in surface coordinates; the touch
		// arrives in world space, so map it back before testing. Parallax
		// sprites render shifted by the unapplied part of the camera
		// travel — shift the touch the same way (shake is already absent
		// from touch mapping).
		if (screenFixed) {
			Scene sc = scene;
			if (sc != null) {
				px = sc.worldToScreenX(px);
				py = sc.worldToScreenY(py);
			}
		} else if (scrollFactor != 1f) {
			Scene sc = scene;
			if (sc != null) {
				px -= (1f - scrollFactor) * sc.cameraX;
				py -= (1f - scrollFactor) * sc.cameraY;
			}
		}
		float w = drawWidth();
		float h = drawHeight();
		if (w <= 0f || h <= 0f) {
			return false;
		}
		float dx = px - x;
		float dy = py - y;
		double rad = -Math.toRadians(rotation);
		float cos = (float) Math.cos(rad);
		float sin = (float) Math.sin(rad);
		float rx = dx * cos - dy * sin;
		float ry = dx * sin + dy * cos;
		float sx = (scaleX != 0f) ? scaleX : 1e-6f;
		float sy = (scaleY != 0f) ? scaleY : 1e-6f;
		float lx = rx / sx + anchorX * w;
		float ly = ry / sy + anchorY * h;
		if (circleHitbox) {
			// ellipse in local space, so touch matches the round art
			float nx = lx / w - 0.5f;
			float ny = ly / h - 0.5f;
			return nx * nx + ny * ny <= 0.25f;
		}
		return lx >= 0f && lx <= w && ly >= 0f && ly <= h;
	}
}
