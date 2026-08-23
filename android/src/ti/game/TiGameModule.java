/**
 * ti.game — 2D sprite game engine module for Titanium SDK (Android).
 *
 * Architecture: the entire game loop is native. JS is a scene-description
 * and event API — create sprites, configure animations, enable behaviors
 * (draggable/pinchable/rotatable) and receive high-level events. The Kroll
 * bridge is never crossed per frame.
 *
 *   var Game = require('ti.game');
 *   var view = Game.createGameView({ backgroundColor: '#202030' });
 *   var sheet = Game.createSpriteSheet({ image: 'hero.png', frameWidth: 64, frameHeight: 64 });
 *   var hero = Game.createSprite({ sheet: sheet, x: 100, y: 200, draggable: true });
 *   view.add(hero);
 */
package ti.game;

import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiApplication;

import ti.game.engine.Easing;

@Kroll.module(name = "TiGame", id = "ti.game")
public class TiGameModule extends KrollModule
{
	// Easing constants for sprite.animate({ easing: Game.EASE_OUT, ... })
	@Kroll.constant public static final String EASE_LINEAR = Easing.LINEAR;
	@Kroll.constant public static final String EASE_IN = Easing.EASE_IN;
	@Kroll.constant public static final String EASE_OUT = Easing.EASE_OUT;
	@Kroll.constant public static final String EASE_IN_OUT = Easing.EASE_IN_OUT;
	@Kroll.constant public static final String EASE_BOUNCE = Easing.BOUNCE;
	@Kroll.constant public static final String EASE_ELASTIC = Easing.ELASTIC;

	public TiGameModule()
	{
		super();
		TiGameView.beginRuntimeGeneration();
	}

	@Kroll.onAppCreate
	public static void onAppCreate(TiApplication app)
	{
	}
}
