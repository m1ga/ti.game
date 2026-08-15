package ti.game.engine;

import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.SoundPool;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Shared audio backend for sound effects: one SoundPool (low latency, up
 * to 8 overlapping streams) that every effect-mode SoundProxy loads its
 * sample into. Music-mode proxies own their MediaPlayer but register here
 * for activity lifecycle, so pausing the app pauses everything (effects
 * via autoPause, music via the listeners) and resuming brings it back.
 */
public class SoundEngine
{
	/** Sample finished loading (SoundPool loads asynchronously). */
	public interface LoadListener {
		void onLoadComplete(int sampleId, boolean success);
	}

	/** Activity went to / returned from the background. */
	public interface LifecycleListener {
		void onEnginePause();
		void onEngineResume();
	}

	private static SoundEngine instance;

	private final SoundPool soundPool;
	private final Object loadLock = new Object();
	private final Map<Integer, LoadListener> loadListeners = new HashMap<>();
	private final Map<Integer, Boolean> earlyLoadResults = new HashMap<>();
	private final CopyOnWriteArrayList<LifecycleListener> lifecycleListeners = new CopyOnWriteArrayList<>();

	public static synchronized SoundEngine getInstance()
	{
		if (instance == null) {
			instance = new SoundEngine();
		}
		return instance;
	}

	private static synchronized SoundEngine instanceOrNull()
	{
		return instance;
	}

	private SoundEngine()
	{
		AudioAttributes attributes = new AudioAttributes.Builder()
			.setUsage(AudioAttributes.USAGE_GAME)
			.setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
			.build();
		soundPool = new SoundPool.Builder()
			.setMaxStreams(8)
			.setAudioAttributes(attributes)
			.build();
		soundPool.setOnLoadCompleteListener(new SoundPool.OnLoadCompleteListener() {
			@Override
			public void onLoadComplete(SoundPool pool, int sampleId, int status)
			{
				LoadListener listener;
				synchronized (loadLock) {
					listener = loadListeners.remove(sampleId);
					if (listener == null) {
						// completed before the proxy registered — remember the result
						earlyLoadResults.put(sampleId, status == 0);
						return;
					}
				}
				listener.onLoadComplete(sampleId, status == 0);
			}
		});
	}

	// --- Effect samples --------------------------------------------------

	public int load(AssetFileDescriptor afd, LoadListener listener)
	{
		return register(soundPool.load(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength(), 1),
			listener);
	}

	public int load(String path, LoadListener listener)
	{
		return register(soundPool.load(path, 1), listener);
	}

	private int register(int sampleId, LoadListener listener)
	{
		Boolean early;
		synchronized (loadLock) {
			early = earlyLoadResults.remove(sampleId);
			if (early == null) {
				loadListeners.put(sampleId, listener);
			}
		}
		if (early != null) {
			listener.onLoadComplete(sampleId, early);
		}
		return sampleId;
	}

	/** Plays a loaded sample; returns the stream id (0 on failure). */
	public int play(int sampleId, float volume, boolean loop)
	{
		return soundPool.play(sampleId, volume, volume, 1, loop ? -1 : 0, 1f);
	}

	public void pauseStream(int streamId)
	{
		if (streamId != 0) {
			soundPool.pause(streamId);
		}
	}

	public void resumeStream(int streamId)
	{
		if (streamId != 0) {
			soundPool.resume(streamId);
		}
	}

	public void stopStream(int streamId)
	{
		if (streamId != 0) {
			soundPool.stop(streamId);
		}
	}

	public void setStreamVolume(int streamId, float volume)
	{
		if (streamId != 0) {
			soundPool.setVolume(streamId, volume, volume);
		}
	}

	public void unload(int sampleId)
	{
		soundPool.unload(sampleId);
		synchronized (loadLock) {
			loadListeners.remove(sampleId);
			earlyLoadResults.remove(sampleId);
		}
	}

	// --- Lifecycle (hooked in by TiGameView's activity callbacks) --------

	public void addLifecycleListener(LifecycleListener listener)
	{
		lifecycleListeners.addIfAbsent(listener);
	}

	public void removeLifecycleListener(LifecycleListener listener)
	{
		lifecycleListeners.remove(listener);
	}

	/** Static so callers never create the engine just to pause nothing. */
	public static void notifyActivityPaused()
	{
		SoundEngine engine = instanceOrNull();
		if (engine == null) {
			return;
		}
		engine.soundPool.autoPause();
		for (LifecycleListener listener : engine.lifecycleListeners) {
			listener.onEnginePause();
		}
	}

	public static void notifyActivityResumed()
	{
		SoundEngine engine = instanceOrNull();
		if (engine == null) {
			return;
		}
		engine.soundPool.autoResume();
		for (LifecycleListener listener : engine.lifecycleListeners) {
			listener.onEngineResume();
		}
	}
}
