package ti.game.engine;

/** Immutable description of a sprite-sheet animation: frame indices + timing. */
public class Animation
{
	public final String name;
	public final int[] frames;
	public final float fps;
	public final boolean loop;

	public Animation(String name, int[] frames, float fps, boolean loop)
	{
		this.name = name;
		this.frames = frames;
		this.fps = (fps > 0f) ? fps : 12f;
		this.loop = loop;
	}
}
