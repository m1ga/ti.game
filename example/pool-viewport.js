// Pool uses a portrait table; scale its scene and native reset control together.
// Only the outer view changes with the window. The running scene keeps its bounds,
// timers, collision geometry and drag state; resizing never restarts a demo.
module.exports = function (win) {
	var host = Ti.UI.createView({ width: Ti.UI.FILL, height: Ti.UI.FILL });
	var stage = Ti.UI.createView({ width: 380, height: 680 });
	var lastScale = 0;
	host.add(stage);
	win.add(host);
	function fit() {
		var bounds = host.rect;
		if (!(bounds.width > 0 && bounds.height > 0)) { return; }
		var scale = Math.min(bounds.width / 380, bounds.height / 680);
		if (Math.abs(scale - lastScale) < 0.0001) { return; }
		lastScale = scale;
		stage.transform = Ti.UI.createMatrix2D().scale(scale, scale);
	}
	host.addEventListener('postlayout', fit);
	win.addEventListener('close', function () {
		host.removeEventListener('postlayout', fit);
	});
	return stage;
};
