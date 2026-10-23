const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const root = path.resolve(__dirname, '../../example');

function fixture(name, density = 2, width = 1920, height = 1048) {
 const windows = [], views = [], objects = [], timers = [];
 function object(props = {}) {
  const value = Object.assign({ children: [], events: {}, rect: {width:380,height:680}, frameCount:16 }, props);
  value.add = children => value.children.push(...(Array.isArray(children) ? children : [children]));
  value.addEventListener = (event, callback) => (value.events[event] ||= []).push(callback);
  value.removeEventListener = (event, callback) => value.events[event] = value.events[event].filter(item => item !== callback);
  value.emit = (event, data) => (value.events[event] || []).forEach(callback => callback(data));
  value.after = (ms, callback) => timers.push(callback);
  const proxy = new Proxy(value, { get(target, key) { return key in target ? target[key] : function () {}; } });
  objects.push(proxy);
  return proxy;
 }
 const Ti = { Platform: {osname:'iphone',displayCaps:{logicalDensityFactor:density,platformHeight:99999}}, UI: {
  FILL:'fill', createWindow(props) {const win=object(props); windows.push(win); return win;},
  createView(props) {const view=object(props);views.push(view);return view;},
  createLabel:object, createButton:object, createTextField:object,
  createMatrix2D: () => ({scale:(x,y)=>({x,y})})
 }};
 const Game = new Proxy({}, {get(target,key) {
  return props => {
   const value=object({...props, kind:key});
   if(key==='createTileLayer') {
    value.width=props.data[0].length*props.tileWidth; value.height=props.data.length*props.tileHeight;
    value.isBlocked=()=>false; value.cellAt=(col,row)=>({x:col*props.tileWidth,y:row*props.tileHeight});
   }
   return value;
  };
 }});
 function load(file) {
  const module={exports:{}};
  vm.runInNewContext(fs.readFileSync(path.join(root,file+'.js'),'utf8'), {
   module,exports:module.exports,Ti, require(id) { if(id==='ti.game')return Game;if(id==='/backnav')return name==='inputmap'?load('backnav'):()=>{};return load(id.slice(1));},
   setTimeout:()=>0,clearTimeout:()=>{},setInterval:()=>0,clearInterval:()=>{},Math,Date,console
  }, {filename:file+'.js'});
  return module.exports;
 }
 load(name)();
 const view=objects.find(item=>item.kind==='createGameView');
 const host=views[0], stage=views[1];
 if(host) {host.rect={width,height};host.emit('postlayout');}
 view.rect={width:stage?380:width,height:stage?680:height};
 const surface={width:view.rect.width*density,height:view.rect.height*density};
 view.emit('resize',surface);
 return {objects,view,host,stage,surface,windows,timers};
}

test('keyboard shortcuts invoke existing demo actions and release listeners on close', () => {
 const names=['flappy','flip','skate','plinko','pool','drum','circles','slopes','zones','text','tilemap','wind','particles','blend','rhythm','swept','camera','timescale','platformer','volley'];
 for(const name of names) {
  const f=fixture(name);
  assert.ok(Object.keys(f.view.inputMap.gameplay).length, name);
  for(const action of Object.keys(f.view.inputMap.gameplay)) {
   f.view.emit('actiondown',{action}); f.view.emit('actionup',{action});
  }
  f.windows[0].emit('blur'); assert.equal(f.view.inputContext,null,name);
  f.windows[0].emit('focus'); assert.equal(f.view.inputContext,'gameplay',name);
  f.windows[0].emit('close'); assert.equal(f.view.inputContext,null,name);
  assert.equal(f.view.events.actiondown.length,0,name);
  assert.equal(f.view.events.actionup.length,0,name);
 }
});

test('keyboard directions restore the held direction and do not release a held touch control', () => {
 for(const name of ['platformer','volley']) {
  const f=fixture(name); const player=f.objects.find(s=>s.kind==='createSprite'&&s.sheet?.image==='assets/player.png');
  const left=f.objects.find(s=>s.text==='◀');
  left.emit('touchstart'); assert.ok(player.velocityX<0,name);
  f.view.emit('actiondown',{action:'right'}); assert.equal(player.velocityX,0,name);
  f.view.emit('actionup',{action:'right'}); assert.ok(player.velocityX<0,name);
  left.emit('touchend'); assert.equal(player.velocityX,0,name);
  f.view.emit('actiondown',{action:'left'}); f.view.emit('actiondown',{action:'right'});
  assert.equal(player.velocityX,0,name);
  f.view.emit('actionup',{action:'right'}); assert.ok(player.velocityX<0,name);
  f.view.emit('actionup',{action:'left'}); assert.equal(player.velocityX,0,name);
  assert.ok(f.view.inputMap.gameplay.jump.some(b=>b.device==='gamepad'&&b.button==='a'));
  assert.equal((f.view.events.buttondown||[]).length,0,'one route for mapped gamepad actions');
 }
});

test('Plinko keyboard drops ten chips and text keyboard scores then resets', () => {
 const p=fixture('plinko');const before=p.objects.filter(s=>s.collisionGroup==='chip').length;
 p.view.emit('actiondown',{action:'ten'});
 assert.equal(p.objects.filter(s=>s.collisionGroup==='chip').length,before+10);
 const t=fixture('text');t.view.emit('actiondown',{action:'score'});
 assert.ok(t.objects.some(s=>s.text==='SCORE 10'));
 t.view.emit('actiondown',{action:'reset'});assert.ok(t.objects.some(s=>s.text==='SCORE 0'));
});

test('Configurable input keeps instructions visible while its character moves and fires', () => {
 const f=fixture('inputmap');
 const instructions=f.objects.find(s=>typeof s.text==='string'&&s.text.includes('A/D')&&s.text.includes('JUMP'));
 assert.ok(instructions);const copy=instructions.text;
 const player=f.objects.find(s=>s.kind==='createSprite'&&s.sheet?.image==='assets/player.png');
 assert.ok(player,'show an existing animated character');
 f.view.emit('actiondown',{action:'left'});assert.ok(player.velocityX<0);
 f.view.emit('actiondown',{action:'right'});assert.ok(player.velocityX>0,'last direction wins while both are held');
 f.view.emit('actionup',{action:'right'});assert.ok(player.velocityX<0);
 f.view.emit('actionup',{action:'left'});assert.equal(player.velocityX,0);
 f.view.emit('actiondown',{action:'right'});f.view.emit('actiondown',{action:'left'});assert.ok(player.velocityX<0);
 f.view.emit('actionup',{action:'left'});assert.ok(player.velocityX>0,'resume the still-held direction');
 f.view.emit('actionup',{action:'right'});assert.equal(player.velocityX,0);
 f.view.emit('actiondown',{action:'left'});f.view.emit('actionup',{action:'left'});
 f.view.emit('actiondown',{action:'fire'});
 assert.ok(f.objects.some(s=>s.collisionGroup==='input-shot'&&s.velocityX<0));
 assert.equal(instructions.text,copy,'input feedback must never replace the instructions');
 f.windows[0].emit('blur');assert.equal(player.velocityX,0);assert.equal(f.view.inputContext,null);
 f.windows[0].emit('focus');assert.equal(f.view.inputContext,'gameplay');
 const typing=f.objects.find(s=>s.hintText==='Type here');
 f.view.emit('actiondown',{action:'right'});typing.emit('focus');
 assert.equal(player.velocityX,0);assert.equal(f.view.inputContext,null);
 f.windows[0].emit('focus');assert.equal(f.view.inputContext,null,'do not steal text field focus');
 f.view.emit('tap');assert.equal(f.view.inputContext,'gameplay','a canvas click restores input after typing');
 typing.emit('focus');assert.equal(f.view.inputContext,null);
 f.objects.find(s=>s.title==='Focus canvas').emit('click');assert.equal(f.view.inputContext,'gameplay');
 assert.equal(instructions.text,copy);
 const count=f.view.children.length;
 f.view.emit('resize',{width:780,height:1688});assert.equal(f.view.children.length,count,'resize reuses the scene');
 f.windows[0].emit('close');
});

test('Configurable input jumps once from the ground and separates jump from fire', () => {
 const f=fixture('inputmap');
 const player=f.objects.find(s=>s.kind==='createSprite'&&s.sheet?.image==='assets/player.png');
 const jump=f.view.inputMap.gameplay.jump;
 assert.ok(jump,'provide a jump action');
 assert.ok(jump.some(b=>b.code==='Space'));
 for(const code of ['KeyW','KeyI','ArrowUp']) assert.ok(!jump.some(b=>b.code===code));
 assert.ok(jump.some(b=>b.device==='gamepad'&&b.button==='a'));
 assert.ok(f.view.inputMap.gameplay.fire.some(b=>b.device==='mouse'&&b.button==='left'));
 assert.ok(!f.view.inputMap.gameplay.fire.some(b=>b.device==='keyboard'),'mouse fire has no arbitrary keyboard default');
 assert.ok(!f.view.inputMap.gameplay.fire.some(b=>b.code==='Space'));
 assert.ok(player.solidWith.includes('input-ground'));
 player.onGround=true;
 f.view.emit('actiondown',{action:'jump'});assert.ok(player.velocityY<0);
 player.onGround=false;player.velocityY=27;
 f.view.emit('actiondown',{action:'jump'});assert.equal(player.velocityY,27,'no double jump in midair');
 f.view.emit('actiondown',{action:'right'});assert.ok(player.velocityX>0);
 assert.equal(player.velocityY,27,'horizontal controls preserve the native jump');
 player.onGround=true;player.velocityY=0;player.emit('land',{group:'input-ground'});
 assert.ok(player.velocityX>0,'landing preserves held movement');
});

test('Configurable input pauses by context and displays raw input without replacing help', () => {
 const f=fixture('inputmap');const v=f.view;
 const help=f.objects.find(s=>typeof s.text==='string'&&s.text.includes('A/D')&&s.text.includes('JUMP'));
 const copy=help.text;
 v.emit('actiondown',{action:'pause'});assert.equal(v.timeScale,0);assert.equal(v.inputContext,'paused');
 assert.ok(v.inputMap.paused.pause.some(b=>b.code==='Escape'));
 v.emit('actionup',{action:'pause'});assert.ok(f.objects.some(s=>typeof s.text==='string'&&s.text.startsWith('PAUSED')));
 v.emit('actiondown',{action:'pause'});assert.equal(v.timeScale,1);assert.equal(v.inputContext,'gameplay');
 v.emit('keydown',{code:'KeyA',modifiers:{shift:true,control:true,alt:false,meta:false}});
 assert.ok(f.objects.some(s=>typeof s.text==='string'&&s.text.includes('Control+Shift+KeyA')));
 v.emit('stick',{stick:'right',x:0.5,y:-0.25,gamepad:1});
 assert.ok(f.objects.some(s=>typeof s.text==='string'&&s.text.includes('right stick 0.50, -0.25')));
 for(const button of ['right','middle']) assert.ok(Object.values(v.inputMap.gameplay).some(bindings=>bindings.some(b=>b.device==='mouse'&&b.button===button)));
 assert.equal(help.text,copy);
 assert.ok(!f.objects.some(s=>s.title==='Close'),'use the shared back control');
 const back=f.objects.find(s=>s.text==='‹  EXAMPLES');assert.ok(back);assert.equal(back.left,12);
});


test('Configurable input aims diagonally at constant shot speed and crouches without moving its feet', () => {
 const f=fixture('inputmap');const v=f.view;
 const player=f.objects.find(s=>s.kind==='createSprite'&&s.sheet?.image==='assets/player.png');
 for(const code of ['KeyW','KeyI','ArrowUp']) assert.ok(v.inputMap.gameplay.aimUp.some(b=>b.code===code));
 for(const code of ['KeyS','KeyK','ArrowDown']) assert.ok(v.inputMap.gameplay.crouch.some(b=>b.code===code));
 const size=player.height,feet=player.y+size/2;
 v.emit('actiondown',{action:'crouch'});assert.ok(player.height<size);assert.equal(player.y+player.height/2,feet);
 v.emit('actionup',{action:'crouch'});assert.equal(player.height,size);assert.equal(player.y+player.height/2,feet);
 v.emit('actiondown',{action:'aimUp'});v.emit('actiondown',{action:'fire'});
 let shot=f.objects.filter(s=>s.collisionGroup==='input-shot').at(-1);assert.equal(shot.velocityX,0);assert.ok(shot.velocityY<0);
 const speed=Math.hypot(shot.velocityX,shot.velocityY);
 for(const direction of ['left','right']) {
  v.emit('actiondown',{action:direction});v.emit('actiondown',{action:'fire'});
  shot=f.objects.filter(s=>s.collisionGroup==='input-shot').at(-1);
  assert.ok(direction==='left'?shot.velocityX<0:shot.velocityX>0);assert.ok(shot.velocityY<0);
  assert.ok(Math.abs(Math.hypot(shot.velocityX,shot.velocityY)-speed)<0.001);
  v.emit('actionup',{action:direction});
 }
 f.windows[0].emit('blur');v.emit('actiondown',{action:'fire'});
 shot=f.objects.filter(s=>s.collisionGroup==='input-shot').at(-1);assert.equal(shot.velocityY,0,'focus loss clears aiming');
});
