package ti.game.engine;

/**
 * Native property tween, ticked by the render loop. This exists because JS
 * can't animate per-frame across the bridge — sprite.animate({...}) creates
 * one of these and the sprite fires a 'complete' event when it finishes.
 */
public class Tween
{
	// Target values; null = property not animated
	public Float toX, toY, toScaleX, toScaleY, toRotation, toOpacity, toGlowOpacity;
	// Sheet frame to show when the tween finishes; null = leave unchanged
	public Integer endFrame;
	public float duration = 0.3f; // seconds
	public float delay = 0f;
	public String easing = Easing.LINEAR;

	private float fromX, fromY, fromScaleX, fromScaleY, fromRotation, fromOpacity, fromGlowOpacity;
	private float elapsed = 0f;
	private boolean started = false;

	void captureStartValues(Sprite s)
	{
		fromX = s.x;
		fromY = s.y;
		fromScaleX = s.scaleX;
		fromScaleY = s.scaleY;
		fromRotation = s.rotation;
		fromOpacity = s.opacity;
		fromGlowOpacity = s.glowOpacity;
	}

	/** Advances the tween; returns true when finished. Called on the GL thread. */
	boolean update(Sprite s, float dt)
	{
		elapsed += dt;
		if (elapsed < delay) {
			return false;
		}
		if (!started) {
			// Re-capture at actual start so delayed tweens pick up current values
			captureStartValues(s);
			started = true;
		}
		float t = (duration > 0f) ? Math.min(1f, (elapsed - delay) / duration) : 1f;
		float e = Easing.apply(easing, t);

		if (toX != null) {
			s.x = fromX + (toX - fromX) * e;
		}
		if (toY != null) {
			s.y = fromY + (toY - fromY) * e;
		}
		if (toScaleX != null) {
			s.scaleX = fromScaleX + (toScaleX - fromScaleX) * e;
		}
		if (toScaleY != null) {
			s.scaleY = fromScaleY + (toScaleY - fromScaleY) * e;
		}
		if (toRotation != null) {
			s.rotation = fromRotation + (toRotation - fromRotation) * e;
		}
		if (toOpacity != null) {
			s.opacity = fromOpacity + (toOpacity - fromOpacity) * e;
		}
		if (toGlowOpacity != null) {
			s.glowOpacity = fromGlowOpacity + (toGlowOpacity - fromGlowOpacity) * e;
		}
		boolean finished = t >= 1f;
		if (finished && endFrame != null) {
			s.frame = endFrame;
		}
		return finished;
	}
}
