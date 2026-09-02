package ti.game;

import android.graphics.Color;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.util.TiConvert;

import ti.game.engine.ParticleEmitter;
import ti.game.engine.SpriteBatch;

/**
 * JS-facing particle emitter:
 *
 *   var smoke = Game.createEmitter({
 *       sheet: puffSheet, frame: 0,
 *       rate: 30, lifetime: 600,            // ms, like all JS durations
 *       speed: 120, angle: 0, spread: 60,   // cone: 0 = up, clockwise
 *       gravity: -40, size: 24,
 *       startScale: 1, endScale: 2.5,
 *       startOpacity: 0.8, endOpacity: 0,
 *       tint: '#889', zIndex: 9,
 *       target: car                          // or x/y for a fixed position
 *   });
 *   gameView.add(smoke);
 *   smoke.emit(30);                          // one-shot burst on top of `rate`
 *
 * Everything per-frame (spawning, integration, fading, drawing) runs
 * natively; JS only writes configuration and triggers bursts.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class EmitterProxy extends KrollProxy
{
	private final ParticleEmitter emitter = new ParticleEmitter();
	private SpriteSheetProxy sheetProxy;
	private SpriteProxy targetProxy;

	public ParticleEmitter getEmitter()
	{
		return emitter;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("sheet") && options.get("sheet") instanceof SpriteSheetProxy) {
			setSheet((SpriteSheetProxy) options.get("sheet"));
		}
		if (options.containsKey("target") && options.get("target") instanceof SpriteProxy) {
			setTarget((SpriteProxy) options.get("target"));
		}
		if (options.containsKey("frame")) {
			emitter.frame = TiConvert.toInt(options.get("frame"), emitter.frame);
		}
		if (options.containsKey("x")) {
			emitter.x = TiConvert.toFloat(options.get("x"), emitter.x);
		}
		if (options.containsKey("y")) {
			emitter.y = TiConvert.toFloat(options.get("y"), emitter.y);
		}
		if (options.containsKey("offsetX")) {
			emitter.offsetX = TiConvert.toFloat(options.get("offsetX"), emitter.offsetX);
		}
		if (options.containsKey("offsetY")) {
			emitter.offsetY = TiConvert.toFloat(options.get("offsetY"), emitter.offsetY);
		}
		if (options.containsKey("zIndex")) {
			emitter.zIndex = TiConvert.toInt(options.get("zIndex"), emitter.zIndex);
		}
		if (options.containsKey("rate")) {
			emitter.rate = TiConvert.toFloat(options.get("rate"), emitter.rate);
		}
		if (options.containsKey("lifetime")) {
			emitter.lifetime = TiConvert.toFloat(options.get("lifetime"), emitter.lifetime * 1000f) / 1000f;
		}
		if (options.containsKey("speed")) {
			emitter.speed = TiConvert.toFloat(options.get("speed"), emitter.speed);
		}
		if (options.containsKey("angle")) {
			emitter.angle = TiConvert.toFloat(options.get("angle"), emitter.angle);
		}
		if (options.containsKey("spread")) {
			emitter.spread = TiConvert.toFloat(options.get("spread"), emitter.spread);
		}
		if (options.containsKey("gravity")) {
			emitter.gravity = TiConvert.toFloat(options.get("gravity"), emitter.gravity);
		}
		if (options.containsKey("size")) {
			emitter.size = TiConvert.toFloat(options.get("size"), emitter.size);
		}
		if (options.containsKey("startScale")) {
			emitter.startScale = Values.ratio(options.get("startScale"), emitter.startScale);
		}
		if (options.containsKey("endScale")) {
			emitter.endScale = Values.ratio(options.get("endScale"), emitter.endScale);
		}
		if (options.containsKey("startOpacity")) {
			emitter.startOpacity = Values.ratio(options.get("startOpacity"), emitter.startOpacity);
		}
		if (options.containsKey("endOpacity")) {
			emitter.endOpacity = Values.ratio(options.get("endOpacity"), emitter.endOpacity);
		}
		if (options.containsKey("tint")) {
			setTint(TiConvert.toString(options.get("tint")));
		}
		if (options.containsKey("blend")) {
			setBlend(TiConvert.toString(options.get("blend")));
		}
		if (options.containsKey("emitting")) {
			emitter.emitting = TiConvert.toBoolean(options.get("emitting"), true);
		}
		if (options.containsKey("maxParticles")) {
			emitter.setMaxParticles(TiConvert.toInt(options.get("maxParticles"), emitter.getMaxParticles()));
		}
	}

	// --- Methods ----------------------------------------------------------

	/** One-shot burst of n particles (explosions), independent of `rate`. */
	@Kroll.method
	public void emit(int n)
	{
		emitter.emit(n);
	}

	/** Kills all live particles. */
	@Kroll.method
	public void clear()
	{
		emitter.clear();
	}

	// --- Sheet / target ---------------------------------------------------

	@Kroll.setProperty
	public void setSheet(Object value)
	{
		// Object + instanceof: a mistyped JS value must not reach a typed JNI slot
		SpriteSheetProxy proxy = (value instanceof SpriteSheetProxy) ? (SpriteSheetProxy) value : null;
		sheetProxy = proxy;
		emitter.sheet = (proxy != null) ? proxy.getSheet() : null;
	}

	@Kroll.getProperty
	public SpriteSheetProxy getSheet()
	{
		return sheetProxy;
	}

	/** Follow this sprite instead of the fixed x/y (null to detach). */
	@Kroll.setProperty
	public void setTarget(Object value)
	{
		SpriteProxy proxy = (value instanceof SpriteProxy) ? (SpriteProxy) value : null;
		targetProxy = proxy;
		emitter.target = (proxy != null) ? proxy.getSprite() : null;
	}

	@Kroll.getProperty
	public SpriteProxy getTarget()
	{
		return targetProxy;
	}

	// --- Configuration properties ----------------------------------------

	@Kroll.getProperty
	public int getFrame()
	{
		return emitter.frame;
	}

	@Kroll.setProperty
	public void setFrame(int value)
	{
		emitter.frame = value;
	}

	@Kroll.getProperty
	public float getX()
	{
		return emitter.x;
	}

	@Kroll.setProperty
	public void setX(float value)
	{
		emitter.x = value;
	}

	@Kroll.getProperty
	public float getY()
	{
		return emitter.y;
	}

	@Kroll.setProperty
	public void setY(float value)
	{
		emitter.y = value;
	}

	@Kroll.getProperty
	public float getOffsetX()
	{
		return emitter.offsetX;
	}

	@Kroll.setProperty
	public void setOffsetX(float value)
	{
		emitter.offsetX = value;
	}

	@Kroll.getProperty
	public float getOffsetY()
	{
		return emitter.offsetY;
	}

	@Kroll.setProperty
	public void setOffsetY(float value)
	{
		emitter.offsetY = value;
	}

	@Kroll.getProperty
	public int getZIndex()
	{
		return emitter.zIndex;
	}

	@Kroll.setProperty
	public void setZIndex(int value)
	{
		emitter.zIndex = value;
	}

	@Kroll.getProperty
	public float getRate()
	{
		return emitter.rate;
	}

	@Kroll.setProperty
	public void setRate(float value)
	{
		emitter.rate = value;
	}

	@Kroll.getProperty
	public float getLifetime()
	{
		return emitter.lifetime * 1000f;
	}

	@Kroll.setProperty
	public void setLifetime(float value)
	{
		emitter.lifetime = value / 1000f;
	}

	@Kroll.getProperty
	public float getSpeed()
	{
		return emitter.speed;
	}

	@Kroll.setProperty
	public void setSpeed(float value)
	{
		emitter.speed = value;
	}

	@Kroll.getProperty
	public float getAngle()
	{
		return emitter.angle;
	}

	@Kroll.setProperty
	public void setAngle(float value)
	{
		emitter.angle = value;
	}

	@Kroll.getProperty
	public float getSpread()
	{
		return emitter.spread;
	}

	@Kroll.setProperty
	public void setSpread(float value)
	{
		emitter.spread = value;
	}

	@Kroll.getProperty
	public float getGravity()
	{
		return emitter.gravity;
	}

	@Kroll.setProperty
	public void setGravity(float value)
	{
		emitter.gravity = value;
	}

	@Kroll.getProperty
	public float getSize()
	{
		return emitter.size;
	}

	@Kroll.setProperty
	public void setSize(float value)
	{
		emitter.size = value;
	}

	@Kroll.getProperty
	public float getStartScale()
	{
		return emitter.startScale;
	}

	@Kroll.setProperty
	public void setStartScale(Object value)
	{
		emitter.startScale = Values.ratio(value, emitter.startScale);
	}

	@Kroll.getProperty
	public float getEndScale()
	{
		return emitter.endScale;
	}

	@Kroll.setProperty
	public void setEndScale(Object value)
	{
		emitter.endScale = Values.ratio(value, emitter.endScale);
	}

	@Kroll.getProperty
	public float getStartOpacity()
	{
		return emitter.startOpacity;
	}

	@Kroll.setProperty
	public void setStartOpacity(Object value)
	{
		emitter.startOpacity = Values.ratio(value, emitter.startOpacity);
	}

	@Kroll.getProperty
	public float getEndOpacity()
	{
		return emitter.endOpacity;
	}

	@Kroll.setProperty
	public void setEndOpacity(Object value)
	{
		emitter.endOpacity = Values.ratio(value, emitter.endOpacity);
	}

	@Kroll.setProperty
	public void setTint(String value)
	{
		if (value == null) {
			emitter.tintR = 1f;
			emitter.tintG = 1f;
			emitter.tintB = 1f;
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			emitter.tintR = Color.red(color) / 255f;
			emitter.tintG = Color.green(color) / 255f;
			emitter.tintB = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// keep previous tint
		}
	}

	/** 'add' = particles brighten instead of cover (fire, sparks,
	 *  magic), 'multiply' darkens (smoke, dust), 'screen' lightens
	 *  softly; anything else = normal alpha blending. */
	@Kroll.setProperty
	public void setBlend(String value)
	{
		emitter.blendMode = SpriteBatch.blendModeFromString(value);
	}

	@Kroll.getProperty
	public String getBlend()
	{
		return SpriteBatch.blendModeName(emitter.blendMode);
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

	@Kroll.getProperty
	public boolean getEmitting()
	{
		return emitter.emitting;
	}

	@Kroll.setProperty
	public void setEmitting(boolean value)
	{
		emitter.emitting = value;
	}

	@Kroll.getProperty
	public int getMaxParticles()
	{
		return emitter.getMaxParticles();
	}

	@Kroll.setProperty
	public void setMaxParticles(int value)
	{
		emitter.setMaxParticles(value);
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Emitter";
	}
}
