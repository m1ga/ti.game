package ti.game;

import android.app.Activity;

import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.view.TiUIView;

import ti.game.engine.Scene;

/**
 * The game canvas: createGameView({ backgroundColor: '#202030' }).
 *
 * Owns the native Scene, so sprites can be added before (or after) the view
 * is realized. Rendering runs continuously once the view is on screen.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class GameViewProxy extends TiViewProxy
{
	private final Scene scene = new Scene();
	private TiGameView gameView;

	@Override
	public TiUIView createView(Activity activity)
	{
		gameView = new TiGameView(this, scene);
		gameView.getLayoutParams().autoFillsWidth = true;
		gameView.getLayoutParams().autoFillsHeight = true;
		return gameView;
	}

	public Scene getScene()
	{
		return scene;
	}

	@Override
	public void handleCreationDict(org.appcelerator.kroll.KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("debug")) {
			scene.debugAll = org.appcelerator.titanium.util.TiConvert.toBoolean(options.get("debug"));
		}
	}

	/** Renders debug overlays (collision box, bounds, anchor) for every sprite. */
	@Kroll.getProperty
	public boolean getDebug()
	{
		return scene.debugAll;
	}

	@Kroll.setProperty
	public void setDebug(boolean value)
	{
		scene.debugAll = value;
	}

	@Kroll.method
	public void add(SpriteProxy spriteProxy)
	{
		if (spriteProxy != null) {
			scene.add(spriteProxy.getSprite());
		}
	}

	@Kroll.method
	public void remove(SpriteProxy spriteProxy)
	{
		if (spriteProxy != null) {
			scene.remove(spriteProxy.getSprite());
		}
	}

	@Kroll.method
	public void removeAllSprites()
	{
		scene.clear();
	}

	/**
	 * Native camera follow with a vertical dead-zone: the view scrolls when
	 * the sprite rises above `topMargin` (fraction of the surface height,
	 * default 0.33) or sinks below `bottomMargin` (default 0.7), clamped to
	 * `maxY` (default 0 — never scrolls below the start position).
	 */
	@Kroll.method
	public void follow(SpriteProxy spriteProxy, @Kroll.argument(optional = true) org.appcelerator.kroll.KrollDict options)
	{
		if (spriteProxy == null) {
			scene.followTarget = null;
			return;
		}
		if (options != null) {
			if (options.containsKey("topMargin")) {
				scene.followTopFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("topMargin"));
			}
			if (options.containsKey("bottomMargin")) {
				scene.followBottomFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("bottomMargin"));
			}
			if (options.containsKey("maxY")) {
				scene.cameraMaxY = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("maxY"));
			}
		}
		scene.followTarget = spriteProxy.getSprite();
	}

	@Kroll.method
	public void stopFollow()
	{
		scene.followTarget = null;
	}

	@Kroll.getProperty
	public float getCameraX()
	{
		return scene.cameraX;
	}

	@Kroll.setProperty
	public void setCameraX(float value)
	{
		scene.cameraX = value;
	}

	@Kroll.getProperty
	public float getCameraY()
	{
		return scene.cameraY;
	}

	@Kroll.setProperty
	public void setCameraY(float value)
	{
		scene.cameraY = value;
	}

	/** Manually pause the render loop (also happens on activity pause). */
	@Kroll.method
	public void pause()
	{
		if (gameView != null) {
			gameView.pauseRendering();
		}
	}

	@Kroll.method
	public void resume()
	{
		if (gameView != null) {
			gameView.resumeRendering();
		}
	}

	/** Rendered surface size in pixels — the scene coordinate space. */
	@Kroll.getProperty
	public int getSurfaceWidth()
	{
		return (gameView != null) ? gameView.getRenderer().surfaceWidth() : 0;
	}

	@Kroll.getProperty
	public int getSurfaceHeight()
	{
		return (gameView != null) ? gameView.getRenderer().surfaceHeight() : 0;
	}

	@Override
	public String getApiName()
	{
		return "ti.game.GameView";
	}
}
