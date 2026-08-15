package ti.game;

import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.MediaPlayer;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.util.TiConvert;

import ti.game.engine.SoundEngine;

/**
 * Native sound playback: createSound({ url: 'assets/jump.wav' }).
 *
 * Two backends behind one API, chosen with the `music` flag:
 *
 *   Effect (default): the sample is loaded into the shared SoundPool —
 *   low latency, overlapping plays (jump, hit, collect).
 *   Music (music: true): a MediaPlayer streams the file — for longer
 *   tracks; loops seamlessly and pauses/resumes with the activity.
 *
 * WAV, MP3 and OGG from app resources ('assets/x.wav') or file paths.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class SoundProxy extends KrollProxy
	implements SoundEngine.LoadListener, SoundEngine.LifecycleListener
{
	private static final String LCAT = "TiGameSound";

	private boolean music = false;
	private volatile float volume = 1f;
	private volatile boolean loop = false;

	// Effect mode (shared SoundPool)
	private int sampleId = -1;
	private volatile boolean loaded = false;
	private volatile boolean pendingPlay = false;
	private int lastStreamId = 0;

	// Music mode (own MediaPlayer)
	private MediaPlayer mediaPlayer;
	private boolean resumeOnActivityResume = false;

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		String url = options.optString("url", null);
		music = options.optBoolean("music", false);
		loop = options.optBoolean("loop", false);
		if (options.containsKey("volume")) {
			volume = TiConvert.toFloat(options.get("volume"));
		}
		if (url == null) {
			Log.e(LCAT, "createSound requires a 'url' property");
			return;
		}
		try {
			openSource(url);
		} catch (Exception e) {
			Log.e(LCAT, "Could not load sound '" + url + "': " + e.getMessage());
		}
	}

	/** Resolves the url and feeds it to the right backend. */
	private void openSource(String url) throws Exception
	{
		// On a module proxy, resolveUrl resolves against the MODULE's asset
		// space (app_appdata/<moduleid>/...), not the app's Resources — so
		// try the resolved location only if it actually exists, and fall
		// back to the file packaged in the app's Resources (APK assets).
		String resolved = resolveUrl(null, url);
		String path = null;
		AssetFileDescriptor afd = null;
		if (resolved.startsWith("app://")) {
			afd = TiApplication.getInstance().getAssets()
				.openFd("Resources/" + resolved.substring("app://".length()));
		} else {
			String candidate = stripFileScheme(resolved);
			if (new java.io.File(candidate).exists()) {
				path = candidate;
			} else {
				afd = TiApplication.getInstance().getAssets().openFd("Resources/" + url);
			}
		}

		if (music) {
			mediaPlayer = new MediaPlayer();
			mediaPlayer.setAudioAttributes(new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_GAME)
				.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
				.build());
			if (afd != null) {
				mediaPlayer.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
				afd.close();
			} else {
				mediaPlayer.setDataSource(path);
			}
			mediaPlayer.prepare();
			mediaPlayer.setLooping(loop);
			mediaPlayer.setVolume(volume, volume);
			SoundEngine.getInstance().addLifecycleListener(this);
		} else {
			SoundEngine engine = SoundEngine.getInstance();
			if (afd != null) {
				sampleId = engine.load(afd, this);
				afd.close();
			} else {
				sampleId = engine.load(path, this);
			}
		}
	}

	private static String stripFileScheme(String url)
	{
		return url.startsWith("file://") ? url.substring("file://".length()) : url;
	}

	// --- Playback --------------------------------------------------------

	@Kroll.method
	public void play()
	{
		if (music) {
			if (mediaPlayer != null) {
				mediaPlayer.start();
			}
		} else if (loaded) {
			lastStreamId = SoundEngine.getInstance().play(sampleId, volume, loop);
		} else if (sampleId >= 0) {
			pendingPlay = true; // sample still loading — play as soon as it's ready
		}
	}

	@Kroll.method
	public void pause()
	{
		pendingPlay = false;
		resumeOnActivityResume = false; // an explicit pause survives the lifecycle
		if (music) {
			if (mediaPlayer != null && mediaPlayer.isPlaying()) {
				mediaPlayer.pause();
			}
		} else {
			SoundEngine.getInstance().pauseStream(lastStreamId);
		}
	}

	@Kroll.method
	public void stop()
	{
		pendingPlay = false;
		// Clear the lifecycle flag: onPause may already have parked this
		// track for auto-resume (activity teardown pauses before the JS
		// 'close' event runs) — an explicit stop() must win, or the music
		// comes back when the next game view resumes the engine.
		resumeOnActivityResume = false;
		if (music) {
			if (mediaPlayer != null) {
				// pause + rewind instead of MediaPlayer.stop(), which would
				// require a re-prepare before the next play()
				if (mediaPlayer.isPlaying()) {
					mediaPlayer.pause();
				}
				mediaPlayer.seekTo(0);
			}
		} else {
			SoundEngine.getInstance().stopStream(lastStreamId);
			lastStreamId = 0;
		}
	}

	// --- Properties ------------------------------------------------------

	@Kroll.getProperty
	public float getVolume()
	{
		return volume;
	}

	@Kroll.setProperty
	public void setVolume(float value)
	{
		volume = value;
		if (music) {
			if (mediaPlayer != null) {
				mediaPlayer.setVolume(value, value);
			}
		} else {
			SoundEngine.getInstance().setStreamVolume(lastStreamId, value);
		}
	}

	@Kroll.getProperty
	public boolean getLoop()
	{
		return loop;
	}

	@Kroll.setProperty
	public void setLoop(boolean value)
	{
		loop = value;
		if (music && mediaPlayer != null) {
			mediaPlayer.setLooping(value);
		}
	}

	@Kroll.getProperty
	public boolean getMusic()
	{
		return music;
	}

	// --- SoundEngine.LoadListener (SoundPool loads asynchronously) -------

	@Override
	public void onLoadComplete(int completedSampleId, boolean success)
	{
		if (completedSampleId != sampleId) {
			return;
		}
		loaded = success;
		if (!success) {
			Log.e(LCAT, "Sound sample failed to load");
			pendingPlay = false;
		} else if (pendingPlay) {
			pendingPlay = false;
			play();
		}
	}

	// --- SoundEngine.LifecycleListener (music follows the activity) ------

	@Override
	public void onEnginePause()
	{
		if (mediaPlayer != null && mediaPlayer.isPlaying()) {
			mediaPlayer.pause();
			resumeOnActivityResume = true;
		}
	}

	@Override
	public void onEngineResume()
	{
		if (resumeOnActivityResume) {
			resumeOnActivityResume = false;
			if (mediaPlayer != null) {
				mediaPlayer.start();
			}
		}
	}

	// --- Cleanup (framework proxy teardown) ------------------------------

	@Override
	public void release()
	{
		if (sampleId >= 0) {
			SoundEngine.getInstance().unload(sampleId);
			sampleId = -1;
		}
		if (mediaPlayer != null) {
			SoundEngine.getInstance().removeLifecycleListener(this);
			mediaPlayer.release();
			mediaPlayer = null;
		}
		super.release();
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Sound";
	}
}
