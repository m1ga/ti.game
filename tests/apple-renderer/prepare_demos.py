#!/usr/bin/env python3
"""Prepare an isolated Classic app that opens/renders/closes launcher demos.
Defaults to mobile demos; --include-input adds the external-input demo for Mac.
This is a smoke test; it does not certify human interaction or visual equivalence.
Build/run it with the Titanium CLI from the generated directory.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', default='/tmp/asteroids-metal-port/demos')
p.add_argument('--icon', type=Path, required=True, help='Existing DefaultIcon.png for the diagnostic app')
p.add_argument('--include-input', action='store_true', help='Include the Mac-only Configurable Input demo')
p.add_argument('--sdk', default='13.4.1.GA', help='Titanium SDK for the generated app (default: 13.4.1.GA)')
args = p.parse_args()
out = Path(args.output).resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep generated app outside the repository')
resources = out / 'Resources'
shutil.copytree(ROOT / 'example', resources, dirs_exist_ok=True)
shutil.copy2(args.icon, out / 'DefaultIcon.png')
manifest = (ROOT / 'ios/manifest').read_text()
version = re.search(r'^version:\s*(.+)$', manifest, re.M)[1]
with zipfile.ZipFile(ROOT / f'ios/dist/ti.game-iphone-{version}.zip') as archive:
    archive.extractall(out)
launcher = (ROOT / 'example/app.js').read_text()
names = re.findall(r"title: '[^']+', start: require\('/([^']+)'\)", launcher)
if not args.include_input:
    names = [name for name in names if name != 'inputmap']
if not names or len(names) != len(set(names)):
    p.error('Expected a nonempty launcher with unique demo modules')
for name in names:
    source = resources / (name + '.js')
    code = source.read_text()
    view = re.search(r'(?:var|const|let) (\w+) = Game.createGameView', code)[1]
    assert code.count('win.open();') == 1, name
    code = code.replace('win.open();', f"require('/metal-smoke').track(win, {view}, '{name}');\n\twin.open();")
    source.write_text(code)
(resources / 'app.js').write_text("require('/metal-smoke').run(" + json.dumps(names) + ');\n')
(resources / 'metal-smoke.js').write_text('''var names, index=0, results=[], root;
function save(){Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory,'metal-demos.json').write(JSON.stringify(results,null,2));}
function next(){
 if(index===names.length){save();Ti.API.info('METAL_SMOKE_COMPLETE '+JSON.stringify(results));return;}
 try{require('/'+names[index])();}catch(error){results.push({name:names[index],error:String(error)});index++;save();setTimeout(next,100);}
}
exports.run=function(list){names=list;root=Ti.UI.createWindow({backgroundColor:'#000'});root.open();setTimeout(next,300);};
exports.track=function(win,view,name){
 var done=false,timer;
 function finish(sample,error){
  if(done)return;done=true;clearTimeout(timer);
  var item={name:name,error:error||null,drawCalls:sample&&sample.drawCalls,fps:sample&&sample.fps,width:sample&&sample.surfaceWidth,height:sample&&sample.surfaceHeight};
  results.push(item);Ti.API.info('METAL_SMOKE '+JSON.stringify(item));save();
  // Exercise native pause/resume and normal view removal between scenes.
  view.pause();view.resume();
  win.close();index++;setTimeout(next,200);
 }
 timer=setTimeout(function(){finish(null,'no rendered performance sample within 10s');},10000);
 view.addEventListener('performance',function(sample){
  if(sample.drawCalls>0&&sample.surfaceWidth>0&&sample.surfaceHeight>0)finish(sample,null);
 });
};
''')
(out / 'tiapp.xml').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<ti:app xmlns:ti="http://ti.tidev.io">
 <id>mx.codigomovil.tigame.metaldemos</id><name>Metal Demos</name><version>1.0</version>
 <guid>79cf594d-7894-458d-8d6b-3a79d060fe76</guid><icon>appicon.png</icon>
 <property name="ti.ui.defaultunit" type="string">dp</property>
 <property name="run-on-main-thread" type="bool">true</property>
 <ios>
  <enable-launch-screen-storyboard>true</enable-launch-screen-storyboard>
  <plist><dict><key>UIApplicationSupportsIndirectInputEvents</key><true/></dict></plist>
 </ios>
 <modules><module platform="iphone" version="{version}">ti.game</module></modules>
 <deployment-targets><target device="iphone">true</target><target device="ipad">true</target></deployment-targets>
 <sdk-version>{args.sdk}</sdk-version>
</ti:app>''')
print(out)
