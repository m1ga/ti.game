// Optional shortcuts use native action transitions, never polling or global capture.
module.exports = function (win, view, actions) {
	var bindings = {};
	Object.keys(actions).forEach(function (name) {
		bindings[name] = actions[name].keys.map(function (code) {
			return { device: 'keyboard', code: code };
		});
		(actions[name].buttons || []).forEach(function (button) {
			bindings[name].push({ device: 'gamepad', button: button });
		});
	});
	view.inputMap = { gameplay: bindings };
	function down(e) {
		if (actions[e.action] && actions[e.action].down) { actions[e.action].down(); }
	}
	function up(e) {
		if (actions[e.action] && actions[e.action].up) { actions[e.action].up(); }
	}
	function focus() {
		view.inputContext = 'gameplay';
		view.focusInput();
	}
	function blur() { view.inputContext = null; }
	view.addEventListener('actiondown', down);
	view.addEventListener('actionup', up);
	win.addEventListener('open', focus);
	win.addEventListener('focus', focus);
	win.addEventListener('blur', blur);
	win.addEventListener('close', function () {
		blur();
		view.removeEventListener('actiondown', down);
		view.removeEventListener('actionup', up);
	});
	// resize may initialize a scene after Window.open has already fired.
	focus();
};
