package ti.game.engine;

/** Easing functions for native tweens. Input/output t in [0, 1]. */
public final class Easing
{
	public static final String LINEAR = "linear";
	public static final String EASE_IN = "easeIn";
	public static final String EASE_OUT = "easeOut";
	public static final String EASE_IN_OUT = "easeInOut";
	public static final String BOUNCE = "bounce";
	public static final String ELASTIC = "elastic";

	private Easing()
	{
	}

	public static float apply(String name, float t)
	{
		if (name == null) {
			return t;
		}
		switch (name) {
			case EASE_IN:
				return t * t * t;
			case EASE_OUT: {
				float u = 1f - t;
				return 1f - u * u * u;
			}
			case EASE_IN_OUT:
				return (t < 0.5f) ? 4f * t * t * t : 1f - (float) Math.pow(-2f * t + 2f, 3) / 2f;
			case BOUNCE:
				return bounceOut(t);
			case ELASTIC: {
				if (t <= 0f || t >= 1f) {
					return t;
				}
				double c4 = (2 * Math.PI) / 3;
				return (float) (Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * c4) + 1);
			}
			case LINEAR:
			default:
				return t;
		}
	}

	private static float bounceOut(float t)
	{
		float n1 = 7.5625f;
		float d1 = 2.75f;
		if (t < 1f / d1) {
			return n1 * t * t;
		} else if (t < 2f / d1) {
			t -= 1.5f / d1;
			return n1 * t * t + 0.75f;
		} else if (t < 2.5f / d1) {
			t -= 2.25f / d1;
			return n1 * t * t + 0.9375f;
		} else {
			t -= 2.625f / d1;
			return n1 * t * t + 0.984375f;
		}
	}
}
