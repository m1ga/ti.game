package ti.game;

import android.graphics.Bitmap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.io.TiBaseFile;
import org.appcelerator.titanium.io.TiFileFactory;
import org.appcelerator.titanium.view.TiDrawableReference;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import ti.game.engine.BitmapFont;
import ti.game.engine.DefaultFont;
import ti.game.engine.SpriteSheet;

/**
 * JS-facing bitmap font for createText. Three ways to build one:
 *
 *   BMFont: createFont({ font: 'assets/hud.fnt' })   // AngelCode text or JSON
 *   Grid:   createFont({ image: 'assets/mono.png', charWidth: 9, charHeight: 15 })
 *   Default: createFont({})                          // built-in pixel font
 *
 * Metrics (and BMFont kerning) parse immediately on the JS thread, so text
 * lays out before the glyph texture is uploaded; the image itself loads
 * lazily on the GL thread like any sprite sheet. Grid fonts map the cells
 * row-major onto `characters` (default: ASCII 32..126).
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class FontProxy extends KrollProxy implements SpriteSheet.Loader
{
	private static final String LCAT = "TiGameFont";

	private BitmapFont font;
	private String imagePath;

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		String fontPath = options.optString("font", null);
		imagePath = options.optString("image", null);
		boolean smoothing = options.optBoolean("smoothing", true);

		if (fontPath != null) {
			parseBmfont(fontPath, options);
		} else if (imagePath != null) {
			int charWidth = options.optInt("charWidth", 0);
			int charHeight = options.optInt("charHeight", 0);
			if (charWidth <= 0 || charHeight <= 0) {
				Log.e(LCAT, "Grid fonts need charWidth and charHeight");
				font = DefaultFont.create();
				return;
			}
			String characters = options.optString("characters", defaultCharacters());
			SpriteSheet sheet = new SpriteSheet(this, charWidth, charHeight);
			sheet.smoothing = smoothing;
			font = BitmapFont.grid(sheet, characters, charWidth, charHeight);
		} else {
			font = DefaultFont.create();
			return;
		}
		if (font != null && options.containsKey("smoothing")) {
			font.sheet.smoothing = smoothing;
		}
	}

	public BitmapFont getFont()
	{
		return font;
	}

	private static String defaultCharacters()
	{
		StringBuilder characters = new StringBuilder();
		for (char c = 32; c < 127; c++) {
			characters.append(c);
		}
		return characters.toString();
	}

	/** Parses a BMFont descriptor — the AngelCode text format or its JSON export. */
	private void parseBmfont(String fontPath, KrollDict options)
	{
		try {
			String source = readTextFile(fontPath);
			SpriteSheet sheet = new SpriteSheet(this, 0, 0);
			font = new BitmapFont(sheet);
			String pageFile = source.trim().startsWith("{")
				? parseJson(source) : parseText(source);
			if (imagePath == null) {
				// page images live next to the descriptor
				int slash = fontPath.lastIndexOf('/');
				imagePath = (slash >= 0) ? fontPath.substring(0, slash + 1) + pageFile : pageFile;
			}
		} catch (Exception e) {
			Log.e(LCAT, "Could not parse font '" + fontPath + "': " + e.getMessage());
			font = DefaultFont.create();
		}
	}

	/** AngelCode text format: one `tag key=value ...` line per entry. */
	private String parseText(String source)
	{
		float scaleW = 1f;
		float scaleH = 1f;
		String pageFile = null;
		Map<Integer, BitmapFont.Glyph> glyphs = new HashMap<>();
		Map<Integer, Float> kerning = new HashMap<>();
		List<SpriteSheet.Frame> frames = new ArrayList<>();
		for (String line : source.split("\n")) {
			Map<String, String> fields = parseFields(line);
			if (line.startsWith("common ")) {
				font.lineHeight = intField(fields, "lineHeight", 0);
				scaleW = Math.max(1, intField(fields, "scaleW", 1));
				scaleH = Math.max(1, intField(fields, "scaleH", 1));
			} else if (line.startsWith("page ") && pageFile == null) {
				pageFile = fields.get("file");
			} else if (line.startsWith("char ")) {
				int x = intField(fields, "x", 0);
				int y = intField(fields, "y", 0);
				int w = intField(fields, "width", 0);
				int h = intField(fields, "height", 0);
				frames.add(new SpriteSheet.Frame(
					x / scaleW, y / scaleH, (x + w) / scaleW, (y + h) / scaleH, w, h));
				glyphs.put(intField(fields, "id", 0), new BitmapFont.Glyph(
					frames.size() - 1, w, h,
					intField(fields, "xoffset", 0), intField(fields, "yoffset", 0),
					intField(fields, "xadvance", 0)));
			} else if (line.startsWith("kerning ")) {
				int first = intField(fields, "first", 0);
				int second = intField(fields, "second", 0);
				if (first <= 0xffff && second <= 0xffff) {
					kerning.put((first << 16) | second, (float) intField(fields, "amount", 0));
				}
			}
		}
		font.sheet.setFrames(frames.toArray(new SpriteSheet.Frame[0]));
		font.setGlyphs(glyphs);
		font.setKerning(kerning);
		return pageFile;
	}

	private static Map<String, String> parseFields(String line)
	{
		Map<String, String> fields = new HashMap<>();
		int i = 0;
		int length = line.length();
		while (i < length) {
			int eq = line.indexOf('=', i);
			if (eq < 0) {
				break;
			}
			int keyStart = line.lastIndexOf(' ', eq - 1) + 1;
			String key = line.substring(keyStart, eq);
			int valueEnd;
			String value;
			if (eq + 1 < length && line.charAt(eq + 1) == '"') {
				valueEnd = line.indexOf('"', eq + 2);
				value = line.substring(eq + 2, (valueEnd < 0) ? length : valueEnd);
				valueEnd = (valueEnd < 0) ? length : valueEnd + 1;
			} else {
				valueEnd = line.indexOf(' ', eq + 1);
				if (valueEnd < 0) {
					valueEnd = length;
				}
				value = line.substring(eq + 1, valueEnd);
			}
			fields.put(key, value.trim());
			i = valueEnd;
		}
		return fields;
	}

	private static int intField(Map<String, String> fields, String key, int fallback)
	{
		String value = fields.get(key);
		if (value == null || value.isEmpty()) {
			return fallback;
		}
		try {
			return Math.round(Float.parseFloat(value));
		} catch (NumberFormatException e) {
			return fallback;
		}
	}

	/** BMFont JSON export: { common, pages, chars, kernings }. */
	private String parseJson(String source) throws Exception
	{
		JSONObject root = new JSONObject(source);
		JSONObject common = root.getJSONObject("common");
		font.lineHeight = common.optInt("lineHeight", 0);
		float scaleW = Math.max(1, common.optInt("scaleW", 1));
		float scaleH = Math.max(1, common.optInt("scaleH", 1));

		Map<Integer, BitmapFont.Glyph> glyphs = new HashMap<>();
		List<SpriteSheet.Frame> frames = new ArrayList<>();
		JSONArray chars = root.getJSONArray("chars");
		for (int i = 0; i < chars.length(); i++) {
			JSONObject c = chars.getJSONObject(i);
			int x = c.optInt("x", 0);
			int y = c.optInt("y", 0);
			int w = c.optInt("width", 0);
			int h = c.optInt("height", 0);
			frames.add(new SpriteSheet.Frame(
				x / scaleW, y / scaleH, (x + w) / scaleW, (y + h) / scaleH, w, h));
			glyphs.put(c.getInt("id"), new BitmapFont.Glyph(
				frames.size() - 1, w, h,
				c.optInt("xoffset", 0), c.optInt("yoffset", 0), c.optInt("xadvance", 0)));
		}

		Map<Integer, Float> kerning = new HashMap<>();
		JSONArray kernings = root.optJSONArray("kernings");
		if (kernings != null) {
			for (int i = 0; i < kernings.length(); i++) {
				JSONObject k = kernings.getJSONObject(i);
				int first = k.optInt("first", 0);
				int second = k.optInt("second", 0);
				if (first <= 0xffff && second <= 0xffff) {
					kerning.put((first << 16) | second, (float) k.optInt("amount", 0));
				}
			}
		}
		font.sheet.setFrames(frames.toArray(new SpriteSheet.Frame[0]));
		font.setGlyphs(glyphs);
		font.setKerning(kerning);

		JSONArray pages = root.optJSONArray("pages");
		return (pages != null && pages.length() > 0) ? pages.getString(0) : null;
	}

	/**
	 * On a module proxy, resolveUrl resolves against the MODULE's asset
	 * space, not the app's Resources — try the resolved location and fall
	 * back to the app's APK assets (same pattern as SoundProxy).
	 */
	private String readTextFile(String url) throws Exception
	{
		try {
			TiBaseFile file = TiFileFactory.createTitaniumFile(resolveUrl(null, url), false);
			try (InputStream in = file.getInputStream()) {
				return readStream(in);
			}
		} catch (Exception e) {
			try (InputStream in = TiApplication.getInstance().getAssets()
					.open("Resources/" + url)) {
				return readStream(in);
			}
		}
	}

	private static String readStream(InputStream in) throws Exception
	{
		BufferedReader reader = new BufferedReader(new InputStreamReader(in, "UTF-8"));
		StringBuilder sb = new StringBuilder();
		String line;
		while ((line = reader.readLine()) != null) {
			sb.append(line).append('\n');
		}
		return sb.toString();
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
			Log.e(LCAT, "Could not load font image: " + imagePath);
		}
		return bitmap;
	}

	@Kroll.getProperty
	public float getLineHeight()
	{
		return (font != null) ? font.lineHeight : 0f;
	}

	/** Frees the glyph texture on the next rendered frame. Permanent —
	 *  text sprites still using this font stop drawing. */
	@Kroll.method
	public void unload()
	{
		if (font != null && font.sheet != null) {
			font.sheet.dispose();
		}
	}

	@Override
	public void release()
	{
		unload();
		super.release();
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Font";
	}
}
