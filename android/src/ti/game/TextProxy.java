package ti.game;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.util.TiConvert;

import ti.game.engine.TextSprite;

/**
 * JS-facing text sprite: createText({ font: font, text: 'SCORE 0' }).
 *
 * Extends SpriteProxy, so text carries the whole sprite API — position,
 * anchor, scale, tint, zIndex/ySort, tweens, idle wobble, flash, touch
 * events, screenFixed — and renders inside the GL scene (one quad per
 * glyph, a single batch run). Setting `text` re-lays out natively; omit
 * `font` to use the built-in pixel font.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class TextProxy extends SpriteProxy
{
	private final TextSprite textSprite;
	private FontProxy fontProxy;

	public TextProxy()
	{
		super(new TextSprite());
		textSprite = (TextSprite) sprite;
		// No explicit font: the scene assigns its own default-font
		// instance when the sprite is added to a game view.
		textSprite.usesDefaultFont = true;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("font")) {
			Object value = options.get("font");
			if (value instanceof FontProxy) {
				setFont((FontProxy) value);
			}
		}
		if (options.containsKey("text")) {
			textSprite.setText(TiConvert.toString(options.get("text"), ""));
		}
		if (options.containsKey("align")) {
			setAlign(TiConvert.toString(options.get("align")));
		}
		if (options.containsKey("letterSpacing")) {
			textSprite.setLetterSpacing(
				TiConvert.toFloat(options.get("letterSpacing"), textSprite.letterSpacing()));
		}
		if (options.containsKey("lineSpacing")) {
			textSprite.setLineSpacing(
				TiConvert.toFloat(options.get("lineSpacing"), textSprite.lineSpacing()));
		}
		if (options.containsKey("maxWidth")) {
			textSprite.setMaxWidth(TiConvert.toFloat(options.get("maxWidth"), 0f));
		}
	}

	@Kroll.setProperty
	public void setFont(FontProxy value)
	{
		fontProxy = value;
		boolean explicit = (value != null && value.getFont() != null);
		textSprite.usesDefaultFont = !explicit;
		textSprite.setFont(explicit ? value.getFont() : null);
		if (!explicit && textSprite.scene != null) {
			textSprite.scene.resolveTextFont(textSprite); // back to the scene's default font
		}
	}

	@Kroll.getProperty
	public FontProxy getFont()
	{
		return fontProxy;
	}

	@Kroll.setProperty
	public void setText(String value)
	{
		textSprite.setText(value);
	}

	@Kroll.getProperty
	public String getText()
	{
		return textSprite.text();
	}

	/** 'left' (default), 'center' or 'right' — how multi-line text lines up. */
	@Kroll.setProperty
	public void setAlign(String value)
	{
		if ("center".equals(value)) {
			textSprite.setAlign(TextSprite.ALIGN_CENTER);
		} else if ("right".equals(value)) {
			textSprite.setAlign(TextSprite.ALIGN_RIGHT);
		} else {
			textSprite.setAlign(TextSprite.ALIGN_LEFT);
		}
	}

	@Kroll.getProperty
	public String getAlign()
	{
		switch (textSprite.align()) {
			case TextSprite.ALIGN_CENTER:
				return "center";
			case TextSprite.ALIGN_RIGHT:
				return "right";
			default:
				return "left";
		}
	}

	/** Extra px between glyphs (negative tightens). */
	@Kroll.setProperty
	public void setLetterSpacing(float value)
	{
		textSprite.setLetterSpacing(value);
	}

	@Kroll.getProperty
	public float getLetterSpacing()
	{
		return textSprite.letterSpacing();
	}

	/** Multiplier on the font's line height (1 = default leading). */
	@Kroll.setProperty
	public void setLineSpacing(float value)
	{
		textSprite.setLineSpacing(value);
	}

	@Kroll.getProperty
	public float getLineSpacing()
	{
		return textSprite.lineSpacing();
	}

	/** Wrap width in px — lines break on word boundaries (0 = no wrap). */
	@Kroll.setProperty
	public void setMaxWidth(float value)
	{
		textSprite.setMaxWidth(value);
	}

	@Kroll.getProperty
	public float getMaxWidth()
	{
		return textSprite.maxWidth();
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Text";
	}
}
