// Digital keyboard, canvas mouse and gamepad bindings share native action edges.
exports = module.exports = function () {
 var Game = require('ti.game');
 var win = Ti.UI.createWindow({ backgroundColor: '#101820' });
 var view = Game.createGameView({ inputMap: { gameplay: {
  left: [{ device: 'keyboard', code: 'KeyA' }, { device: 'keyboard', code: 'ArrowLeft' }, { device: 'gamepad', button: 'left' }],
  right: [{ device: 'keyboard', code: 'KeyD' }, { device: 'keyboard', code: 'ArrowRight' }, { device: 'gamepad', button: 'right' }],
  fire: [{ device: 'keyboard', code: 'Space' }, { device: 'mouse', button: 'left' }, { device: 'gamepad', button: 'a' }]
 } } });
 var status = Ti.UI.createLabel({ top: 30, color: '#fff', text: 'A/D or arrows; Space, canvas click or gamepad A' });
 var typing = Ti.UI.createTextField({ bottom: 80, width: '80%', height: 44, hintText: 'Typing here keeps native keyboard focus', backgroundColor: '#fff' });
 var focus = Ti.UI.createButton({ bottom: 20, title: 'Focus game canvas' });
 var close = Ti.UI.createButton({ top: 80, title: 'Close' });
 view.addEventListener('actiondown', function (e) { status.text = e.action + ' down'; });
 view.addEventListener('actionup', function (e) { status.text = e.action + ' up'; });
 focus.addEventListener('click', function () { typing.blur(); view.focusInput(); });
 close.addEventListener('click', function () { win.close(); });
 win.add(view); win.add(status); win.add(typing); win.add(focus); win.add(close);
 win.addEventListener('open', function () { view.focusInput(); });
 win.addEventListener('close', function () { view.inputContext = null; });
 win.open();
};
