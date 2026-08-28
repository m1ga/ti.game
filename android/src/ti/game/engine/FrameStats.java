package ti.game.engine;

import java.util.Arrays;

/**
 * One second of render telemetry: frame CPU cost (average, p95, peak),
 * dropped frames, per-phase timings and the batcher's counters. Feeds both
 * the on-screen debug HUD and the 'performance' event.
 *
 * Everything here is off unless `enabled` is set, and the renderer reads
 * that flag before it touches a clock — with the HUD off and no
 * 'performance' listener the engine pays for no measurement at all.
 *
 * Written and read on the GL thread only; `enabled` is the single field
 * that crosses threads.
 *
 * Two metrics iOS reports and Android cannot: average present time and
 * present failures. GLSurfaceView calls eglSwapBuffers inside its own
 * GLThread after onDrawFrame returns, so there is no point in the renderer
 * where the swap can be timed or its result read. They are omitted from
 * the HUD and from the event payload here rather than reported as zero.
 *
 * iOS twin: ios/Classes/TGFrameStats.{h,m}.
 */
public class FrameStats
{
	private static final int MAX_SAMPLES = 240;
	private static final long WINDOW_NANOS = 1_000_000_000L;

	/** One closed window's worth of numbers. Reused — copy what you keep. */
	public static final class Snapshot
	{
		public double fps;
		public double averageCpuMs;
		public double p95CpuMs;
		public double maxCpuMs;
		public double averageUpdateMs;
		public double averageTexturePrepareMs;
		public double averageBatchMs;
		public int droppedFrames;
		public int sprites;
		public int visibleSprites;
		public int emitters;
		public int particles;
		public int drawCalls;
		public int textureSwitches;
	}

	/** Master switch — HUD on, or a 'performance' listener attached. */
	public volatile boolean enabled = false;

	// --- Per-frame slots, filled by the renderer before addFrame ---------
	public double updateMs;
	public double texturePrepareMs;
	public double batchMs;
	public int sprites;
	public int visibleSprites;
	public int emitters;
	public int particles;
	public int drawCalls;
	public int textureSwitches;

	// --- Window accumulators (GL thread) ---------------------------------
	private final Snapshot snapshot = new Snapshot();
	private final double[] samples = new double[MAX_SAMPLES];
	private final double[] sortBuffer = new double[MAX_SAMPLES];
	private int sampleCount;
	private boolean windowOpen;
	private long windowStartNanos;
	private double totalCpuMs;
	private double maxCpuMs;
	private double totalUpdateMs;
	private double totalTexturePrepareMs;
	private double totalBatchMs;
	private int measuredFrames;
	private int droppedFrames;

	public void reset()
	{
		windowOpen = false;
		sampleCount = 0;
		totalCpuMs = 0;
		maxCpuMs = 0;
		totalUpdateMs = 0;
		totalTexturePrepareMs = 0;
		totalBatchMs = 0;
		measuredFrames = 0;
		droppedFrames = 0;
	}

	/**
	 * Records one frame. `cpuMs` is the renderer's own cost, measured after
	 * the maxFps sleep so a frame rate cap never reads as work. The
	 * interval between consecutive frames against the expected one gives
	 * the dropped-frame count: in continuous mode eglSwapBuffers blocks on
	 * vsync, so that interval is the real presentation cadence.
	 */
	public void addFrame(double cpuMs, long nowNanos, long intervalNanos, long targetNanos)
	{
		if (!windowOpen) {
			reset();
			windowOpen = true;
			windowStartNanos = nowNanos;
		}
		if (sampleCount < MAX_SAMPLES) {
			samples[sampleCount++] = cpuMs;
		}
		totalCpuMs += cpuMs;
		if (cpuMs > maxCpuMs) {
			maxCpuMs = cpuMs;
		}
		totalUpdateMs += updateMs;
		totalTexturePrepareMs += texturePrepareMs;
		totalBatchMs += batchMs;
		measuredFrames++;

		if (targetNanos > 0 && intervalNanos > targetNanos + targetNanos / 2) {
			long intervals = Math.round((double) intervalNanos / (double) targetNanos);
			if (intervals > 1) {
				droppedFrames += (int) (intervals - 1);
			}
		}
	}

	public boolean windowClosed(long nowNanos)
	{
		return windowOpen && (nowNanos - windowStartNanos) >= WINDOW_NANOS;
	}

	/** Averages the window, starts a new one, and returns the numbers. */
	public Snapshot closeWindow(long nowNanos)
	{
		double elapsed = (nowNanos - windowStartNanos) / 1_000_000_000.0;
		int frames = Math.max(1, measuredFrames);

		snapshot.fps = (elapsed > 0) ? measuredFrames / elapsed : 0;
		snapshot.averageCpuMs = totalCpuMs / frames;
		snapshot.maxCpuMs = maxCpuMs;
		snapshot.p95CpuMs = percentile95();
		snapshot.averageUpdateMs = totalUpdateMs / frames;
		snapshot.averageTexturePrepareMs = totalTexturePrepareMs / frames;
		snapshot.averageBatchMs = totalBatchMs / frames;
		snapshot.droppedFrames = droppedFrames;
		snapshot.sprites = sprites;
		snapshot.visibleSprites = visibleSprites;
		snapshot.emitters = emitters;
		snapshot.particles = particles;
		snapshot.drawCalls = drawCalls;
		snapshot.textureSwitches = textureSwitches;

		reset();
		windowOpen = true;
		windowStartNanos = nowNanos;
		return snapshot;
	}

	private double percentile95()
	{
		if (sampleCount == 0) {
			return 0;
		}
		System.arraycopy(samples, 0, sortBuffer, 0, sampleCount);
		Arrays.sort(sortBuffer, 0, sampleCount);
		int index = (int) Math.ceil(sampleCount * 0.95) - 1;
		if (index < 0) {
			index = 0;
		}
		if (index > sampleCount - 1) {
			index = sampleCount - 1;
		}
		return sortBuffer[index];
	}
}
