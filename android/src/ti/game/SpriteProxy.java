package ti.game;

import android.graphics.Color;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.util.TiConvert;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import ti.game.engine.Animation;
import ti.game.engine.Easing;
import ti.game.engine.Sprite;
import ti.game.engine.Tween;

/**
 * JS-facing sprite. Setting properties writes straight into the native
 * Sprite in the renderer's scene graph — nothing here runs per frame.
 *
 *   var hero = Game.createSprite({
 *       sheet: sheet, x: 100, y: 200, draggable: true,
 *       animations: {
 *           walk: { frames: [0,1,2,3], fps: 12, loop: true },
 *           jump: { frames: [4,5,6], fps: 10, frame: 0 }
 *       }
 *   });
 *   hero.play('walk');
 *
 * Events fired natively: tap, dragstart, drag, dragend, pinch, rotate,
 * animationcomplete, complete (tween finished).
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class SpriteProxy extends KrollProxy implements Sprite.SpriteEventListener
{
	private static final String LCAT = "TiGameSprite";

	private final Sprite sprite = new Sprite();
	private SpriteSheetProxy sheetProxy;
	private String glowColor;
	private String tintColor;

	public SpriteProxy()
	{
		super();
		sprite.proxy = this;
		sprite.eventListener = this;
	}

	public Sprite getSprite()
	{
		return sprite;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);

		if (options.containsKey("sheet")) {
			Object value = options.get("sheet");
			if (value instanceof SpriteSheetProxy) {
				setSheet((SpriteSheetProxy) value);
			}
		}
		if (options.containsKey("x")) {
			sprite.x = TiConvert.toFloat(options.get("x"));
		}
		if (options.containsKey("y")) {
			sprite.y = TiConvert.toFloat(options.get("y"));
		}
		if (options.containsKey("width")) {
			sprite.width = TiConvert.toFloat(options.get("width"));
		}
		if (options.containsKey("height")) {
			sprite.height = TiConvert.toFloat(options.get("height"));
		}
		if (options.containsKey("scale")) {
			float s = TiConvert.toFloat(options.get("scale"));
			sprite.scaleX = s;
			sprite.scaleY = s;
		}
		if (options.containsKey("scaleX")) {
			sprite.scaleX = TiConvert.toFloat(options.get("scaleX"));
		}
		if (options.containsKey("scaleY")) {
			sprite.scaleY = TiConvert.toFloat(options.get("scaleY"));
		}
		if (options.containsKey("rotation")) {
			sprite.rotation = TiConvert.toFloat(options.get("rotation"));
		}
		if (options.containsKey("anchorX")) {
			sprite.anchorX = TiConvert.toFloat(options.get("anchorX"));
		}
		if (options.containsKey("anchorY")) {
			sprite.anchorY = TiConvert.toFloat(options.get("anchorY"));
		}
		if (options.containsKey("opacity")) {
			sprite.opacity = TiConvert.toFloat(options.get("opacity"));
		}
		if (options.containsKey("tintColor")) {
			setTintColor(TiConvert.toString(options.get("tintColor")));
		}
		if (options.containsKey("glowColor")) {
			setGlowColor(TiConvert.toString(options.get("glowColor")));
		}
		if (options.containsKey("glowBlur")) {
			sprite.glowBlur = TiConvert.toFloat(options.get("glowBlur"));
		}
		if (options.containsKey("glowOpacity")) {
			sprite.glowOpacity = TiConvert.toFloat(options.get("glowOpacity"));
		}
		if (options.containsKey("visible")) {
			sprite.visible = TiConvert.toBoolean(options.get("visible"));
		}
		if (options.containsKey("zIndex")) {
			sprite.zIndex = TiConvert.toInt(options.get("zIndex"));
		}
		if (options.containsKey("frame")) {
			sprite.frame = TiConvert.toInt(options.get("frame"));
		}
		if (options.containsKey("draggable")) {
			sprite.draggable = TiConvert.toBoolean(options.get("draggable"));
		}
		if (options.containsKey("pinchable")) {
			sprite.pinchable = TiConvert.toBoolean(options.get("pinchable"));
		}
		if (options.containsKey("rotatable")) {
			sprite.rotatable = TiConvert.toBoolean(options.get("rotatable"));
		}
		if (options.containsKey("touchEnabled")) {
			sprite.touchEnabled = TiConvert.toBoolean(options.get("touchEnabled"));
		}
		if (options.containsKey("tileRepeat")) {
			setTileRepeat(options.get("tileRepeat"));
		}
		if (options.containsKey("animations")) {
			parseAnimations(options.get("animations"));
		}
		if (options.containsKey("velocityX")) {
			sprite.velocityX = TiConvert.toFloat(options.get("velocityX"));
		}
		if (options.containsKey("velocityY")) {
			sprite.velocityY = TiConvert.toFloat(options.get("velocityY"));
		}
		if (options.containsKey("gravity")) {
			sprite.gravity = TiConvert.toFloat(options.get("gravity"));
		}
		if (options.containsKey("wrapX")) {
			sprite.wrapX = TiConvert.toFloat(options.get("wrapX"));
		}
		if (options.containsKey("wrapShift")) {
			sprite.wrapShift = TiConvert.toFloat(options.get("wrapShift"));
		}
		if (options.containsKey("hitboxScale")) {
			sprite.hitboxScale = TiConvert.toFloat(options.get("hitboxScale"));
		}
		if (options.containsKey("hitboxShape")) {
			setHitboxShape(TiConvert.toString(options.get("hitboxShape")));
		}
		if (options.containsKey("debug")) {
			sprite.debug = TiConvert.toBoolean(options.get("debug"));
		}
		if (options.containsKey("collisionGroup")) {
			sprite.collisionGroup = TiConvert.toString(options.get("collisionGroup"));
		}
		if (options.containsKey("collidesWith")) {
			setCollidesWith((Object[]) options.get("collidesWith"));
		}
		if (options.containsKey("solidWith")) {
			setSolidWith((Object[]) options.get("solidWith"));
		}
		if (options.containsKey("restitution")) {
			sprite.restitution = TiConvert.toFloat(options.get("restitution"));
		}
		if (options.containsKey("carMode")) {
			sprite.carMode = TiConvert.toBoolean(options.get("carMode"));
		}
		if (options.containsKey("enginePower")) {
			sprite.enginePower = TiConvert.toFloat(options.get("enginePower"));
		}
		if (options.containsKey("maxSpeed")) {
			sprite.maxSpeed = TiConvert.toFloat(options.get("maxSpeed"));
		}
		if (options.containsKey("turnRate")) {
			sprite.turnRate = TiConvert.toFloat(options.get("turnRate"));
		}
		if (options.containsKey("grip")) {
			sprite.grip = TiConvert.toFloat(options.get("grip"));
		}
		if (options.containsKey("drag")) {
			sprite.drag = TiConvert.toFloat(options.get("drag"));
		}
		if (options.containsKey("ySort")) {
			sprite.ySort = TiConvert.toBoolean(options.get("ySort"));
		}
		if (options.containsKey("angularVelocity")) {
			sprite.angularVelocity = TiConvert.toFloat(options.get("angularVelocity"));
		}
		if (options.containsKey("thrust")) {
			sprite.thrust = TiConvert.toFloat(options.get("thrust"));
		}
		if (options.containsKey("wrapAround")) {
			sprite.wrapAround = TiConvert.toBoolean(options.get("wrapAround"));
		}
		if (options.containsKey("idleAnimation")) {
			sprite.idleAnimation = TiConvert.toBoolean(options.get("idleAnimation"));
		}
		if (options.containsKey("idleRotation")) {
			sprite.idleRotation = TiConvert.toFloat(options.get("idleRotation"));
		}
		if (options.containsKey("idleMovement")) {
			sprite.idleMovement = TiConvert.toFloat(options.get("idleMovement"));
		}
		if (options.containsKey("idleSpeed")) {
			sprite.idleSpeed = TiConvert.toFloat(options.get("idleSpeed"));
		}
		if (options.containsKey("skidMarks")) {
			sprite.skidMarks = TiConvert.toBoolean(options.get("skidMarks"));
		}
		if (options.containsKey("skidThreshold")) {
			sprite.skidThreshold = TiConvert.toFloat(options.get("skidThreshold"));
		}
	}

	@SuppressWarnings("unchecked")
	private void parseAnimations(Object value)
	{
		if (!(value instanceof Map)) {
			return;
		}
		for (Map.Entry<String, Object> entry : ((Map<String, Object>) value).entrySet()) {
			if (!(entry.getValue() instanceof Map)) {
				continue;
			}
			Map<String, Object> def = (Map<String, Object>) entry.getValue();
			Object framesValue = def.get("frames");
			if (!(framesValue instanceof Object[])) {
				Log.w(LCAT, "Animation '" + entry.getKey() + "' has no frames array; skipped");
				continue;
			}
			Object[] rawFrames = (Object[]) framesValue;
			int[] frames = new int[rawFrames.length];
			for (int i = 0; i < rawFrames.length; i++) {
				frames[i] = TiConvert.toInt(rawFrames[i]);
			}
			float fps = def.containsKey("fps") ? TiConvert.toFloat(def.get("fps")) : 12f;
			boolean loop = def.containsKey("loop") && TiConvert.toBoolean(def.get("loop"));
			int endFrame = def.containsKey("frame") ? TiConvert.toInt(def.get("frame")) : -1;
			sprite.addAnimation(entry.getKey(), new Animation(entry.getKey(), frames, fps, loop, endFrame));
		}
	}

	// --- Sheet -----------------------------------------------------------

	@Kroll.setProperty
	public void setSheet(SpriteSheetProxy value)
	{
		sheetProxy = value;
		sprite.sheet = (value != null) ? value.getSheet() : null;
	}

	@Kroll.getProperty
	public SpriteSheetProxy getSheet()
	{
		return sheetProxy;
	}

	// --- Transform properties (live values, updated by drags/tweens) -----

	@Kroll.getProperty
	public float getX()
	{
		return sprite.x;
	}

	@Kroll.setProperty
	public void setX(float value)
	{
		sprite.x = value;
	}

	@Kroll.getProperty
	public float getY()
	{
		return sprite.y;
	}

	@Kroll.setProperty
	public void setY(float value)
	{
		sprite.y = value;
	}

	@Kroll.getProperty
	public float getWidth()
	{
		return sprite.drawWidth();
	}

	@Kroll.setProperty
	public void setWidth(float value)
	{
		sprite.width = value;
	}

	@Kroll.getProperty
	public float getHeight()
	{
		return sprite.drawHeight();
	}

	@Kroll.setProperty
	public void setHeight(float value)
	{
		sprite.height = value;
	}

	@Kroll.getProperty
	public float getScaleX()
	{
		return sprite.scaleX;
	}

	@Kroll.setProperty
	public void setScaleX(float value)
	{
		sprite.scaleX = value;
	}

	@Kroll.getProperty
	public float getScaleY()
	{
		return sprite.scaleY;
	}

	@Kroll.setProperty
	public void setScaleY(float value)
	{
		sprite.scaleY = value;
	}

	@Kroll.setProperty
	public void setScale(float value)
	{
		sprite.scaleX = value;
		sprite.scaleY = value;
	}

	@Kroll.getProperty
	public float getScale()
	{
		return sprite.scaleX;
	}

	@Kroll.getProperty
	public float getRotation()
	{
		return sprite.rotation;
	}

	@Kroll.setProperty
	public void setRotation(float value)
	{
		sprite.rotation = value;
	}

	@Kroll.getProperty
	public float getAnchorX()
	{
		return sprite.anchorX;
	}

	@Kroll.setProperty
	public void setAnchorX(float value)
	{
		sprite.anchorX = value;
	}

	@Kroll.getProperty
	public float getAnchorY()
	{
		return sprite.anchorY;
	}

	@Kroll.setProperty
	public void setAnchorY(float value)
	{
		sprite.anchorY = value;
	}

	@Kroll.getProperty
	public float getOpacity()
	{
		return sprite.opacity;
	}

	@Kroll.setProperty
	public void setOpacity(float value)
	{
		sprite.opacity = value;
	}

	/** Multiplies the frame's colors, e.g. '#ff5252'; null/white = unchanged. */
	@Kroll.setProperty
	public void setTintColor(String value)
	{
		tintColor = value;
		if (value == null) {
			sprite.tintR = 1f;
			sprite.tintG = 1f;
			sprite.tintB = 1f;
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			sprite.tintR = Color.red(color) / 255f;
			sprite.tintG = Color.green(color) / 255f;
			sprite.tintB = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// keep previous color
		}
	}

	@Kroll.getProperty
	public String getTintColor()
	{
		return tintColor;
	}

	/** Glow tint, e.g. '#ffd54a'; visible once glowBlur > 0. */
	@Kroll.setProperty
	public void setGlowColor(String value)
	{
		glowColor = value;
		if (value == null) {
			sprite.glowR = 1f;
			sprite.glowG = 1f;
			sprite.glowB = 1f;
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			sprite.glowR = Color.red(color) / 255f;
			sprite.glowG = Color.green(color) / 255f;
			sprite.glowB = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// keep previous color
		}
	}

	@Kroll.getProperty
	public String getGlowColor()
	{
		return glowColor;
	}

	/** Color.parseColor can't handle Titanium's '#rgb' shorthand. */
	private static String expandShortHex(String value)
	{
		if (value.length() == 4 && value.charAt(0) == '#') {
			return new String(new char[] {
				'#',
				value.charAt(1), value.charAt(1),
				value.charAt(2), value.charAt(2),
				value.charAt(3), value.charAt(3)
			});
		}
		return value;
	}

	/** Glow blur radius in px; 0 = no glow. */
	@Kroll.getProperty
	public float getGlowBlur()
	{
		return sprite.glowBlur;
	}

	@Kroll.setProperty
	public void setGlowBlur(float value)
	{
		sprite.glowBlur = value;
	}

	/** Halo strength 0..1 (fade the glow without touching the blur). */
	@Kroll.getProperty
	public float getGlowOpacity()
	{
		return sprite.glowOpacity;
	}

	@Kroll.setProperty
	public void setGlowOpacity(float value)
	{
		sprite.glowOpacity = value;
	}

	@Kroll.getProperty
	public boolean getVisible()
	{
		return sprite.visible;
	}

	@Kroll.setProperty
	public void setVisible(boolean value)
	{
		sprite.visible = value;
	}

	@Kroll.getProperty
	public int getZIndex()
	{
		return sprite.zIndex;
	}

	@Kroll.setProperty
	public void setZIndex(int value)
	{
		sprite.zIndex = value;
		if (sprite.scene != null) {
			sprite.scene.markZOrderDirty();
		}
	}

	@Kroll.getProperty
	public boolean getYSort()
	{
		return sprite.ySort;
	}

	@Kroll.setProperty
	public void setYSort(boolean value)
	{
		sprite.ySort = value;
		if (sprite.scene != null) {
			sprite.scene.recomputeYSort();
		}
	}

	@Kroll.getProperty
	public int getFrame()
	{
		return sprite.frame;
	}

	@Kroll.setProperty
	public void setFrame(int value)
	{
		sprite.stop();
		sprite.frame = value;
	}

	// --- Interaction flags ------------------------------------------------

	@Kroll.getProperty
	public boolean getDraggable()
	{
		return sprite.draggable;
	}

	@Kroll.setProperty
	public void setDraggable(boolean value)
	{
		sprite.draggable = value;
	}

	@Kroll.getProperty
	public boolean getPinchable()
	{
		return sprite.pinchable;
	}

	@Kroll.setProperty
	public void setPinchable(boolean value)
	{
		sprite.pinchable = value;
	}

	@Kroll.getProperty
	public boolean getRotatable()
	{
		return sprite.rotatable;
	}

	@Kroll.setProperty
	public void setRotatable(boolean value)
	{
		sprite.rotatable = value;
	}

	/** false = touches pass through to sprites underneath. */
	@Kroll.getProperty
	public boolean getTouchEnabled()
	{
		return sprite.touchEnabled;
	}

	@Kroll.setProperty
	public void setTouchEnabled(boolean value)
	{
		sprite.touchEnabled = value;
	}

	/**
	 * Tile the frame at its native size instead of stretching it across
	 * the sprite: true = both axes, 'x' / 'y' = one axis. The sheet needs
	 * `repeat: true` (GL_REPEAT wrap; power-of-two texture on ES 2.0) and
	 * a frame that spans the whole texture.
	 */
	@Kroll.setProperty
	public void setTileRepeat(Object value)
	{
		if (value instanceof String) {
			sprite.tileRepeatX = "x".equals(value);
			sprite.tileRepeatY = "y".equals(value);
		} else {
			boolean both = TiConvert.toBoolean(value, false);
			sprite.tileRepeatX = both;
			sprite.tileRepeatY = both;
		}
	}

	@Kroll.getProperty
	public Object getTileRepeat()
	{
		if (sprite.tileRepeatX && sprite.tileRepeatY) {
			return true;
		}
		if (sprite.tileRepeatX) {
			return "x";
		}
		if (sprite.tileRepeatY) {
			return "y";
		}
		return false;
	}

	// --- Physics ----------------------------------------------------------

	@Kroll.getProperty
	public float getVelocityX()
	{
		return sprite.velocityX;
	}

	@Kroll.setProperty
	public void setVelocityX(float value)
	{
		sprite.velocityX = value;
	}

	@Kroll.getProperty
	public float getVelocityY()
	{
		return sprite.velocityY;
	}

	@Kroll.setProperty
	public void setVelocityY(float value)
	{
		sprite.velocityY = value;
	}

	@Kroll.getProperty
	public float getGravity()
	{
		return sprite.gravity;
	}

	@Kroll.setProperty
	public void setGravity(float value)
	{
		sprite.gravity = value;
	}

	@Kroll.getProperty
	public float getWrapX()
	{
		return sprite.wrapX;
	}

	@Kroll.setProperty
	public void setWrapX(float value)
	{
		sprite.wrapX = value;
	}

	@Kroll.getProperty
	public float getWrapShift()
	{
		return sprite.wrapShift;
	}

	@Kroll.setProperty
	public void setWrapShift(float value)
	{
		sprite.wrapShift = value;
	}

	// --- Newtonian flight (Asteroids-style) -------------------------------

	@Kroll.getProperty
	public float getAngularVelocity()
	{
		return sprite.angularVelocity;
	}

	@Kroll.setProperty
	public void setAngularVelocity(float value)
	{
		sprite.angularVelocity = value;
	}

	@Kroll.getProperty
	public float getThrust()
	{
		return sprite.thrust;
	}

	@Kroll.setProperty
	public void setThrust(float value)
	{
		sprite.thrust = value;
	}

	@Kroll.getProperty
	public boolean getWrapAround()
	{
		return sprite.wrapAround;
	}

	@Kroll.setProperty
	public void setWrapAround(boolean value)
	{
		sprite.wrapAround = value;
	}

	// --- Car physics (top-down driving) -----------------------------------

	@Kroll.getProperty
	public boolean getCarMode()
	{
		return sprite.carMode;
	}

	@Kroll.setProperty
	public void setCarMode(boolean value)
	{
		sprite.carMode = value;
	}

	@Kroll.getProperty
	public float getThrottle()
	{
		return sprite.throttle;
	}

	@Kroll.setProperty
	public void setThrottle(float value)
	{
		sprite.throttle = value;
	}

	@Kroll.getProperty
	public float getSteering()
	{
		return sprite.steering;
	}

	@Kroll.setProperty
	public void setSteering(float value)
	{
		sprite.steering = value;
	}

	@Kroll.getProperty
	public float getEnginePower()
	{
		return sprite.enginePower;
	}

	@Kroll.setProperty
	public void setEnginePower(float value)
	{
		sprite.enginePower = value;
	}

	@Kroll.getProperty
	public float getMaxSpeed()
	{
		return sprite.maxSpeed;
	}

	@Kroll.setProperty
	public void setMaxSpeed(float value)
	{
		sprite.maxSpeed = value;
	}

	@Kroll.getProperty
	public float getTurnRate()
	{
		return sprite.turnRate;
	}

	@Kroll.setProperty
	public void setTurnRate(float value)
	{
		sprite.turnRate = value;
	}

	@Kroll.getProperty
	public float getGrip()
	{
		return sprite.grip;
	}

	@Kroll.setProperty
	public void setGrip(float value)
	{
		sprite.grip = value;
	}

	@Kroll.getProperty
	public float getDrag()
	{
		return sprite.drag;
	}

	@Kroll.setProperty
	public void setDrag(float value)
	{
		sprite.drag = value;
	}

	@Kroll.getProperty
	public boolean getSkidMarks()
	{
		return sprite.skidMarks;
	}

	@Kroll.setProperty
	public void setSkidMarks(boolean value)
	{
		sprite.skidMarks = value;
	}

	@Kroll.getProperty
	public float getSkidThreshold()
	{
		return sprite.skidThreshold;
	}

	@Kroll.setProperty
	public void setSkidThreshold(float value)
	{
		sprite.skidThreshold = value;
	}

	/** True while lateral speed exceeds the skid threshold (read-only). */
	@Kroll.getProperty
	public boolean getDrifting()
	{
		return sprite.drifting;
	}

	// --- Collision --------------------------------------------------------

	@Kroll.getProperty
	public float getHitboxScale()
	{
		return sprite.hitboxScale;
	}

	@Kroll.setProperty
	public void setHitboxScale(float value)
	{
		sprite.hitboxScale = value;
	}

	/** 'rect' (default) or 'circle' — balls and asteroids want circles. */
	@Kroll.getProperty
	public String getHitboxShape()
	{
		return sprite.circleHitbox ? "circle" : "rect";
	}

	@Kroll.setProperty
	public void setHitboxShape(String value)
	{
		sprite.circleHitbox = "circle".equals(value);
	}

	@Kroll.getProperty
	public boolean getDebug()
	{
		return sprite.debug;
	}

	@Kroll.setProperty
	public void setDebug(boolean value)
	{
		sprite.debug = value;
	}

	@Kroll.getProperty
	public String getCollisionGroup()
	{
		return sprite.collisionGroup;
	}

	@Kroll.setProperty
	public void setCollisionGroup(String value)
	{
		sprite.collisionGroup = value;
	}

	@Kroll.getProperty
	public String[] getCollidesWith()
	{
		Set<String> groups = sprite.collidesWith;
		return (groups != null) ? groups.toArray(new String[0]) : new String[0];
	}

	@Kroll.setProperty
	public void setCollidesWith(Object[] groups)
	{
		if (groups == null) {
			sprite.collidesWith = null;
			return;
		}
		Set<String> set = new HashSet<>();
		for (Object g : groups) {
			set.add(TiConvert.toString(g));
		}
		sprite.collidesWith = set;
	}

	// --- Solid collision (platformer) -------------------------------------

	@Kroll.getProperty
	public String[] getSolidWith()
	{
		Set<String> groups = sprite.solidWith;
		return (groups != null) ? groups.toArray(new String[0]) : new String[0];
	}

	@Kroll.setProperty
	public void setSolidWith(Object[] groups)
	{
		if (groups == null) {
			sprite.solidWith = null;
			return;
		}
		Set<String> set = new HashSet<>();
		for (Object g : groups) {
			set.add(TiConvert.toString(g));
		}
		sprite.solidWith = set;
	}

	/** True while standing on a solid (read-only; e.g. gate jumping on it). */
	@Kroll.getProperty
	public boolean getOnGround()
	{
		return sprite.onGround;
	}

	@Kroll.getProperty
	public float getRestitution()
	{
		return sprite.restitution;
	}

	@Kroll.setProperty
	public void setRestitution(float value)
	{
		sprite.restitution = value;
	}

	// --- Idle animation ---------------------------------------------------

	@Kroll.getProperty
	public boolean getIdleAnimation()
	{
		return sprite.idleAnimation;
	}

	@Kroll.setProperty
	public void setIdleAnimation(boolean value)
	{
		sprite.idleAnimation = value;
	}

	@Kroll.getProperty
	public float getIdleRotation()
	{
		return sprite.idleRotation;
	}

	@Kroll.setProperty
	public void setIdleRotation(float value)
	{
		sprite.idleRotation = value;
	}

	@Kroll.getProperty
	public float getIdleMovement()
	{
		return sprite.idleMovement;
	}

	@Kroll.setProperty
	public void setIdleMovement(float value)
	{
		sprite.idleMovement = value;
	}

	@Kroll.getProperty
	public float getIdleSpeed()
	{
		return sprite.idleSpeed;
	}

	@Kroll.setProperty
	public void setIdleSpeed(float value)
	{
		sprite.idleSpeed = value;
	}

	// --- Sheet animation --------------------------------------------------

	@Kroll.method
	public boolean play(String name)
	{
		if (!sprite.play(name)) {
			Log.w(LCAT, "Unknown animation: " + name);
			return false;
		}
		return true;
	}

	@Kroll.method
	public void stop()
	{
		sprite.stop();
	}

	@Kroll.getProperty
	public String getAnimation()
	{
		return sprite.currentAnimationName();
	}

	// --- Tweens -----------------------------------------------------------

	/**
	 * Native tween: sprite.animate({ x: 300, rotation: 90, duration: 500,
	 * easing: 'easeOut' }). Fires 'complete' when done. Duration/delay in ms.
	 * Optional 'frame' sets that sheet frame once the tween finishes.
	 */
	@Kroll.method
	public void animate(KrollDict options)
	{
		if (options == null) {
			return;
		}
		Tween tween = new Tween();
		if (options.containsKey("x")) {
			tween.toX = TiConvert.toFloat(options.get("x"));
		}
		if (options.containsKey("y")) {
			tween.toY = TiConvert.toFloat(options.get("y"));
		}
		if (options.containsKey("scale")) {
			float s = TiConvert.toFloat(options.get("scale"));
			tween.toScaleX = s;
			tween.toScaleY = s;
		}
		if (options.containsKey("scaleX")) {
			tween.toScaleX = TiConvert.toFloat(options.get("scaleX"));
		}
		if (options.containsKey("scaleY")) {
			tween.toScaleY = TiConvert.toFloat(options.get("scaleY"));
		}
		if (options.containsKey("rotation")) {
			tween.toRotation = TiConvert.toFloat(options.get("rotation"));
		}
		if (options.containsKey("opacity")) {
			tween.toOpacity = TiConvert.toFloat(options.get("opacity"));
		}
		if (options.containsKey("glowOpacity")) {
			tween.toGlowOpacity = TiConvert.toFloat(options.get("glowOpacity"));
		}
		if (options.containsKey("duration")) {
			tween.duration = TiConvert.toFloat(options.get("duration")) / 1000f;
		}
		if (options.containsKey("delay")) {
			tween.delay = TiConvert.toFloat(options.get("delay")) / 1000f;
		}
		if (options.containsKey("easing")) {
			tween.easing = TiConvert.toString(options.get("easing"));
		}
		if (options.containsKey("frame")) {
			tween.endFrame = TiConvert.toInt(options.get("frame"));
		}
		sprite.addTween(tween);
	}

	@Kroll.method
	public void clearTweens()
	{
		sprite.clearTweens();
	}

	// --- Native engine callbacks (GL thread; fireEvent is thread-safe) ----

	@Override
	public void onAnimationComplete(Sprite s, String animationName)
	{
		if (hasListeners("animationcomplete")) {
			KrollDict data = new KrollDict();
			data.put("animation", animationName);
			fireEvent("animationcomplete", data);
		}
	}

	@Override
	public void onTweenComplete(Sprite s)
	{
		if (hasListeners("complete")) {
			KrollDict data = new KrollDict();
			data.put("x", s.x);
			data.put("y", s.y);
			data.put("rotation", s.rotation);
			data.put("scaleX", s.scaleX);
			data.put("scaleY", s.scaleY);
			data.put("opacity", s.opacity);
			fireEvent("complete", data);
		}
	}

	@Override
	public void onCollision(Sprite s, Sprite other)
	{
		if (hasListeners("collision")) {
			KrollDict data = new KrollDict();
			data.put("group", other.collisionGroup);
			data.put("other", other.proxy);
			data.put("x", s.x);
			data.put("y", s.y);
			fireEvent("collision", data);
		}
	}

	@Override
	public void onLand(Sprite s, Sprite solid)
	{
		if (hasListeners("land")) {
			KrollDict data = new KrollDict();
			data.put("x", s.x);
			data.put("y", s.y);
			if (solid != null) {
				data.put("other", solid.proxy);
				data.put("group", solid.collisionGroup);
			}
			fireEvent("land", data);
		}
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Sprite";
	}
}
