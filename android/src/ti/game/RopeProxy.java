package ti.game;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.util.TiConvert;

import ti.game.engine.Rope;

/**
 * JS-facing Verlet rope:
 *
 *   var rope = Game.createRope({
 *       sheet: ropeSheet,
 *       segments: 12,
 *       segmentLength: 40,     // px
 *       thickness: 12,         // drawn width, px
 *       gravity: 1500, damping: 0.98, iterations: 3,
 *       head: ball,            // pin the head to a sprite (or set x/y)
 *       zIndex: 4
 *   });
 *   gameView.add(rope);
 *
 * Drag the head sprite (a normal draggable sprite) and the rope follows —
 * integration, constraints and drawing all run in the native game loop.
 * An optional `tail` sprite pins the other end (bridges). `endX`/`endY`
 * read the live position of the loose end.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class RopeProxy extends KrollProxy
{
	private final Rope rope = new Rope();
	private SpriteSheetProxy sheetProxy;
	private SpriteProxy headProxy;
	private SpriteProxy tailProxy;

	public Rope getRope()
	{
		return rope;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("sheet") && options.get("sheet") instanceof SpriteSheetProxy) {
			setSheet((SpriteSheetProxy) options.get("sheet"));
		}
		if (options.containsKey("head") && options.get("head") instanceof SpriteProxy) {
			setHead((SpriteProxy) options.get("head"));
		}
		if (options.containsKey("tail") && options.get("tail") instanceof SpriteProxy) {
			setTail((SpriteProxy) options.get("tail"));
		}
		if (options.containsKey("frame")) {
			rope.frame = TiConvert.toInt(options.get("frame"));
		}
		if (options.containsKey("segments")) {
			rope.segments = TiConvert.toInt(options.get("segments"));
		}
		if (options.containsKey("segmentLength")) {
			rope.segmentLength = TiConvert.toFloat(options.get("segmentLength"));
		}
		if (options.containsKey("thickness")) {
			rope.thickness = TiConvert.toFloat(options.get("thickness"));
		}
		if (options.containsKey("gravity")) {
			rope.gravity = TiConvert.toFloat(options.get("gravity"));
		}
		if (options.containsKey("damping")) {
			rope.damping = TiConvert.toFloat(options.get("damping"));
		}
		if (options.containsKey("iterations")) {
			rope.iterations = TiConvert.toInt(options.get("iterations"));
		}
		if (options.containsKey("zIndex")) {
			rope.zIndex = TiConvert.toInt(options.get("zIndex"));
		}
		if (options.containsKey("visible")) {
			rope.visible = TiConvert.toBoolean(options.get("visible"));
		}
		if (options.containsKey("x")) {
			rope.x = TiConvert.toFloat(options.get("x"));
		}
		if (options.containsKey("y")) {
			rope.y = TiConvert.toFloat(options.get("y"));
		}
	}

	// --- Sheet / anchors --------------------------------------------------

	@Kroll.setProperty
	public void setSheet(SpriteSheetProxy value)
	{
		sheetProxy = value;
		rope.sheet = (value != null) ? value.getSheet() : null;
	}

	@Kroll.getProperty
	public SpriteSheetProxy getSheet()
	{
		return sheetProxy;
	}

	/** Pin the head to this sprite (null = use the fixed x/y anchor). */
	@Kroll.setProperty
	public void setHead(SpriteProxy value)
	{
		headProxy = value;
		rope.head = (value != null) ? value.getSprite() : null;
	}

	@Kroll.getProperty
	public SpriteProxy getHead()
	{
		return headProxy;
	}

	/** Pin the loose end to this sprite too (bridges); null = free. */
	@Kroll.setProperty
	public void setTail(SpriteProxy value)
	{
		tailProxy = value;
		rope.tail = (value != null) ? value.getSprite() : null;
	}

	@Kroll.getProperty
	public SpriteProxy getTail()
	{
		return tailProxy;
	}

	// --- Configuration ----------------------------------------------------

	@Kroll.getProperty
	public int getFrame()
	{
		return rope.frame;
	}

	@Kroll.setProperty
	public void setFrame(int value)
	{
		rope.frame = value;
	}

	@Kroll.getProperty
	public int getSegments()
	{
		return rope.segments;
	}

	@Kroll.setProperty
	public void setSegments(int value)
	{
		rope.segments = value;
	}

	@Kroll.getProperty
	public float getSegmentLength()
	{
		return rope.segmentLength;
	}

	@Kroll.setProperty
	public void setSegmentLength(float value)
	{
		rope.segmentLength = value;
	}

	@Kroll.getProperty
	public float getThickness()
	{
		return rope.thickness;
	}

	@Kroll.setProperty
	public void setThickness(float value)
	{
		rope.thickness = value;
	}

	@Kroll.getProperty
	public float getGravity()
	{
		return rope.gravity;
	}

	@Kroll.setProperty
	public void setGravity(float value)
	{
		rope.gravity = value;
	}

	@Kroll.getProperty
	public float getDamping()
	{
		return rope.damping;
	}

	@Kroll.setProperty
	public void setDamping(float value)
	{
		rope.damping = value;
	}

	@Kroll.getProperty
	public int getIterations()
	{
		return rope.iterations;
	}

	@Kroll.setProperty
	public void setIterations(int value)
	{
		rope.iterations = value;
	}

	@Kroll.getProperty
	public int getZIndex()
	{
		return rope.zIndex;
	}

	@Kroll.setProperty
	public void setZIndex(int value)
	{
		rope.zIndex = value;
	}

	@Kroll.getProperty
	public boolean getVisible()
	{
		return rope.visible;
	}

	@Kroll.setProperty
	public void setVisible(boolean value)
	{
		rope.visible = value;
	}

	@Kroll.getProperty
	public float getX()
	{
		return rope.x;
	}

	@Kroll.setProperty
	public void setX(float value)
	{
		rope.x = value;
	}

	@Kroll.getProperty
	public float getY()
	{
		return rope.y;
	}

	@Kroll.setProperty
	public void setY(float value)
	{
		rope.y = value;
	}

	/** Live position of the loose end (read-only). */
	@Kroll.getProperty
	public float getEndX()
	{
		return rope.endX;
	}

	@Kroll.getProperty
	public float getEndY()
	{
		return rope.endY;
	}

	@Override
	public String getApiName()
	{
		return "ti.game.Rope";
	}
}
