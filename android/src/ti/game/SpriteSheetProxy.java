package ti.game;

import android.graphics.Bitmap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.io.TiBaseFile;
import org.appcelerator.titanium.io.TiFileFactory;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiDrawableReference;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

import ti.game.engine.SpriteSheet;

/**
 * JS-facing sprite sheet. Supports two formats:
 *
 *   Grid:   createSpriteSheet({ image: 'hero.png', frameWidth: 64, frameHeight: 64 })
 *   Atlas:  createSpriteSheet({ image: 'hero.png', atlas: 'hero.json' })  // TexturePacker JSON
 *
 * The image is decoded and uploaded on the GL thread the first time a
 * sprite using this sheet is rendered.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class SpriteSheetProxy extends KrollProxy implements SpriteSheet.Loader
{
	private static final String LCAT = "TiGameSpriteSheet";

	private SpriteSheet sheet;
	private String imagePath;
	private String atlasPath;
	private final List<String> frameNames = new ArrayList<>();

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		imagePath = options.optString("image", null);
		atlasPath = options.optString("atlas", null);
		int frameWidth = options.optInt("frameWidth", 0);
		int frameHeight = options.optInt("frameHeight", 0);
		sheet = new SpriteSheet(this, frameWidth, frameHeight);
		sheet.smoothing = options.optBoolean("smoothing", true);
		sheet.repeat = options.optBoolean("repeat", false);
		if (imagePath == null) {
			Log.e(LCAT, "createSpriteSheet requires an 'image' property");
		}
	}

	public SpriteSheet getSheet()
	{
		return sheet;
	}

	// SpriteSheet.Loader — called from the GL thread on first use
	@Override
	public Bitmap load(SpriteSheet target)
	{
		if (imagePath == null) {
			return null;
		}
		Bitmap bitmap = TiDrawableReference.fromUrl(this, imagePath).getBitmap();
		if (bitmap == null) {
			Log.e(LCAT, "Could not load sheet image: " + imagePath);
			return null;
		}
		if (atlasPath != null) {
			parseAtlas(bitmap.getWidth(), bitmap.getHeight());
		}
		return bitmap;
	}

	/** Parses a TexturePacker JSON atlas (hash or array format) into UV frames. */
	private void parseAtlas(int imageWidth, int imageHeight)
	{
		try {
			String json = readTextFile(resolveUrl(null, atlasPath));
			JSONObject root = new JSONObject(json);
			Object framesNode = root.get("frames");
			List<SpriteSheet.Frame> frames = new ArrayList<>();
			frameNames.clear();

			if (framesNode instanceof JSONArray) {
				JSONArray array = (JSONArray) framesNode;
				for (int i = 0; i < array.length(); i++) {
					JSONObject entry = array.getJSONObject(i);
					frameNames.add(entry.optString("filename", String.valueOf(i)));
					frames.add(toFrame(entry.getJSONObject("frame"), imageWidth, imageHeight));
				}
			} else {
				JSONObject hash = (JSONObject) framesNode;
				List<String> names = new ArrayList<>();
				Iterator<String> keys = hash.keys();
				while (keys.hasNext()) {
					names.add(keys.next());
				}
				Collections.sort(names);
				for (String name : names) {
					frameNames.add(name);
					frames.add(toFrame(hash.getJSONObject(name).getJSONObject("frame"), imageWidth, imageHeight));
				}
			}
			sheet.setFrames(frames.toArray(new SpriteSheet.Frame[0]));
		} catch (Exception e) {
			Log.e(LCAT, "Could not parse atlas '" + atlasPath + "': " + e.getMessage());
		}
	}

	private static SpriteSheet.Frame toFrame(JSONObject f, int imageWidth, int imageHeight)
		throws org.json.JSONException
	{
		int x = f.getInt("x");
		int y = f.getInt("y");
		int w = f.getInt("w");
		int h = f.getInt("h");
		return new SpriteSheet.Frame(
			x / (float) imageWidth, y / (float) imageHeight,
			(x + w) / (float) imageWidth, (y + h) / (float) imageHeight,
			w, h);
	}

	private static String readTextFile(String url) throws Exception
	{
		TiBaseFile file = TiFileFactory.createTitaniumFile(url, false);
		try (InputStream in = file.getInputStream();
			 BufferedReader reader = new BufferedReader(new InputStreamReader(in, "UTF-8"))) {
			StringBuilder sb = new StringBuilder();
			String line;
			while ((line = reader.readLine()) != null) {
				sb.append(line).append('\n');
			}
			return sb.toString();
		}
	}

	/** Frame index for an atlas frame name, or -1. Lets JS build animations by name. */
	@Kroll.method
	public int frameIndex(String name)
	{
		return frameNames.indexOf(name);
	}

	@Kroll.getProperty
	public int getFrameCount()
	{
		return sheet.frameCount();
	}

	@Kroll.getProperty
	public String[] getFrameNames()
	{
		return frameNames.toArray(new String[0]);
	}

	@Override
	public String getApiName()
	{
		return "ti.game.SpriteSheet";
	}
}
