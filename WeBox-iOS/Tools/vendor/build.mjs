import {build} from 'esbuild';
import fs from 'node:fs';import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..');
for(const [name,contents] of Object.entries({'cheerio':"globalThis.cheerio={load:require('cheerio/lib/slim').load};",'cryptojs':"globalThis.__compatCryptoJS=require('crypto-js');"})){
 await build({stdin:{contents,resolveDir:import.meta.dirname},bundle:true,platform:'browser',format:'iife',minify:true,legalComments:'eof',outfile:path.join(root,'Resources',`sdk-${name}.js`)});
}
const names=['cheerio','cheerio-select','boolbase','css-select','css-what','domhandler','domutils','dom-serializer','domelementtype','entities','htmlparser2','nth-check','crypto-js'];
let notices='WeBox SDK (widget.js / webox.js / xptv.js / compute-worker.js)\nExtracted unchanged from the user-supplied WeBox 0.1.101 beta APK, revision ea064604. The APK includes GPL-3.0; the same license is included with this app. These files implement a host protocol, not a bundled content source.\n\n';
for(const name of names){const dir=path.join(import.meta.dirname,'node_modules',name);const pkg=JSON.parse(fs.readFileSync(path.join(dir,'package.json'),'utf8'));const license=fs.readdirSync(dir).find(n=>/^licen[cs]e(?:\.md|\.txt)?$/i.test(n));notices+=`${name} ${pkg.version} (${pkg.license})\n${license?fs.readFileSync(path.join(dir,license),'utf8'):'See '+pkg.repository?.url}\n\n`;}
fs.writeFileSync(path.join(root,'Resources/licenses/THIRD_PARTY.txt'),notices);
console.log('Rebuilt browser libraries and license notices.');
