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

test('resize fits scene and native overlays without changing running scene bounds',()=>{
 const f=fixture('pool'); const state=f.view.children.slice();
 for(const [width,height] of [[320,480],[390,844],[768,1024],[1024,768],[1366,1024],[1920,1048],[2560,1080],[640,1600]]) {
  f.host.rect={width,height}; f.host.emit('postlayout');
  const scale=f.stage.transform;
  assert.equal(scale.x,scale.y);
  assert.ok(f.stage.width*scale.x <= width+0.001);
  assert.ok(f.stage.height*scale.y <= height+0.001);
  assert.equal(f.stage.width,380);assert.equal(f.stage.height,680);
  assert.deepEqual(f.view.children,state,'resizing must preserve balls and game state');
 }
 f.windows[0].emit('close'); assert.equal(f.host.events.postlayout.length,0);
});

test('Plinko has a continuous chip-sized gap through every staggered peg row',()=>{
 for(const [width,height] of [[320,480],[390,844],[768,1024],[1920,1048],[2560,1080],[640,1600]]) {
 const f=fixture('plinko',2,width,height);f.timers[0]();
 const pegs=f.objects.filter(item=>item.collisionGroup==='peg'&&item.hitboxShape==='circle');
 const chip=f.objects.find(item=>item.collisionGroup==='chip');
 assert.equal(pegs.length,86);assert.ok(chip);
 assert.ok(pegs[0].width/2<=20.000001,'pins stay at most 20 view points wide');
 const authoredPeg=Math.max(5,Math.round(f.surface.width*.92/9*.28));
 const authoredChip=Math.max(9,Math.round(f.surface.width*.92/9*.46));
 assert.ok(Math.abs(chip.width/pegs[0].width-authoredChip/authoredPeg)<.001,'keep the mobile chip/pin proportions');
 if(width===390&&height===844){assert.equal(pegs[0].width,authoredPeg);assert.equal(chip.width,authoredChip);}
 for(let a=0;a<pegs.length;a++)for(let b=a+1;b<pegs.length;b++) {
  const p=pegs[a],q=pegs[b];
  const gap=Math.hypot(p.x-q.x,p.y-q.y)-(p.width+q.width)*0.9/2;
  assert.ok(gap > chip.width*0.9,`a chip must fit at ${width}x${height}`);
 }
 }
});

test('all sixteen Pool balls start within the vertical felt, with cue below rack',()=>{
 const f=fixture('pool');const {width:W,height:H}=f.surface;
 const balls=f.objects.filter(item=>item.collisionGroup==='ball');assert.equal(balls.length,16);
 const rail=Math.max(12,Math.round(W*.035)),margin=Math.max(12,Math.round(W*.045));
 for(const ball of balls){const r=ball.width*.9/2;assert.ok(ball.x-r>=margin+rail&&ball.x+r<=W-margin-rail);assert.ok(ball.y-r>=H*.19+rail&&ball.y+r<=H*.84-rail);}
 assert.ok(balls[0].y > Math.max(...balls.slice(1).map(ball=>ball.y)));
});

test('Tile Map keeps a readable walker scale and moves HUD after window resizing',()=>{
 for(const density of [1,2,3]){
  const f=fixture('tilemap',density);const walker=f.objects.find(item=>item.solidWith?.includes?.('water'));
  assert.equal(walker.width/density,32);
  const before=f.view.children.length;
  f.view.emit('resize',{width:640*density,height:900*density});
  assert.equal(f.view.children.length,before,'do not recreate the map on resize');
  const title=f.objects.find(item=>item.text==='120 x 90 TILES - ONE LAYER');assert.equal(title.x,320*density);
 }
});

test('all launcher demos use the full canvas except the portrait Pool table',()=>{
 const launcher=fs.readFileSync(path.join(root,'app.js'),'utf8');
 const names=Array.from(launcher.matchAll(/start: require\('\/([^']+)'\)/g),match=>match[1]).filter(name=>name!=='inputmap');
 assert.equal(names.length,34);
 for(const name of names)for(const [width,height] of [[320,480],[390,844],[768,1024],[1920,1048],[2560,1080],[640,1600]]){
  const f=fixture(name,2,width,height);
  for(const item of f.view.children){
   for(const key of ['x','y','width','height']){
    if(typeof item[key]==='number')assert.ok(Number.isFinite(item[key]),`${name}: invalid ${key}`);
   }
  }
  assert.equal(Boolean(f.stage),name==='pool',`${name}: only Pool needs a portrait stage`);
 }
});

test('Text instructions fit while the ball moves inside its camera dead zone',()=>{
 for(const [width,height] of [[390,844],[1920,1048],[2560,720]]){
 const f=fixture('text',2,width,height);
 const block=f.objects.find(item=>typeof item.text==='string'&&item.text.startsWith('DRAG THE BALL'));
 const tag=f.objects.find(item=>item.text==='THE BALL');
 const ball=f.objects.find(item=>item.kind==='createSprite'&&item.draggable);
 const title=f.objects.find(item=>item.text==='TEXT DEMO');
 // Reserve vertical space for the three instruction lines, tag and ball.
 const blockBottom=block.y+3*12*block.lineSpacing*block.scale/2;
 assert.ok(blockBottom<ball.y-Math.min(f.surface.width,f.surface.height)*.09-6*tag.scale,'instructions must clear the attached tag');
 assert.ok(ball.width<=f.surface.height*.14,'ball must fit a short window');
 assert.ok(title.scale*12<f.surface.height*.08,'title must fit its top margin');
 const displayedWidth=block.maxWidth*block.scale;
 assert.ok(Number.isFinite(displayedWidth));
 for(const center of [.35,.5,.65]){
  assert.ok(center*f.surface.width-displayedWidth/2>=0);
  assert.ok(center*f.surface.width+displayedWidth/2<=f.surface.width);
 }
 }
});


test('Platformer reserves the native control area using canvas density',()=>{
 for(const density of [1,2,3])for(const [width,height] of [[390,844],[1920,1048]]){
  const f=fixture('platformer',density,width,height);
  const floor=f.view.children.find(item=>item.collisionGroup==='solid'&&item.width===f.surface.width);
  assert.equal(floor.height,130*density);
 }
});

test('Maze leaves room for both HUD labels above and below its tiles',()=>{
 for(const [width,height] of [[320,480],[768,1024],[1920,1048],[2560,1080]]){
  const f=fixture('maze',2,width,height);
  const title=f.objects.find(item=>item.text==='TAP A TILE - A* FINDS THE WAY');
  const score=f.objects.find(item=>item.text==='CAUGHT 0');
  assert.ok(title.y-title.scale*8>0);
  assert.ok(score.y+score.scale*8<f.surface.height);
 }
});

test('foreground art fits its vertical space in wide windows',()=>{
 for(const [width,height] of [[390,844],[1920,1048],[2560,1080]]){
  const basic=fixture('basic',2,width,height);
  const ghost=basic.view.children.find(item=>item.opacity===0.6);
  assert.ok(ghost.y-ghost.height/2>=0,'Basic ghost must stay above the top edge');
  const blend=fixture('blend',2,width,height);
  const spark=blend.view.children.find(item=>item.sheet?.image==='assets/spark.png'&&item.blend==='normal');
  assert.ok(spark.height<=blend.surface.height*.16,'blend rows must not cover neighboring rows');
  const point=fixture('pointclick',2,width,height);
  const tree=point.view.children.find(item=>item.sheet?.image==='assets/oak.png'&&item.opacity!==0);
  assert.ok(tree.y-tree.height/2>=0,'adventure tree must fit above its trunk base');
  const rhythm=fixture('rhythm',2,width,height);
  const pad=rhythm.view.children.find(item=>item.sheet?.image==='assets/pad.png');
  assert.ok(pad.y+pad.height/2<=rhythm.surface.height,'rhythm pads must fit below the hit line');
 }
});

test('actors and clocks remain inside short wide scenes',()=>{
 const width=2560,height=720;
 for(const name of ['flip','hitbox','rope','worldwrap']){
  const f=fixture(name,2,width,height);
  const actors=f.view.children.filter(item=>item.kind==='createSprite'&&(typeof item.animations==='object'||item.draggable===true));
  for(const actor of actors){
   if(actor.visible===false)continue;
   assert.ok(actor.y-actor.height/2>=0,`${name}: actor crosses the top of the canvas`);
  }
 }
 const f=fixture('timescale',2,width,height);
 const ball=f.view.children.find(item=>item.solidWith?.includes?.('floor'));
 const clock=f.objects.find(item=>item.text==='REAL 0s');
 assert.ok(ball.y-ball.height/2>clock.y+clock.scale*8,'the bouncing ball must clear the clocks at its initial apex');
});

test('Bingo Drum preserves ball, launcher and impulse proportions across viewports',()=>{
 for(const [width,height] of [[390,844],[768,1024],[1920,1048],[2560,1080]]){
  const f=fixture('drum',2,width,height);
  const drum=f.view.children.find(item=>item.collisionGroup==='drum');
  const ball=f.view.children.find(item=>item.collisionGroup==='ball');
  const launcher=f.view.children.find(item=>item.collisionGroup==='drum-launcher');
  const diameter=drum.width/.88;
  assert.ok(Math.abs(ball.width/diameter-.095)<1/diameter);
  assert.equal(launcher.width,ball.width*.9);
  ball.velocityX=0;ball.velocityY=0;
  ball.emit('collision',{group:'drum-launcher'});
  assert.ok(ball.velocityY/diameter>=-3.600001&&ball.velocityY/diameter<=-3);
  const kicked=ball.velocityY;
  ball.emit('collision',{group:'drum-launcher'});
  assert.equal(ball.velocityY,kicked,'a sustained contact must not repeatedly add impulses');
 }
});

test('Path ship and Raycast actors fit a short wide canvas',()=>{
 const pathScene=fixture('path',2,2560,720);
 const ship=pathScene.view.children.find(item=>item.sheet?.image==='assets/ship.png');
 assert.ok(ship.height/2<=pathScene.surface.height*.06+1,'ship must fit at the top of its path');
 const ray=fixture('raycast',2,2560,720);
 const turret=ray.view.children.find(item=>item.sheet?.image==='assets/ship.png');
 assert.ok(turret.y+turret.height/2<=ray.surface.height,'turret must fit at the bottom');
 const walker=ray.view.children.find(item=>item.sheet?.image==='assets/walker.png');
 const platform=ray.view.children.find(item=>item.collisionGroup==='ground');
 assert.ok(Math.abs(walker.y+walker.height/2-(platform.y-platform.height/2))<=1,'ledge probe walker starts at the platform surface');
});
