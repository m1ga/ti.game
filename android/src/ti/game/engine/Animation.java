package ti.game.engine;

/** Immutable description of a sprite-sheet animation: frame indices + timing. */
public class Animation
{
	public final String name;
	public final int[] frames;
	public final float fps;
	public final boolean loop;
	// Sheet frame to show once a non-looping run finishes; -1 = hold the
	// last animation frame.
	public final int endFrame;

	public Animation(String name, int[] frames, float fps, boolean loop, int endFrame)
	{
		this.name = name;
		this.frames = frames;
		this.fps = (fps > 0f) ? fps : 12f;
		this.loop = loop;
		this.endFrame = endFrame;
	}
}
