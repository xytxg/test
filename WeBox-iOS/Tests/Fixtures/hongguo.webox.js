// SPDX-License-Identifier: GPL-3.0-only
// Protocol adapted from zfdang/hongguo-open-player commit 48f956f4f0220163e1e520d3f1bd38aab590c201.
// v5 signing originates from N3urda/hongguoTV and drpys; see 红果接入说明.md.
(function(){
let activeCtx=null,currentIdentity=null,loaded=null;
function uint64(value){return value & 0xffffffffffffffffn;}
class Bytes extends Uint8Array {
 static alloc(n,fill=0){return new Bytes(n).fill(fill);}
 static isBuffer(x){return x instanceof Bytes;}
 static from(x,enc='utf8'){
  if(typeof x!=='string')return new Bytes(x);
  if(enc==='hex'){if(x.length%2||!/^[0-9a-f]*$/i.test(x))throw Error('invalid hex');return new Bytes(x.match(/../g)?.map(v=>parseInt(v,16))||[]);}
  if(enc==='base64'||enc==='base64url'){const s=atob(x.replace(/-/g,'+').replace(/_/g,'/'));return new Bytes(Array.from(s,c=>c.charCodeAt(0)));}
  const s=enc==='utf8'||enc==='utf-8'?unescape(encodeURIComponent(x)):x;return new Bytes(Array.from(s,c=>c.charCodeAt(0)&255));
 }
 static concat(parts){const out=new Bytes(parts.reduce((n,p)=>n+p.length,0));let at=0;for(const p of parts){out.set(p,at);at+=p.length;}return out;}
 toString(enc='utf8',start=0,end=this.length){const b=this.subarray(start,end);if(enc==='hex')return Array.from(b,v=>v.toString(16).padStart(2,'0')).join('');let s='';for(let i=0;i<b.length;i+=8192)s+=String.fromCharCode(...b.subarray(i,i+8192));if(enc==='base64'||enc==='base64url'){s=btoa(s);return enc==='base64url'?s.replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''):s;}return enc==='utf8'||enc==='utf-8'?decodeURIComponent(escape(s)):s;}
 copy(out,at=0,start=0,end=this.length){const b=this.subarray(start,Math.min(end,start+out.length-at));out.set(b,at);return b.length;}
 write(s,at=0,length,enc='utf8'){if(typeof length==='string'){enc=length;length=undefined;}const b=Bytes.from(s,enc).subarray(0,length);this.set(b,at);return b.length;}
 view(){return new DataView(this.buffer,this.byteOffset,this.byteLength);}
 readUInt32BE(i=0){return this.view().getUint32(i);} readUInt32LE(i=0){return this.view().getUint32(i,true);}
 readInt32LE(i=0){return this.view().getInt32(i,true);} readUInt16BE(i=0){return this.view().getUint16(i);}
 writeFloatLE(v,i=0){this.view().setFloat32(i,v,true);return i+4;}
 writeUInt32BE(v,i=0){this.view().setUint32(i,v);return i+4;} writeUInt32LE(v,i=0){this.view().setUint32(i,v,true);return i+4;}
 readBigUInt64BE(i=0){return (BigInt(this.readUInt32BE(i))<<32n)|BigInt(this.readUInt32BE(i+4));}
 readBigUInt64LE(i=0){return (BigInt(this.readUInt32LE(i+4))<<32n)|BigInt(this.readUInt32LE(i));}
 writeBigUInt64BE(v,i=0){this.writeUInt32BE(Number(v>>32n),i);this.writeUInt32BE(Number(v&0xffffffffn),i+4);return i+8;}
 writeBigUInt64LE(v,i=0){this.writeUInt32LE(Number(v&0xffffffffn),i);this.writeUInt32LE(Number(v>>32n),i+4);return i+8;}
}
const Buffer=Bytes;
function cryptoAdapter(){return {
 randomBytes:n=>{const b=new Bytes(n);crypto.getRandomValues(b);return b;},
 randomUUID:()=>{const b=new Bytes(16);crypto.getRandomValues(b);b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=b.toString('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;},
 createHash:algorithm=>{const parts=[];return {update(b){parts.push(typeof b==='string'?Buffer.from(b):b);return this;},digest(enc){const b=Buffer.from(activeCtx.crypto.hash(algorithm,Buffer.concat(parts).toString('base64'),{inputEncoding:'base64',outputEncoding:'base64'}),'base64');return enc?b.toString(enc):b;}};},
 createCipheriv:(algorithm,key,iv)=>cipherAdapter(false,algorithm,key,iv),createDecipheriv:(algorithm,key,iv)=>cipherAdapter(true,algorithm,key,iv)
};}
function cipherAdapter(decrypt,algorithm,key,iv){let padding=true,used=false;return {setAutoPadding(v){padding=v;return this;},update(b){if(used)throw Error('Only single-buffer protocol encryption supported');used=true;return Buffer.from(activeCtx.crypto[decrypt?'aesDecrypt':'aesEncrypt'](Buffer.from(b).toString('base64'),key.toString('hex'),iv.toString('hex'),{mode:algorithm.split('-')[2].toUpperCase(),padding:padding?'Pkcs7':'NoPadding',keyEncoding:'hex',ivEncoding:'hex',inputEncoding:'base64',outputEncoding:'base64'}),'base64');},final(){return Buffer.alloc(0);}};}
function libraries(ctx){activeCtx=ctx;if(loaded)return loaded;const cache={};const process={env:{},};const require=name=>{
 if(name==='node:crypto'||name==='crypto')return cryptoAdapter();
 if(name==='node:zlib')return {gzipSync:b=>Buffer.from(ctx.crypto.gzip(b.toString('base64'),{inputEncoding:'base64',outputEncoding:'base64'}),'base64')};
 if(name==='../services/logger')return {info(){},warn(){}};
 if(name==='./playback-device'){const fn={getCurrentDevice:()=>currentIdentity};return {getPlaybackDevice:fn};}
 if(name==='./device-session')return {deviceKey:()=>''};
 if(name==='./argus')return {};
 if(name==='./download-quality')return {};
 if(cache[name])return cache[name].exports;
 const factory=LIBRARIES[name];if(!factory)throw Error('Missing internal protocol module');const module={exports:{}};cache[name]=module;factory(module,module.exports,require,process);return module.exports;
 };loaded={v5:require('./v5-sign'),metadata:require('./metadata'),register:require('./register'),mp4:require('./mp4')};return loaded;}

const LIBRARIES={
"./sm3":function(module,exports,require,process){
// SPDX-License-Identifier: GPL-3.0-only
// SM3 (GB/T 32905), pure JavaScript: Electron's bundled crypto may omit SM3.
module.exports = function sm3(input) {
  const source = Buffer.isBuffer(input) ? input : Buffer.from(input);
  const data = Buffer.alloc(Math.ceil((source.length + 9) / 64) * 64);
  source.copy(data);
  data[source.length] = 0x80;
  data.writeBigUInt64BE(BigInt(source.length) * 8n, data.length - 8);
  const state = new Uint32Array([0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600, 0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e]);
  const words = new Uint32Array(68);
  const rotate = (x, n) => ((x << (n & 31)) | (x >>> ((32 - n) & 31))) >>> 0;
  for (let offset = 0; offset < data.length; offset += 64) {
    for (let i = 0; i < 16; i++) words[i] = data.readUInt32BE(offset + i * 4);
    for (let i = 16; i < 68; i++) {
      const x = words[i - 16] ^ words[i - 9] ^ rotate(words[i - 3], 15);
      words[i] = x ^ rotate(x, 15) ^ rotate(x, 23) ^ rotate(words[i - 13], 7) ^ words[i - 6];
    }
    let [a, b, c, d, e, f, g, h] = state;
    for (let i = 0; i < 64; i++) {
      const a12 = rotate(a, 12);
      const s1 = rotate((a12 + e + rotate(i < 16 ? 0x79cc4519 : 0x7a879d8a, i)) >>> 0, 7);
      const s2 = s1 ^ a12;
      const ff = i < 16 ? a ^ b ^ c : (a & b) | (a & c) | (b & c);
      const gg = i < 16 ? e ^ f ^ g : (e & f) | (~e & g);
      const t1 = (ff + d + s2 + (words[i] ^ words[i + 4])) >>> 0;
      const t2 = (gg + h + s1 + words[i]) >>> 0;
      d = c; c = rotate(b, 9); b = a; a = t1;
      h = g; g = rotate(f, 19); f = e;
      e = (t2 ^ rotate(t2, 9) ^ rotate(t2, 17)) >>> 0;
    }
    const next = [a, b, c, d, e, f, g, h];
    for (let i = 0; i < 8; i++) state[i] ^= next[i];
  }
  const digest = Buffer.alloc(32);
  for (let i = 0; i < 8; i++) digest.writeUInt32BE(state[i], i * 4);
  return digest;
};

},
"./v5-sign":function(module,exports,require,process){
// SPDX-License-Identifier: GPL-3.0-only
// SPDX-License-Identifier: GPL-3.0-only
// v04.10.03 mobile playback signing (mobileV5=true).
// Ported from N3urda/hongguoTV core Signer.kt / AesV3.kt / V5Constants.kt
// (which are themselves ports of drpys 22261ad, GPL-3.0-only).
// Crypto tables and SDK protocol constants below are not user credentials.
//
// Scope: ONLY the /novel/player/multi_video_model/player/v1 playback endpoint.
// Search/catalogue endpoints keep the legacy v3 signer in app-source.js.
const crypto = require('node:crypto');
const sm3 = require('./sm3');

// ---------- low-level helpers (mirror Signer.kt / Bytes.kt) ----------
function u32(value) { return Number(value) >>> 0; }
function rol32(value, count) { const n = count & 31; const x = u32(value); return u32((x << n) | (x >>> (32 - n))); }
function ror32(value, count) { const n = count & 31; const x = u32(value); return u32((x >>> n) | (x << (32 - n))); }
function le32(value) { const b = Buffer.alloc(4); b.writeUInt32LE(u32(value)); return b; }
function be32(value) { const b = Buffer.alloc(4); b.writeUInt32BE(u32(value)); return b; }
function zigzag(value) { const n = BigInt(value); return n < 0n ? ((-n) * 2n - 1n) : n * 2n; }
function varint(value) { let n = BigInt(value); const out = []; while (n > 127n) { out.push(Number((n & 127n) | 128n)); n >>= 7n; } out.push(Number(n)); return Buffer.from(out); }
function protoField(tag, value, type = 'string') {
    if (value === undefined || value === null || value === '') return Buffer.alloc(0);
    if (type === 'bytes' || type === 'string' || type === 'message') {
        const body = type === 'bytes' ? Buffer.from(value) : type === 'message' ? value : Buffer.from(String(value));
        return Buffer.concat([varint((BigInt(tag) << 3n) | 2n), varint(body.length), body]);
    }
    if (type === 'float') { const body = Buffer.alloc(4); body.writeFloatLE(Number(value)); return Buffer.concat([varint((BigInt(tag) << 3n) | 5n), body]); }
    return Buffer.concat([varint(BigInt(tag) << 3n), varint(type === 'sint' ? zigzag(value) : value)]);
}
function proto(fields) { return Buffer.concat(fields.map(([tag, value, type]) => protoField(tag, value, type))); }
function getIv(iv, data) { let value = u32(iv); for (let i = 0; i < data.length; i += 1) { if ((i & 1) === 0) value = u32((value >>> 4) ^ value ^ (value << 6) ^ data[i]); else value = u32(~((value >>> 7) ^ value ^ (data[i] | (value << 12)))); } return value; }
function sumMd5(data) { let check = 0x20220420; for (let i = 0; i < 12; i += 1) { const temp = (i & 1) === 0 ? (check >>> 3) ^ check : (check >>> 5) ^ check; check = (i & 1) === 0 ? data[i] ^ (check << 7) : data[i] | (check << 11); if ((i & 1) !== 0) check = ~check; check = u32(check ^ temp); } return u32((check | 4) ^ 0x1000000); }
function xorBytes(a, b) { const out = Buffer.alloc(a.length); for (let i = 0; i < out.length; i += 1) out[i] = a[i] ^ b[i % b.length]; return out; }
function bxor(a, b) { const out = Buffer.alloc(Math.min(a.length, b.length)); for (let i = 0; i < out.length; i += 1) out[i] = a[i] ^ b[i]; return out; }
function md5(data) { return crypto.createHash('md5').update(data).digest(); }
function upperHex(data) { return data.toString('hex').toUpperCase(); }

// ---------- V5Constants.kt ----------
const V5_MAGIC = Buffer.from('2d4b4fca49750d433fb5ae2c226dcc56', 'hex');
const V5_LICENSE = '646637794';
const V5_SIGN_KEY = Buffer.from(
    'b23c2a470a20d105dc3f8c4438f8272ed46d6c89ffdcdedd5108698d26e9489d', 'hex');
const V5_SBOX = Buffer.from(
    '53290fe9e51f316f90f74a7e034d367784ab49237cd0135cdc632c322fd3be0e2624a417ecd9151a7ff64f60730a87f9445ec6ada2f865d22b696c4188f24c0d' +
    'f37b75510b939f6bc2fe6883e68bc8c722181ba0bdb08c9871b50c9a16b46eea8eed20ba4b8a14e0fcf1468dbbef05a93e5a9d7dcf06898635c1fd99f5de287a' +
    '80c594daaab19b6279fbd75070cb52eb2555c456e39e7839853874e2f0013ac0b64742d8ca10e4b79c955de8b843ce4ed464a6a72ed508091c92e7b3eedd1e1d' +
    'd12afac321618fa3d65f9167c982f43d66a53c6a1997585b346dbf9672ff37cdbc073b2dae11453304df00815476b2a13fccdb30b957a8acafe1274002485912' +
    '38922563e36406d37a24100b7902a028044e218453c2a399199c9d13dc40c55ba67e502273850ebdc1a2e2188b8f2d9e3cb909b8c46a2a9f4a6dd93007eafa65' +
    'b7b3a881aa908cc74f0ad76bbbb58617c37012ca05a469fd44e62eecf1e4272ce860c0ae5eadf99b20d8f0234174006f3f110d7657d01645d4eff8f71471cbfe' +
    '1cb2f52648727bf3c9de55153e031b4d61757db63dbf7782eeafe9018a8891362fb14759ac32bab03b349aeb5a377c5156be4c8dfbe13a684bda39cf836697c8' +
    '94545fe0f2491acea9fc6252f4ff1e0fe72bd2df6e67a7f635e5bcc6d1a5dd951d89960887a18eb40c785cdb1f80ed42299333ab98cdd67f316cd54346585dcc' +
    'd759fb722789b08807cc0fda293f7e5e1819bb0353517020b31d3d00374952bea2c421e862040a9ec892a05b266b7a0d0cc316f483b81af39715657ffe32ad8d' +
    'e0c13077646035236ee5363e5f900e9a7cf850a81cd9960b6df73317226f99eaa6fff15cec34acb98246639b918ab2851466a7cdfc4ad1b52c2ae95a58d3734e' +
    '47ddd5b7560193f644ef9c408b7dee39b4d6aabf4de761e3252d4c7ba3843187745d55e6a5db05d42b45caed43c0c5d0b64bfa9d94a4a9d8f2f0e1a108dcfd28' +
    '8fd2bc1fc7bd675412138169cb09249875ba3b68cfb11180afae104fc9789571c6dfce02413886796ae21e3c488cc21b9f423a066c2eabf98e2fdeeb5776e4f5' +
    'd09a515ba58cbbab3e37b09fd4f6d9244df80512e84cd7956be301cf64f1429d58577cc241f3a2c655144f81aaf95a4e108da894b38970561ae9002619fbbac9' +
    '1fa922ed202bfc62cb08e0de2a7f3631435f8b47c8a3c563b4db4071ce74c46da6fa696a9e282d1e825d663b93bfd56c48dce1884bb10fccea063929f746443f' +
    'd830a4232e53da21a1f2d1bdfebc3a02c10a1b8ad31d04fd616590d272ac737e98eb33af60528716bee78ec0ee8699031177277d9cff32542c67caf5f4459168' +
    '1335ae0e178f3409a7803db83892dde5b9b7f0c750e24aef077badd678a09b850b84ec1597e4963cb5e675df1c0d6fb618496ecd76c35c798325590c2fb27a5e', 'hex');

// VendorConstants.kt hashTable (shared by v3 and v5 hashF13).
const HASH_TABLE = [
    0xebb64faf,0x7aadcc2,0xcf3187bf,0xe01138ff,0x6d0bfcff,0x5a30a3be,0xb41ad638,0x34180eb8,
    0xf233eb6f,0xb1a584cc,0xccc30dc7,0x47d1db51,0xd55653de,0x70a84fa1,0x57473c12,0xf76f0288,
    0x2c077f0a,0xda0dcad0,0xfbb86f6c,0xfdc4cf00,0x688a020d,0xe676c6a6,0x8cd6338b,0x1a3c8d0e,
    0xcce8b06b,0x6ad0ed0b,0xa0522717,0xdc71ac83,0x2285db71,0xd5b4dda6,0x736f8650,0x6560306c,
    0x617ce2a6,0xe423417e,0xa40e143,0x544e4032,0x88dffb2a,0x716c1ae0,0x4c467a88,0x5b23bb3,
    0xe1d0b866,0xbaa3dcb8,0xae3374d3,0xc3381a50,0x1702f75b,0xfe6da368,0xf0b4cf48,0x4e0ffbb8,
    0x72aad10d,0x26c53a3d,0xf2bce0f6,0xb4557581,0x4a257fdd,0x8c3182a2,0xab0b3b86,0x3d5dfb14,
    0x4f103634,0xd37b52d7,0x444eff16,0xeb0a33d1,0x6ca86f6e,0x284ba7,0x8387cfa,0x5fb37586,
];

// ---------- hashF13 v5 (Signer.kt hashF13, mobileV5 branch) ----------
// query: sm3(encoded query string), body: md5(gzip body), ts: khronos seconds.
function ivOf(query, body, ts) {
    return getIv(getIv(getIv(0x20230928, query), body), le32(ts));
}
function branchV5(queryString, body, ts) {
    const query = sm3(Buffer.from(queryString));
    const digest = body ? md5(body) : Buffer.alloc(16);
    const low = ivOf(query, digest, ts) & 15;
    return low === 12 ? 0 : 1;
}
function hashF13V5(query, body, ts) {
    const low = ivOf(query, body, ts) & 15;
    if (low !== 12) throw new Error(`v5 hash branch unsupported: ${low}`);
    const ivV1 = 0x9d4a97c2;
    const count = u32(ivV1 + ts);
    const tt = HASH_TABLE.map(value => ror32(value, count + 1));
    const shift = (count + 2) & 7;
    const pad = Buffer.from([0xfa, 0x45, 0x61, 0xd7].map(value => ((value | (value << 8)) >> shift) & 255));
    const data = Buffer.concat([query, body, le32(ts), pad, Buffer.from('00000000000001a0', 'hex')]);
    const di = [];
    for (let i = 0; i < data.length; i += 4) di.push(data.readUInt32BE(i));
    let di0 = di[0];
    for (let i = 0; i < 112; i += 1) {
        const x = di[i + 1];
        const y = di[i + 14];
        const r1 = rol32(x, 14) ^ rol32(x, 25) ^ (x >>> 3);
        const r2 = rol32(y, 13) ^ rol32(y, 15) ^ (y >>> 10);
        di.push(u32(di0 + di[i + 9] + r1 + r2));
        di0 = x;
    }
    const initial = [0x7aba4fc8,0x67166507,0x6403fa00,0x340f512f,984304912,3005047866,2874125293,2152413264]
        .map(value => ror32(value, count));
    const chosen = [96,1,3,4,0,6,5,2,0,7,7];
    const d = initial.slice();
    for (let i = 0; i < chosen[0]; i += 1) {
        const base = (ivV1 + i) >>> 0;
        const n1 = ((d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]]) ^ d[chosen[3]];
        const n2 = rol32(d[chosen[1]], 26) ^ rol32(d[chosen[1]], 21) ^ rol32(d[chosen[1]], 7);
        const n4 = u32(di[base & 127] + n1 + n2 + tt[base & 63] + d[chosen[5]]);
        const n5 = rol32(d[chosen[2]], 30) ^ rol32(d[chosen[2]], 19) ^ rol32(d[chosen[2]], 10);
        const n6 = (d[chosen[2]] & d[chosen[6]]) | ((d[chosen[2]] | d[chosen[6]]) & d[chosen[7]]);
        const old = d[chosen[9]];
        d.unshift(d.pop());
        d[chosen[10]] = u32(n5 + n6 + n4);
        d[chosen[8]] = u32(old + n4);
    }
    const ret = Buffer.alloc(32);
    for (let i = 0; i < 8; i += 1) ret.writeUInt32BE(u32(d[i] + initial[i]), i * 4);
    const folded = bxor(ret.subarray(0, 16), ret.subarray(16, 32));
    const check = sumMd5(folded) | 0x20;
    return Buffer.concat([folded, le32(check)]);
}

// ---------- AesV3 v5 (AesV3.kt, v5=true) ----------
function matrix(bytes) { return Array.from({ length: 4 }, (_v, i) => Array.from(bytes.subarray(i * 4, i * 4 + 4))); }
function flat(rows) { return Buffer.from(rows.flat()); }
function aesMix(rows) {
    for (let i = 0; i < 4; i += 1) {
        const t = rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i];
        const u = rows[0][i];
        const xt = x => ((x << 1) ^ ((x & 128) ? 0x1b : 0)) & 255;
        rows[0][i] = u32(rows[0][i] ^ t ^ xt(rows[0][i] ^ rows[1][i]));
        rows[1][i] = u32(rows[1][i] ^ t ^ xt(rows[1][i] ^ rows[2][i]));
        rows[2][i] = u32(rows[2][i] ^ t ^ xt(rows[2][i] ^ rows[3][i]));
        rows[3][i] = u32(rows[3][i] ^ t ^ xt(rows[3][i] ^ u));
    }
}
class AesV3V5 {
    constructor(key, khronos) {
        const word = khronos & 3;
        this.box = V5_SBOX.subarray(word * 256, (word + 1) * 256);
        this.con = [
            [2,0,3,1],[1,3,2,0],[3,2,1,0],[2,3,1,0],
        ][word];
        this.order = [
            [0,9,14,15,4,13,2,7,8,1,6,3,12,5,10,11],
            [0,9,14,11,4,13,2,3,8,1,6,15,12,5,10,7],
            [0,9,14,3,4,13,2,15,8,1,6,11,12,5,10,7],
            [0,9,14,15,4,13,2,3,8,1,6,11,12,5,10,7],
        ][word];
        const init = [0xbbb5de72,0xd4638d5b,0x92a5f73b,0x89f8a1c9][word];
        const initial = Buffer.alloc(16);
        for (let i = 0; i < 4; i += 1) initial.writeUInt32LE(init, i * 4);
        const expanded = Buffer.concat([xorBytes(initial, key), Buffer.alloc(32)]);
        let rounds = 8;
        for (let i = 4; i < 12; i += 1) {
            const at = 4 * (i - 1);
            let a = expanded[at], b = expanded[at + 1], c = expanded[at + 2], d = expanded[at + 3];
            if ((i & 3) === 0) {
                const t = (u32(init >> (rounds & 24)) ^ this.box[b]) & 255;
                b = this.box[c]; c = this.box[d]; d = this.box[a]; a = t;
            }
            rounds += 2;
            expanded[at + 4] = a ^ expanded[at - 12];
            expanded[at + 5] = b ^ expanded[at - 11];
            expanded[at + 6] = c ^ expanded[at - 10];
            expanded[at + 7] = d ^ expanded[at - 9];
        }
        this.keys = Array.from({ length: 12 }, (_v, i) => Array.from(expanded.subarray(i * 4, i * 4 + 4)));
    }
    addCon(rows, keys) { for (let i = 0; i < 4; i += 1) for (let j = 0; j < 4; j += 1) rows[i][j] ^= keys[i][this.con[j]]; }
    sub(rows) {
        for (let i = 0; i < 4; i += 1) for (let j = 0; j < 4; j += 1) rows[i][j] = this.box[rows[i][j]];
        const before = rows.map(row => row.slice());
        for (let i = 0; i < 4; i += 1) rows[i] = before[this.con[i]].slice();
    }
    shift(rows) { const b = flat(rows); for (let i = 0; i < 16; i += 1) rows[Math.floor(i / 4)][i % 4] = b[this.order[i]]; }
    shiftCon(rows) { const old = rows.map(row => row.slice()); for (let i = 0; i < 4; i += 1) rows[i] = this.con.map(j => old[i][j]); }
    block(value) {
        const rows = matrix(value);
        this.addCon(rows, this.keys.slice(0, 4));
        for (let round = 1; round < 3; round += 1) {
            this.sub(rows);
            this.shift(rows);
            if (round === 1) { this.shiftCon(rows); aesMix(rows); }
            this.addCon(rows, this.keys.slice(round * 4));
        }
        for (let i = 0; i < 4; i += 1) for (let j = 0; j < 4; j += 1) rows[i][j] ^= this.keys[4 + i][j];
        return flat(rows);
    }
    encrypt(source, iv) {
        if (source.length < 248) throw new Error('v5 AesV3 source too short');
        const wire = [6,5,3,4,2,7,1,0];
        const compact = [1,7,3,6,2,0,4,5];
        const plaintext = Buffer.alloc(32);
        for (let i = 0; i < 31; i += 1) for (let j = 0; j < 8; j += 1) {
            plaintext[i] |= ((source[i * 8 + j] >>> wire[j]) & 1) << compact[j];
        }
        plaintext[31] = 1;
        const first = this.block(xorBytes(plaintext.subarray(0, 16), iv));
        const key = Buffer.concat([first, this.block(xorBytes(plaintext.subarray(16, 32), first))]);
        const out = Buffer.from(source);
        for (let i = 0; i < 31; i += 1) for (let j = 0; j < 8; j += 1) {
            const at = i * 8 + j;
            out[at] = (out[at] & ~(1 << wire[j]) | (((key[i] >>> compact[j]) & 1) << wire[j])) & 255;
        }
        return Buffer.concat([Buffer.from([key[key.length - 1]]), out]);
    }
}

// ---------- medusa v5 (Signer.kt medusaV5) ----------
function rand() { return Math.floor(Math.random() * 0x100000000); }
function xmxor(data, key) {
    const encoded = Buffer.alloc(data.length);
    for (let i = 0; i < data.length; i += 1) {
        const at = (i * 4) & 28;
        const d0 = key[at], d1 = key[at + 1];
        let d2 = ((((data[i] << 4) | (data[i] >>> 4)) & 255) + d0);
        d2 = (~d2) ^ d1;
        d2 = (((d2 & 255) << 3) | ((d2 & 255) >>> 5)) & 255;
        d2 = (d2 + d1) & 255;
        d2 = (d2 ^ d0) & 255;
        encoded[data.length - i - 1] = (~d2) & 255;
    }
    let last = encoded[encoded.length - 1] ^ encoded[encoded.length - 2];
    const first = encoded[0];
    encoded[0] = ((~last) + first) & 255;
    encoded[1] = ((encoded[0] ^ encoded[encoded.length - 1] ^ 254) + encoded[1]) & 255;
    encoded[2] = (encoded[2] + ((last - first) ^ (((encoded[1] << 3) | (encoded[1] >>> 5)) & 255) ^ 2)) & 255;
    for (let i = 0; i < encoded.length - 4; i += 1) {
        const temp = (((encoded[i + 2] << 3) | (encoded[i + 2] >>> 5)) & 255) ^ encoded[i + 1] ^ (i + 3);
        encoded[i + 3] = ((~temp) + encoded[i + 3]) & 255;
    }
    encoded[encoded.length - 1] ^= encoded[encoded.length - 2];
    let sum = 0;
    for (let i = 0; i < encoded.length - 1; i += 1) sum += encoded[i + 1];
    encoded[0] = ((encoded[0] ^ encoded[1]) + sum) & 255;
    return encoded;
}
function keyHash(signKey, random) {
    const hash = sm3(Buffer.concat([signKey, le32(random), signKey]));
    const d1 = (random >> 16) & 255;
    let d2 = (((d1 << 11) | (random >>> 24)) ^ (d1 >>> 5) ^ d1);
    d2 = (~d2) >>> 0;
    return [hash, le32(d2)];
}

const PROCESS_NONCE = crypto.randomBytes(18).toString('base64url');
const PROCESS_STARTED = Date.now();

function medusaV5(queryString, body, ts, values) {
    const query = sm3(Buffer.from(queryString, 'utf8'));
    const f13 = hashF13V5(query, body ? md5(body) : Buffer.alloc(16), ts);
    const flags = Buffer.alloc(8);
    const version = values.version_name;
    const deviceInfo = proto([
        [1,1,'sint'],[2,2,'sint'],[3,'8662'],[4,values.device_id],[5,PROCESS_NONCE],
        [6,'!noperm!'],[12,'Asia/Shanghai,8'],[13,'zh_CN'],
        [22,values.os_version],[25,PROCESS_STARTED,'sint'],
        [30,values.device_type],[31,'HONOR'],[32,values.device_type],[34,'HONOR'],
    ]);
    const env = proto([
        [6,'v04.10.03.04-bugfix'],[8,values.channel],[12,deviceInfo,'message'],[14,version],
    ]);
    const message = proto([
        [1,V5_MAGIC,'bytes'],[2,5,'sint'],[3,u32(rand()),'sint'],[4,'8662'],
        [5,values.device_id],[6,V5_LICENSE],[7,version],[8,'v04.10.03-ml-android'],
        [9,0x040a0300,'sint'],[10,flags,'bytes'],[12,ts,'sint'],[13,f13,'bytes'],
        [14,query.subarray(0,6),'bytes'],
        [15,proto([[1,1,'sint'],[2,1,'sint'],[3,1,'sint'],[5,1,'sint']]),'message'],
        [17,ts,'sint'],[20,'none'],[21,377,'sint'],[23,env,'message'],
        [24,'{"cmr":16777216,"cmr2":16777216,"un_h":11,"vpn":0,"kd":0,"dyn":"","do":1,"tk":true}'],
    ]);
    const nonce = rand();
    const [hash, seed] = keyHash(V5_SIGN_KEY, nonce);
    let transformed = Buffer.concat([flags, xmxor(message, hash)]).reverse();
    for (let i = 0; i < transformed.length; i += 1) transformed[i] ^= seed[(~i) & 3];
    const check = u32(0x18000001 | ((query[0] & 63) << 14) | ((f13[0] & 63) << 8));
    const packed = Buffer.concat([
        Buffer.from([0xca]), le32(rand()), le32(check), transformed,
        Buffer.from([(nonce >>> 16) & 255, (nonce >>> 24) & 255]),
    ]);
    const encrypted = new AesV3V5(md5(V5_SIGN_KEY.subarray(0, 16)), ts)
        .encrypt(packed, md5(V5_SIGN_KEY.subarray(16, 32)));
    const prefix = Buffer.concat([le32(5), V5_MAGIC]);
    const tsBytes = le32(ts);
    for (let i = 0; i < prefix.length; i += 1) prefix[i] ^= tsBytes[i & 3];
    return Buffer.concat([
        prefix,
        Buffer.from([nonce & 255, (nonce >>> 8) & 255, 0, 1]),
        encrypted,
    ]).toString('base64');
}

// ---------- helios v5 (Signer.kt helios, mobileV5 license) ----------
function ror64(value, count) { const n = BigInt(count) & 63n; const x = uint64( BigInt(value)); return uint64( (x >> n) | (x << (64n - n))); }
function heliosV5(ts) {
    const random = rand();
    const digestText = md5(Buffer.concat([le32(random), Buffer.from('8662')])).toString('hex');
    const ascii = Buffer.from(digestText, 'ascii');
    const words = [];
    for (let i = 0; i < 4; i += 1) words.push(ascii.readBigUInt64LE(i * 8));
    const table = [words[0]];
    let b0 = words[0], b8 = words[1];
    words.splice(0, 2);
    for (let i = 0; i < 34; i += 1) {
        let x8 = uint64( ror64(b8, 8) + b0);
        x8 = uint64( x8 ^ BigInt(i));
        words.push(x8);
        x8 = uint64( x8 ^ ror64(b0, 61));
        table.push(x8);
        b0 = x8;
        b8 = words.shift();
    }
    const text = Buffer.from(`${ts}-${V5_LICENSE}-8662`);
    const pad = Buffer.alloc(Math.ceil((text.length + 1) / 16) * 16, 16 - (text.length % 16));
    text.copy(pad);
    const output = [];
    for (let at = 0; at < pad.length; at += 16) {
        let a = pad.readBigUInt64LE(at), b = pad.readBigUInt64LE(at + 8);
        for (let i = 0; i < 34; i += 1) {
            b = uint64( table[i] ^ uint64( a + ror64(b, 8)));
            a = uint64( b ^ ror64(a, 61));
        }
        const block = Buffer.alloc(16);
        block.writeBigUInt64LE(a); block.writeBigUInt64LE(b, 8);
        output.push(block);
    }
    return Buffer.concat([le32(random), ...output]).toString('base64');
}

// ---------- query encoding (Signer.kt encode): Java URLEncoder semantics ----------
function encodeValue(value) {
    return encodeURIComponent(String(value == null ? '' : value))
        .replace(/[!'()]/g, ch => `%${ch.charCodeAt(0).toString(16).toUpperCase()}`)
        .replace(/%7E/g, '~');
}
function encodeValues(values) {
    return Object.entries(values).map(([k, v]) => `${encodeValue(k)}=${encodeValue(v)}`).join('&');
}

// ---------- public: sign a v5 playback request ----------
// base: endpoint without query. values: fixed v5 query params incl. _rticket base.
// body: gzip buffer. now: clock ms (default Date.now()).
// returns { url, headers } where headers only contain v5 signing + body headers.
function signPlaybackV5(base, values, body, now = Date.now()) {
    const ts = Math.floor(now / 1000);
    for (let offset = 0; offset < 1024; offset += 1) {
        const ticket = now + offset;
        const next = { ...values, _rticket: String(ticket) };
        const query = encodeValues(next);
        if (branchV5(query, body, ts) !== 0) continue;
        const url = `${base}?${query}`;
        const headers = {
            'x-khronos': String(ts),
            'x-helios': heliosV5(ts),
            'x-medusa': medusaV5(url.substring(base.length + 1), body, ts, next),
        };
        if (body) {
            headers['Content-Type'] = 'application/json; charset=utf-8';
            headers['x-ss-stub'] = upperHex(md5(body));
        }
        return { url, headers };
    }
    throw new Error('无法生成 v5 播放签名');
}

module.exports = {
    hashF13V5, branchV5, AesV3V5, medusaV5, heliosV5, signPlaybackV5, encodeValues,
    V5_MAGIC, V5_LICENSE, V5_SIGN_KEY, V5_SBOX, HASH_TABLE,
};

},
"./metadata":function(module,exports,require,process){
// SPDX-License-Identifier: GPL-3.0-only
// SPDX-License-Identifier: GPL-3.0-only
// Signing and Spade algorithms adapted from woshishiq1/drpys
// commit 22261adfa31435e3b3ef5a730b8a2a75bcaf1715, spider/js/红果果[短].js,
// via N3urda/hongguoTV eea73e6a45569a2cbbb9440f7cd5290c459b0b70.
// Changes: registered in-memory playback identity; pure JS SM3;
// bounded HTTPS transport; exact episode matching; supported codec selection.
// Crypto tables and SDK protocol constants below are not user credentials.
const crypto = require('node:crypto');
const { gzipSync } = require('node:zlib');
const logger = require('../services/logger');
const { getPlaybackDevice } = require('./playback-device');
const { deviceKey } = require('./device-session');
const sm3 = require('./sm3');
const { PlayerSigner } = require('./argus');
const { signPlaybackV5 } = require('./v5-sign');
const { normalizeDownloadQuality, meetsDownloadQuality } = require('./download-quality');
const localId = () => String(1000000000000000n + BigInt('0x' + crypto.randomBytes(6).toString('hex')));
const PROCESS_NONCE = crypto.randomBytes(18).toString('base64url');
const PROCESS_STARTED = Date.now();
const VIDEO_API = 'https://reading.snssdk.com/novel/player/multi_video_model/player/v1';
const VIDEO_API_FALLBACK = 'https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1';
const VIDEO_APIS = [
    VIDEO_API,
    VIDEO_API_FALLBACK,
    'https://api5-normal-lq.fqnovel.com/novel/player/multi_video_model/player/v1',
    'https://is.snssdk.com/novel/player/multi_video_model/player/v1',
    'https://api5-normal-hl.fqnovel.com/novel/player/multi_video_model/player/v1',
];
const SHORTPLAY_API = 'https://api3-normal-sinfonlinea.fqnovel.com/novel/player/video_model/v1/';
const SHORTPLAY_APIS = [
    SHORTPLAY_API,
    'https://api5-normal-lq.fqnovel.com/novel/player/video_model/v1/',
    'https://reading.snssdk.com/novel/player/video_model/v1/',
];
const SEARCH_API = 'https://api5-normal-sinfonlinea.fqnovel.com/reading/bookapi/search/tab/v';
const VIDEO_UA = 'com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)';
const PLAYBACK_UA = 'com.phoenix.read/74332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)';
// v5 playback uses the official 7.3.9.32 PGT-AN10 profile (see hongguoTV MobilePlayback.kt).
const V5_PLAYBACK_UA = 'com.phoenix.read/73932 (Linux; U; Android 12; zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)';
const V5_PLAYBACK_QUERY = {
    aid: '8662', app_name: 'novelread', version_code: '74332', version_name: '7.4.3.32',
    channel: 'vivo_8662_64', device_platform: 'android', device_type: 'PGT-AN10',
    os_version: '12', update_version_code: '74332',
};
const SEARCH_UA = 'com.phoenix.read/72232 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3)';
const DEVICE = {
    ac: 'wifi', channel: 'update_64', aid: '8662', app_name: 'novelread',
    version_code: '71332', version_name: '7.1.3.32', device_platform: 'android', os: 'android',
    ssmix: 'a', device_type: '25053RT47C', device_brand: 'Redmi', language: 'zh', os_api: '36',
    os_version: '16', manifest_version_code: '71332', resolution: '1280*2772', dpi: '520',
    update_version_code: '71332', host_abi: 'arm64-v8a', dragon_device_type: 'phone', pv_player: '71332',
    compliance_status: '0', need_personal_recommend: '1', player_so_load: '1', is_android_pad_screen: '0',
};
function str(value, fallback = '') { return String(value == null ? fallback : value).trim(); }
function cleanUrl(value) { return str(value).replace(/\\\//g, '/').replace(/\\u0026/g, '&').replace(/&amp;/g, '&'); }
function jsonBody(value) { try { return JSON.parse(value); } catch { return null; } }
// 签名对 query 字节级敏感：python urllib.parse.quote 的 ['!'*'()'] 兜底编码行为须保持一致
function pythonUrlEncode(values) {
    return Object.entries(values).map(([key, value]) => {
        const encode = (item) => encodeURIComponent(String(item == null ? '' : item))
            .replace(/[!'()]/g, (ch) => `%${ch.charCodeAt(0).toString(16).toUpperCase()}`);
        return `${encode(key)}=${encode(value)}`;
    }).join('&');
}
function md5(value) { return crypto.createHash('md5').update(value).digest('hex').toUpperCase(); }

function u32(value) { return Number(value) >>> 0; }
function rol32(value, count) { const n = count & 31; const x = u32(value); return u32((x << n) | (x >>> (32 - n))); }
function ror32(value, count) { const n = count & 31; const x = u32(value); return u32((x >>> n) | (x << (32 - n))); }
function ror64(value, count) { const n = BigInt(count) & 63n; const x = uint64( BigInt(value)); return uint64( (x >> n) | (x << (64n - n))); }
function le32(value) { const b = Buffer.alloc(4); b.writeUInt32LE(u32(value)); return b; }
function be32(value) { const b = Buffer.alloc(4); b.writeUInt32BE(u32(value)); return b; }
function zigzag(value) { const n = BigInt(value); return n < 0n ? ((-n) * 2n - 1n) : n * 2n; }
function varint(value) { let n = BigInt(value); const out = []; while (n > 127n) { out.push(Number((n & 127n) | 128n)); n >>= 7n; } out.push(Number(n)); return Buffer.from(out); }
function protoField(tag, value, type = 'string') {
    if (value === undefined || value === null || value === '') return Buffer.alloc(0);
    if (type === 'bytes' || type === 'string' || type === 'message') {
        const body = type === 'bytes' ? Buffer.from(value) : type === 'message' ? value : Buffer.from(String(value));
        return Buffer.concat([varint((BigInt(tag) << 3n) | 2n), varint(body.length), body]);
    }
    if (type === 'float') { const body = Buffer.alloc(4); body.writeFloatLE(Number(value)); return Buffer.concat([varint((BigInt(tag) << 3n) | 5n), body]); }
    return Buffer.concat([varint(BigInt(tag) << 3n), varint(type === 'sint' ? zigzag(value) : value)]);
}
function proto(fields) { return Buffer.concat(fields.map(([tag, value, type]) => protoField(tag, value, type))); }
function getIv(iv, data) { let value = u32(iv); for (let i = 0; i < data.length; i += 1) { if ((i & 1) === 0) value = u32((value >>> 4) ^ value ^ (value << 6) ^ data[i]); else value = u32(~((value >>> 7) ^ value ^ (data[i] | (value << 12)))); } return value; }
function sumMd5(data) { let check = 0x20220420; for (let i = 0; i < 12; i += 1) { const temp = (i & 1) === 0 ? (check >>> 3) ^ check : (check >>> 5) ^ check; check = (i & 1) === 0 ? data[i] ^ (check << 7) : data[i] | (check << 11); if ((i & 1) !== 0) check = ~check; check = u32(check ^ temp); } return u32((check | 4) ^ 0x1000000); }
const BRANCH2_SV = [0xa7aefe20,0x7149f1d6,0x47e4ca07,0xe9b58f67,0x93b924de,0xc614d0f5,0x38afe0ef,0xb2bbad73,0xe24444c3,0x9d3aec9b,0xdf7b37e4,0xd8b16d40,0xf8ac31b8,0x76b9a90b,0x31d833ee,0x953fce64,0x353595a4,0x4609c13b,0x36925008,0x8c6d0925,0x5df5c177,0x1cfbf52b,0x8a4fa7f0,0x114ca35e,0x8193f984,0x7a7a8733,0x316ab4d5,0x3c20cfc9,0xa6d84453,0x3a18500c,0x798ec47a,0x97a76b28,0x66c4ff96,0x51716443,0xdd2fc3b,0xb5696da7,0xbbeb3ac5,0x5c53d204,0xd32608ce,0x7279b9ec,0xf4188ecf,0xf7d793db,0x332cc491,0xab76ae15,0x9bebe727,0x18a01384,0x5be9f8a7,0x5f90a754,0x39b663c0,0x36673c83,0x7c92f514,0x9d7d94d7,0xe2e8d9aa,0x5f7e9ea9,0x7abd4551,0x569e05da,0x40a25632,0x3df5a9a5,0xbab37d80,0x454286dc,0x3f5d4e78,0x3d7b75d,0xb1fe4af7,0xa5ab26a3];
const BRANCH2_ORDERS = Buffer.from('0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003','hex');
function md5V3Step(kind, a, b, c, d, m, shift, constant) { let f; if (kind === 0) f = (b & c) | ((~b) & d); else if (kind === 1) f = (b & d) | (c & (~d)); else if (kind === 2) f = b ^ c ^ d; else f = c ^ (b | (~d)); return u32(b + rol32(u32(a + f + m + constant), shift)); }
function md5SumV3(message, countV2, orders, countV1) {
    const sv = BRANCH2_SV.map((value) => ror32(value, countV1)); const start = [ror32(0x79e0f2fb, countV2), ror32(0xc8b52570, countV2), ror32(0xebc2f8cd, countV2), ror32(0x7c104d93, countV2)]; const endCount = (countV2 + 6) & 255; const end = [ror32(0x19be4866, endCount), ror32(0xe85986b4, endCount), ror32(0xe19b326e, endCount), ror32(0x71d1d7d4, endCount)]; const m = []; for (let i = 0; i < 16; i += 1) m.push(message.readUInt32LE(i * 4)); let [a,b,c,d] = start;
    const run = (kind, order, shifts, offset) => { for (let i = 0; i < 16; i += 1) { const phase = i & 3; const next = phase === 0 ? md5V3Step(kind,a,b,c,d,m[orders[offset + i]],shifts[i],sv[offset + i]) : phase === 1 ? md5V3Step(kind,d,a,b,c,m[orders[offset + i]],shifts[i],sv[offset + i]) : phase === 2 ? md5V3Step(kind,c,d,a,b,m[orders[offset + i]],shifts[i],sv[offset + i]) : md5V3Step(kind,b,c,d,a,m[orders[offset + i]],shifts[i],sv[offset + i]); if (phase === 0) a = next; else if (phase === 1) d = next; else if (phase === 2) c = next; else b = next; } };
    run(0, orders, [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22], 0);
    run(1, orders, [5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20], 16);
    run(2, orders, [4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23], 32);
    run(3, orders, [6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21], 48);
    const ret = Buffer.alloc(16); ret.writeUInt32LE(u32((start[0] + a) ^ end[0]), 0); ret.writeUInt32LE(u32((start[1] + b) ^ end[1]), 4); ret.writeUInt32LE(u32((start[2] + c) ^ end[2]), 8); ret.writeUInt32LE(u32((start[3] + d) ^ end[3]), 12); return Buffer.concat([ret, le32(sumMd5(ret))]);
}
function branch2F13(iv, querySm3, bodyMd5, tsBytes, khronos) { const v = (iv & 13) * 86; const ivV0 = ((v >>> 15) & 255) + ((v >>> 8) & 255); const n1 = [0x8980f29b,0xeb549c7f,0xb08726db,0xd40cb5e6,0xe8f559e4][ivV0]; const countV1 = (n1 + khronos + 1) & 255; const countV2 = u32(n1 + khronos); const shift = (countV2 + 5) & 7; const seed = [0x84,0x96,0x77,0x9d,0xd4,0x15,0x0b,0xf8]; const pad = Buffer.from(seed.map((value) => ((value | (value << 8)) >> shift) & 255)); const input = Buffer.concat([querySm3,bodyMd5,tsBytes,pad,Buffer.from('a0010000','hex')]); return md5SumV3(input,countV2,BRANCH2_ORDERS.subarray(ivV0 << 6,(ivV0 + 1) << 6),countV1); }
function bxor(a, b) { const out = Buffer.alloc(Math.min(a.length, b.length)); for (let i = 0; i < out.length; i += 1) out[i] = a[i] ^ b[i]; return out; }
function hashF13(querySm3, bodyMd5, tsBytes, khronos) {
    const iv = getIv(getIv(getIv(0x20230928, querySm3), bodyMd5), tsBytes); const low = iv & 15; const ivV0 = (low * 171) >> 9; const branch = low - ivV0 * 3;
    if (branch === 2) return branch2F13(iv, querySm3, bodyMd5, tsBytes, khronos);
    if (branch !== 0) return Buffer.concat([querySm3.subarray(0, 16), bodyMd5, le32(sumMd5(Buffer.concat([querySm3, bodyMd5]))) ]);
    const ivV1List = [0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1]; const ivV1 = ivV1List[ivV0]; const countV1 = (ivV1 + khronos + 1) & 255; const countV2 = u32(ivV1 + khronos);
    const tt02 = [0xebb64faf,0x7aadcc2,0xcf3187bf,0xe01138ff,0x6d0bfcff,0x5a30a3be,0xb41ad638,0x34180eb8,0xf233eb6f,0xb1a584cc,0xccc30dc7,0x47d1db51,0xd55653de,0x70a84fa1,0x57473c12,0xf76f0288,0x2c077f0a,0xda0dcad0,0xfbb86f6c,0xfdc4cf00,0x688a020d,0xe676c6a6,0x8cd6338b,0x1a3c8d0e,0xcce8b06b,0x6ad0ed0b,0xa0522717,0xdc71ac83,0x2285db71,0xd5b4dda6,0x736f8650,0x6560306c,0x617ce2a6,0xe423417e,0xa40e143,0x544e4032,0x88dffb2a,0x716c1ae0,0x4c467a88,0x5b23bb3,0xe1d0b866,0xbaa3dcb8,0xae3374d3,0xc3381a50,0x1702f75b,0xfe6da368,0xf0b4cf48,0x4e0ffbb8,0x72aad10d,0x26c53a3d,0xf2bce0f6,0xb4557581,0x4a257fdd,0x8c3182a2,0xab0b3b86,0x3d5dfb14,0x4f103634,0xd37b52d7,0x444eff16,0xeb0a33d1,0x6ca86f6e,0x284ba7,0x8387cfa,0x5fb37586];
    const tt = tt02.map((value) => ror32(value, countV1)); const n0 = (countV2 + 2) & 7; const seed = [0xfa,0x45,0x61,0xd7]; const pad = Buffer.from(seed.map((value) => ((value | (value << 8)) >> n0) & 255));
    const data = Buffer.concat([querySm3, bodyMd5, tsBytes, pad, Buffer.from('00000000000001a0','hex')]); const di = []; for (let i = 0; i < data.length; i += 4) di.push(data.readUInt32BE(i)); let di0 = di[0]; for (let i = 0; i < 112; i += 1) { const di1 = di[i + 1]; const di14 = di[i + 14]; const r1 = rol32(di1, 14) ^ rol32(di1, 25) ^ (di1 >>> 3); const r2 = rol32(di14, 13) ^ rol32(di14, 15) ^ (di14 >>> 10); di.push(u32(di0 + di[i + 9] + r1 + r2)); di0 = di1; }
    const init = [0x7aba4fc8,0x67166507,0x6403fa00,0x340f512f,984304912,3005047866,2874125293,2152413264].map((v) => ror32(v, countV2 & 31)); const chosen = [[101,5,7,6,3,2,1,0,5,4,3],[96,0,6,7,5,3,2,1,5,4,4],[96,7,6,2,1,4,0,5,4,3,5],[99,3,6,2,4,5,1,0,0,7,6],[96,0,5,6,7,3,1,2,5,4,4],[100,2,0,3,5,4,6,7,2,1,5]][ivV0]; let d = init.slice(); for (let i = 0; i < chosen[0]; i += 1) { const base = ivV1 + i; const n0v = di[base & 127]; const n1 = ((d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]]) ^ d[chosen[3]]; const n2 = rol32(d[chosen[1]],26)^rol32(d[chosen[1]],21)^rol32(d[chosen[1]],7); const n4 = u32(n0v+n1+n2+tt[base&63]+d[chosen[5]]); const n5=rol32(d[chosen[2]],30)^rol32(d[chosen[2]],19)^rol32(d[chosen[2]],10); const n6=(d[chosen[2]]&d[chosen[6]])|((d[chosen[2]]|d[chosen[6]])&d[chosen[7]]); const n7=u32(n5+n6); const old=d[chosen[9]]; d.unshift(d.pop()); d[chosen[10]]=u32(n7+n4); d[chosen[8]]=u32(old+n4); }
    const ret = Buffer.alloc(32); for (let i = 0; i < 8; i += 1) ret.writeUInt32BE(u32(d[i]+init[i]), i*4); const folded = bxor(ret.subarray(0,16), ret.subarray(16)); folded.copy(ret,0); return Buffer.concat([ret.subarray(0,16), le32(sumMd5(ret.subarray(0,16)))]);
}
function reverseBits(value) { let result = 0; for (let i = 0; i < 8; i += 1) result = (result << 1) | ((value >> i) & 1); return result; }
function rc4Gorgon(data, key) {
    const s = Array.from({ length: 256 }, (_v, i) => i); let j = 0;
    for (let i = 0; i < 256; i += 1) { j = (j + s[i] + key[i % key.length]) & 255; s[i] = s[j]; }
    let i = 0; j = 0;
    return Buffer.from(data.map((value) => { i += 1; const x = s[i]; j += x; const y = s[j & 255]; s[i] = y; return value ^ s[(y + y) & 255]; }));
}
function xGorgon(query, body, timestamp, random) {
    const sdk = Buffer.alloc(4); sdk.writeUInt32LE(67503104);
    const input = Buffer.concat([crypto.createHash('md5').update(query).digest().subarray(0, 4), body ? crypto.createHash('md5').update(body).digest().subarray(0, 4) : Buffer.alloc(4), Buffer.alloc(4), sdk, be32(timestamp)]);
    const key = [0x4a, 0x40, 0x16, (random >> 8) & 255, 0x47, 0x6c, 0x01, random & 255]; const out = rc4Gorgon([...input], key);
    for (let i = 0; i < out.length; i += 1) { let value = out[i]; value = ((value >> 4) | (value << 4)) & 255; const next = i + 1 < out.length ? out[i + 1] : out[0]; out[i] = (~(reverseBits((next ^ value) & 255) ^ 20)) & 255; }
    return Buffer.concat([Buffer.from('8404', 'hex'), Buffer.from([random & 255, (random >> 8) & 255, 0x40, 0x01]), out]).toString('hex');
}
function deviceProto(deviceId) { return proto([[1,1,'sint'],[2,2,'sint'],[3,'8662'],[4,deviceId],[5,PROCESS_NONCE],[6,'!noperm!'],[7,-888888,'sint'],[8,-888888,'sint'],[9,3,'sint'],[10,-888888,'sint'],[11,'!notset!'],[12,'Asia/Shanghai,8'],[13,'zh_CN'],[14,4,'sint'],[16,0,'float'],[17,0,'float'],[18,0,'float'],[19,0,'float'],[20,0,'float'],[21,0,'float'],[22,'16'],[23,41,'sint'],[24,36,'sint'],[25,PROCESS_STARTED,'sint'],[26,PROCESS_STARTED,'sint'],[27,PROCESS_STARTED,'sint'],[28,PROCESS_STARTED,'sint'],[29,-1,'sint'],[30,'25053RT47C'],[31,'Redmi'],[32,'25053RT47C'],[33,'25053RT47C'],[34,'Xiaomi'],[35,'Redmi'],[36,'Redmi'],[38,31,'sint']]); }
const SBOX = Buffer.from('+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==','base64');
function xorBytes(a, b) { const out = Buffer.from(a); for (let i = 0; i < out.length; i += 1) out[i] ^= b[i % b.length]; return out; }
function matrix(bytes) { return Array.from({ length: 4 }, (_v, i) => Array.from(bytes.subarray(i * 4, i * 4 + 4))); }
function flat(rows) { return Buffer.from(rows.flat()); }
function aesMix(rows) { for (let i = 0; i < 4; i += 1) { const t=rows[0][i]^rows[1][i]^rows[2][i]^rows[3][i]; const u=rows[0][i]; const xt=(x)=>((x<<1)^((x&128)?0x1b:0))&255; rows[0][i]^=t^xt(rows[0][i]^rows[1][i]); rows[1][i]^=t^xt(rows[1][i]^rows[2][i]); rows[2][i]^=t^xt(rows[2][i]^rows[3][i]); rows[3][i]^=t^xt(rows[3][i]^u); } }
class AesV3 {
    constructor(key, khronos) { this.wordSize=khronos&3; this.box=SBOX.subarray(this.wordSize*256,(this.wordSize+1)*256); this.con=[[1,0,2,3],[1,3,0,2],[0,1,3,2],[1,0,2,3]][this.wordSize]; this.con2=[[1,0,2,3],[2,0,3,1],[0,1,3,2],[1,0,2,3]][this.wordSize]; this.order=[[0,9,14,11,4,13,2,7,8,1,6,15,12,5,10,3],[0,9,14,15,4,13,2,7,8,1,6,3,12,5,10,11],[0,9,14,7,4,13,2,11,8,1,6,3,12,5,10,15],[0,9,14,11,4,13,2,7,8,1,6,15,12,5,10,3]][this.wordSize]; const init=[0xca025ddc,0x823dc546,0xc9420583,0xc298225f][this.wordSize]; const initial=Buffer.alloc(16); for(let i=0;i<4;i+=1)initial.writeUInt32LE(init,i*4); const mk=xorBytes(initial,key); const expanded=Buffer.concat([mk,Buffer.alloc(32)]); let rounds=8; for(let i=4;i<12;i+=1){let at=4*(i-1);let a=expanded[at],b=expanded[at+1],c=expanded[at+2],d=expanded[at+3];if((i&3)===0){const t=(u32(init>>((rounds&24)))^this.box[b])&255;b=this.box[c];c=this.box[d];d=this.box[a];a=t;}rounds+=2;expanded[at+4]=a^expanded[at-12];expanded[at+5]=b^expanded[at-11];expanded[at+6]=c^expanded[at-10];expanded[at+7]=d^expanded[at-9];} this.keys=Array.from({length:12},(_v,i)=>Array.from(expanded.subarray(i*4,i*4+4))); }
    add(rows,key) { for(let i=0;i<4;i+=1) for(let j=0;j<4;j+=1) rows[i][j]^=key[i][j]; }
    addCon(rows, keys) { for(let i=0;i<4;i+=1) for(let j=0;j<4;j+=1) rows[i][j]^=keys[i][this.con2[j]]; }
    sub(rows) { for(let i=0;i<4;i+=1) for(let j=0;j<4;j+=1) rows[i][j]=this.box[rows[i][j]]; const old=rows.map((x)=>x.slice()); for(let i=0;i<4;i+=1) rows[i]=old[this.con2[i]]; }
    shift(rows) { const b=flat(rows); for(let i=0;i<16;i+=1) rows[Math.floor(i/4)][i%4]=b[this.order[i]]; }
    shiftCon(rows) { const old=rows.map((x)=>x.slice()); for(let i=0;i<4;i+=1) rows[i]=this.con2.map((x)=>old[i][x]); }
    block(value) { const rows=matrix(value); this.addCon(rows,this.keys.slice(0,4)); for(let i=1;i<3;i+=1){this.sub(rows);this.shift(rows);if(i===1){this.shiftCon(rows);aesMix(rows);}this.addCon(rows,this.keys.slice(i*4));}this.add(rows,this.keys.slice(4));return flat(rows); }
    encrypt(data, iv) { const source=Buffer.from(data); const plaintext=Buffer.alloc(32); for(let i=0;i<31;i+=1){const at=i*8;const n0=(source[at]>>4)&2;const n1=n0|(source[at+1]&64);const n2=n1|((source[at+2]>>2)&1);const n3=n2|((source[at+3]<<3)&128);const n4=n3|((source[at+4]>>1)&4);const n5=n4|((source[at+5]<<3)&16);const n6=n5|((source[at+6]<<5)&32);plaintext[i]=n6|((source[at+7]>>4)&8);} plaintext[31]=1; const blocks=[]; let previous=Buffer.from(iv); for(let i=0;i<plaintext.length;i+=16){const value=this.block(xorBytes(plaintext.subarray(i,i+16),previous));blocks.push(value);previous=value;} const key=Buffer.concat(blocks); const out=Buffer.from(source); for(let i=0;i<31;i+=1){const at=i*8; const k=key[i]; out[at]&=0xdf;out[at]|=(k<<4)&32;out[at+1]&=0xbf;out[at+1]|=k&64;out[at+2]&=0xfb;out[at+2]|=(k<<2)&4;out[at+3]&=0xef;out[at+3]|=(k>>3)&16;out[at+4]&=0xf7;out[at+4]|=(k+k)&8;out[at+5]&=0xfd;out[at+5]|=(k>>3)&2;out[at+6]&=0xfe;out[at+6]|=(k>>5)&1;out[at+7]&=0x7f;out[at+7]|=(k<<4)&128;} return Buffer.concat([key.subarray(-1),out]); }
}
function xmxor(data, key) { const encoded=Buffer.alloc(data.length); for(let i=0;i<data.length;i+=1){const at=(i*4)&28;const d0=key[at],d1=key[at+1];let d2=((((data[i]<<4)|(data[i]>>>4))&255)+d0);d2=(~d2)^d1;d2=((((d2&255)<<3)|((d2&255)>>>5))&255);d2=(d2+d1)&255;d2=(d2^d0)&255;encoded[data.length-i-1]=(~d2)&255;} let last=encoded[encoded.length-1]^encoded[encoded.length-2];const first=encoded[0];encoded[0]=(~last+first)&255;encoded[1]=((encoded[0]^encoded[encoded.length-1]^254)+encoded[1])&255;encoded[2]=(encoded[2]+((last-first)^(((encoded[1]<<3)|(encoded[1]>>>5))&255)^2))&255;for(let i=0;i<encoded.length-4;i+=1){const temp=(((encoded[i+2]<<3)|(encoded[i+2]>>>5))&255)^encoded[i+1]^(i+3);encoded[i+3]=(~temp+encoded[i+3])&255;}encoded[encoded.length-1]^=encoded[encoded.length-2];let sum=0;for(let i=0;i<encoded.length-1;i+=1)sum+=encoded[i+1];encoded[0]=((encoded[0]^encoded[1])+sum)&255;return encoded; }
function keyHash(signKey, random) { const input=Buffer.concat([signKey,le32(random),signKey]); const hash=sm3(input); const d1=(random>>16)&255; let d2=((d1<<11)|(random>>>24))^(d1>>5)^d1; d2=(~d2)>>>0; return [hash,le32(d2)]; }
function buildMedusa(url, body, khronos, device) {
    const bodyMd5=body?crypto.createHash('md5').update(body).digest():Buffer.alloc(16); const querySm3=sm3(url.split('?')[1]); const ts=le32(khronos); const queryBodyTs=hashF13(querySm3,bodyMd5,ts,khronos); const nested=proto([[1,111,'sint'],[2,10,'sint'],[3,694367,'sint'],[5,586952199,'sint']]); const messageRand=Math.floor(Math.random()*0x100000000); const envLaunch=Math.floor(Math.random()*21)+100; const envPid=Math.floor(Math.random()*2000)+10001; const env=proto([[1,envLaunch,'sint'],[2,146331399,'sint'],[3,146331396,'sint'],[5,7,'sint'],[6,'v04.06.04.03-bugfix'],[7,envPid,'sint'],[12,deviceProto(device.device_id),'message'],[13,proto([[1,Math.floor(Date.now()/1000),'sint'],[2,-2,'sint'],[4,200,'sint']]),'message'],[14,device.version_name]]); const queryHash=sm3(Buffer.concat([Buffer.from(url.split('?')[1]),bodyMd5,Buffer.from('none')])); const message=proto([[1,Buffer.from('f7e85ffad7d7dc3bd62ac87057cf6118','hex'),'bytes'],[2,3,'sint'],[3,messageRand,'sint'],[4,'8662'],[5,device.device_id],[6,'1588093228'],[7,device.version_name],[8,'v04.06.04-ml-android'],[9,67503104,'sint'],[10,Buffer.from('4001000000000000','hex'),'bytes'],[12,khronos,'sint'],[13,queryBodyTs,'bytes'],[14,querySm3.subarray(0,6),'bytes'],[15,nested,'message'],[16,PROCESS_NONCE],[17,khronos,'sint'],[19,queryHash,'bytes'],[20,'none'],[21,312,'sint'],[23,env,'message'],[24,'{\"cmr\":16777216,\"cmr2\":16777216,\"un_h\":1879194040,\"vpn\":0,\"kd\":0,\"fkd\":3672518972,\"pd\":-1872573247,\"dyn\":\"\",\"do\":0,\"tk\":true}']]); const random=Math.floor(Math.random()*0x100000000); const [hash,seed]=keyHash(Buffer.from('8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eae f71cb691f7aa8aa2f5'.replace(/ /g,''),'hex'),random); let transformed=xmxor(message,hash); transformed=Buffer.concat([Buffer.from('4001000000000000','hex'),transformed]).reverse(); for(let i=0;i<transformed.length;i+=1)transformed[i]^=seed[(~i)&3]; const check=((querySm3[0]&63)<<14)|0x18000001|((queryBodyTs[0]&63)<<8); const xmRand=Math.floor(Math.random()*0x100000000); const packed=Buffer.concat([Buffer.from([0x35]),le32(xmRand),le32(check),transformed,Buffer.from([random>>16,random>>24])]); const encrypted=new AesV3(Buffer.from('f1593376766ea98d34f31b057a9d5be4','hex'),khronos).encrypt(packed,Buffer.from('1fe109a4125283f418de9e051a969e12','hex')); const version=Buffer.from('03000000f7e85ffad7d7dc3bd62ac87057cf6118','hex'); const prefix=Buffer.alloc(20); for(let i=0;i<20;i+=4) prefix.writeUInt32LE(u32(version.readUInt32LE(i)^khronos),i); return Buffer.concat([prefix,Buffer.from([random&255,(random>>8)&255,0,1]),encrypted]).toString('base64');
}
function helios(khronos) {
    const random = Math.floor(Math.random() * 0x100000000); const data = Buffer.concat([le32(random), Buffer.from('8662')]); const digest = crypto.createHash('md5').update(data).digest(); const ascii = Buffer.from(digest.toString('hex'), 'ascii'); const words = [];
    for (let i = 0; i < 4; i += 1) words.push(ascii.readBigUInt64LE(i * 8)); const table = [words[0]]; let b0 = words[0]; let b8 = words[1]; words.splice(0, 2);
    for (let i = 0; i < 34; i += 1) { let x8 = uint64( ror64(b8, 8) + b0); x8 = uint64( x8 ^ BigInt(i)); words.push(x8); x8 = uint64( x8 ^ ror64(b0, 61)); table.push(x8); b0 = x8; b8 = words.shift(); }
    const text = Buffer.from(`${khronos}-1588093228-8662`); const pad = Buffer.alloc(Math.ceil((text.length + 1) / 16) * 16, 16 - (text.length % 16)); text.copy(pad); const output = [];
    for (let at = 0; at < pad.length; at += 16) { let a = pad.readBigUInt64LE(at); let b = pad.readBigUInt64LE(at + 8); for (let i = 0; i < 34; i += 1) { b = uint64( table[i] ^ (a + ror64(b, 8))); a = uint64( b ^ ror64(a, 61)); } const block = Buffer.alloc(16); block.writeBigUInt64LE(a); block.writeBigUInt64LE(b, 8); output.push(block); }
    return Buffer.concat([le32(random), ...output]).toString('base64');
}

function branchOf(url, body, khronos) { const bodyMd5 = body ? crypto.createHash('md5').update(body).digest() : Buffer.alloc(16); const q = sm3(url.split('?')[1]); const iv = getIv(getIv(getIv(0x20230928, q), bodyMd5), le32(khronos)); const low = iv & 15; return low - (((low * 171) >> 9) * 3); }
function playbackRequest(payload, identity, apiBase = VIDEO_API) {
    // v04.10.03 mobile playback signing. The v3 medusa is rejected with an empty
    // HTTP 200 by the current player endpoint; v5 binds the registered device
    // identity into both the query and the medusa plaintext. Search/catalogue
    // endpoints still use the legacy v3 signer elsewhere in this module.
    const body = gzipSync(Buffer.from(payload));
    const { device_id, iid, cdid } = identity || {};
    const values = {
        ...V5_PLAYBACK_QUERY,
        iid: iid || '', cdid: cdid || '', device_id: device_id || '',
    };
    const { url, headers: signedHeaders } = signPlaybackV5(apiBase, values, body);
    const headers = {
        'User-Agent': V5_PLAYBACK_UA, Accept: 'application/json',
        'Content-Encoding': 'gzip',
        ...signedHeaders,
    };
    // The transport supplies cookies scoped to the destination from the active session.
    return { url, body, headers };
}

function shortplayRequest(vid, identity, apiBase = SHORTPLAY_API) {
    const khronos = Math.floor(Date.now() / 1000);
    const query = pythonUrlEncode({
        iid: identity?.iid || '',
        device_id: identity?.device_id || '',
        aid: '1967',
        app_name: 'novelapp',
        version_code: '72132',
        version_name: '7.2.1.32',
        device_platform: 'android',
        device_brand: 'Xiaomi',
        os_version: '13',
        cdid: identity?.cdid || '',
    });
    const url = `${apiBase}?${query}`;
    const payload = JSON.stringify({
        video_id: String(vid),
        content_type: 1004,
        biz_param: {
            detail_page_version: 0, device_level: 3, disable_digg_stat: false, disable_video_relate_book: false,
            from_video_id: '', need_all_video_definition: true, need_mp4_align: false, source: 4,
            use_os_player: false, use_server_dns: false, video_platform: 3,
        },
    });
    const body = Buffer.from(payload);
    const signerHeaders = PlayerSigner.headers(query, body, khronos);
    const headers = {
        'User-Agent': 'com.dragon.read',
        'Content-Type': 'application/json; charset=utf-8',
        ...signerHeaders,
    };
    // Session cookies are added by requestJson after domain/path/expiry checks.
    return { url, body, headers };
}

function parseSearchInteger(value) {
    if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value.trim()))) return null;
    const number = Number(value);
    return Number.isSafeInteger(number) && number >= 0 ? number : null;
}
function signedSearchRequest({ keyword, page = 1, cursor = null, identity } = {}) {
    const pg = parseSearchInteger(page);
    if (pg === null || pg < 1 || pg > 50) throw Object.assign(new Error('App 搜索页码需为 1 至 50 的整数'), { code: 'APP_INPUT' });
    if (![identity?.device_id, identity?.iid].every(value => typeof value === 'string' && /^\d{1,30}$/.test(value) && /[1-9]/.test(value))
        || typeof identity?.cdid !== 'string' || !/^[a-f0-9-]{36}$/i.test(identity.cdid)) {
        throw Object.assign(new Error('App 搜索设备身份无效'), { code: 'APP_INPUT' });
    }
    // Search uses the hongguoTV 7.2.2.32 profile and only hash branch 0.
    const device = { ...DEVICE, version_code: '72232', version_name: '7.2.2.32', manifest_version_code: '72232',
        update_version_code: '72232', pv_player: '72232', iid: identity.iid, device_id: identity.device_id, cdid: identity.cdid };
    const khronos = Math.floor(Date.now() / 1000), ticketBase = Date.now();
    const base = { ...device, query: String(keyword || '').slice(0, 80), count: '20', tab_type: '11',
        bookshelf_search_plan: '4', use_correct: 'true', user_is_login: '0' };
    if (cursor?.search_id) base.search_id = cursor.search_id;
    if (cursor?.passback) base.passback = cursor.passback;
    const offset = parseSearchInteger(cursor?.next_offset) ?? (pg - 1) * 20;
    base.offset = String(offset);
    let requestTicket = ticketBase, query = '', url = '';
    for (let n = 0; n < 128; n += 1) {
        requestTicket = ticketBase + n;
        query = pythonUrlEncode({ ...base, ts: String(khronos), _rticket: String(requestTicket) });
        url = `${SEARCH_API}?${query}`;
        if (branchOf(url, null, khronos) === 0) break;
        if (n === 127) throw new Error('无法生成搜索请求签名');
    }
    const random = Math.floor(Math.random() * 65536);
    const headers = {
        'User-Agent': SEARCH_UA, Accept: 'application/json; charset=utf-8,application/x-protobuf',
        'x-ss-req-ticket': String(requestTicket), 'x-tt-request-tag': 't=0;n=0', 'sdk-version': '2',
        'passport-sdk-version': '50561', 'x-xs-from-web': '0', 'x-khronos': String(khronos),
        'x-ladon': be32(khronos).toString('base64'), 'x-argus': le32(khronos).toString('base64'),
        'x-gorgon': xGorgon(query, null, khronos, random), 'x-helios': helios(khronos),
        'x-medusa': buildMedusa(url, null, khronos, device), 'x-tt-dt': '',
    };
    return { url, headers };
}

// Catalogue cursors belong to one anonymous identity; keep it in memory for this process only.
const metadataDevice = { ...DEVICE, version_code: '73532', version_name: '7.3.5.32', manifest_version_code: '73532',
    update_version_code: '73532', pv_player: '73532', iid: localId(), device_id: localId() };
function getActiveMetadataDevice() {
    const current = typeof getPlaybackDevice.getCurrentDevice === 'function' ? getPlaybackDevice.getCurrentDevice() : null;
    if (current?.device_id && current?.iid) {
        return {
            ...DEVICE,
            version_code: '73532',
            version_name: '7.3.5.32',
            manifest_version_code: '73532',
            update_version_code: '73532',
            pv_player: '73532',
            iid: current.iid,
            device_id: current.device_id,
            cdid: current.cdid || metadataDevice.cdid,
        };
    }
    return metadataDevice;
}
function signedMetadataRequest(apiPath, values = {}, payload = null) {
    if (!['/reading/distribution/category/landpage/v/', '/reading/bookapi/bookmall/cell/change/v', '/reading/user/celebrity/homepage/v1/', '/reading/user/celebrity/works/v1/'].includes(apiPath)) {
        throw new Error('不支持的 App 目录接口');
    }
    const targetDevice = getActiveMetadataDevice();
    const body = payload === null ? null : Buffer.from(JSON.stringify(payload));
    const khronos = Math.floor(Date.now() / 1000), ticketBase = Date.now();
    let query, url, requestTicket;
    for (let n = 0; n < 128; n += 1) {
        requestTicket = ticketBase + n;
        query = pythonUrlEncode({ ...values, ...targetDevice, ts: String(khronos), _rticket: String(requestTicket) });
        url = `https://api5-normal-sinfonlineb.fqnovel.com${apiPath}?${query}`;
        if (branchOf(url, body, khronos) === 0) break;
        if (n === 127) throw new Error('无法生成 App 目录请求签名');
    }
    const headers = {
        'User-Agent': VIDEO_UA.replace('71332', '73532'), Accept: 'application/json', 'Accept-Encoding': 'identity',
        'x-xs-from-web': '0', 'sdk-version': '2', 'x-ss-dp': '8662', 'x-tt-store-region': 'cn', 'x-tt-store-region-src': 'did',
        'x-ss-req-ticket': String(requestTicket), 'x-khronos': String(khronos),
        'x-gorgon': xGorgon(query, body, khronos, Math.floor(Math.random() * 65536)),
        'x-ladon': be32(khronos).toString('base64'), 'x-argus': le32(khronos).toString('base64'),
        'x-helios': helios(khronos), 'x-medusa': buildMedusa(url, body, khronos, targetDevice), 'x-tt-dt': '',
    };
    if (body) { headers['Content-Type'] = 'application/json; charset=utf-8'; headers['x-ss-stub'] = md5(body); }
    return { url, headers, body };
}


module.exports={signedMetadataRequest,signedSearchRequest};

},
"./register":function(module,exports,require,process){
// SPDX-License-Identifier: GPL-3.0-only
const crypto=require('node:crypto');const {gzipSync}=require('node:zlib');
const REGISTER_URL = 'https://log5-applog-lf.fqnovel.com/service/2/device_register/?tt_data=a&cronet_version=8d40f833_2026-03-03&ttnet_version=4.2.243.31-douyin&use_store_region_cookie=1';
const KDF_SALT = Buffer.from('4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58', 'hex');
const PLAYBACK_UA = 'com.phoenix.read/74332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)';
function createRegistrationRequest() {
    const now = Date.now();
    const cdid = crypto.randomUUID();
    const header = {
        display_name: '红果免费短剧', update_version_code: 74332, manifest_version_code: 74332,
        app_version_minor: '7.4.3.32', aid: 8662, channel: 'update_64', package: 'com.phoenix.read',
        app_version: '7.4.3.32', version_code: 74332, sdk_version: '3.7.0-rc.34-fanqie-xiaoshuo',
        sdk_target_version: 29, git_hash: '3a88f4e', os: 'Android', os_version: '16', os_api: 36,
        device_model: '25053RT47C', device_brand: 'Redmi', device_manufacturer: 'Redmi',
        cpu_abi: 'arm64-v8a', release_build: 'b5e187f', density_dpi: 520, display_density: 'mdpi',
        resolution: '1280x2772', language: 'zh', timezone: 8, access: 'wifi', not_request_sender: 0,
        carrier: 'CHINA MOBILE', mcc_mnc: '46000', rom: 'eng.root.20231116.160340',
        rom_version: 'W528JS release-keys', cdid,
        sig_hash: '56a962410c494bbaf0b58dba20cae56f', openudid: crypto.randomBytes(8).toString('hex'),
        clientudid: crypto.randomUUID(), ipv6_list: [], region: 'CN', tz_name: 'Asia/Shanghai',
        tz_offset: 28800, sim_region: 'cn', sim_serial_number: [], oaid_may_support: false,
        req_id: crypto.randomUUID(), device_platform: 'android',
        custom: { account_region_src: 'fallback', account_region: 'cn', host_bit: 64, dragon_device_type: 'phone' }, pre_installed_channel: '',
        apk_first_install_time: now, is_system_app: 0, sdk_flavor: 'china', guest_mode: 0,
    };
    const compressed = gzipSync(Buffer.from(JSON.stringify({ magic_tag: 'ss_app_log', header, _gen_time: now })));
    const random = crypto.randomBytes(32);
    const derived = crypto.createHash('sha512').update(Buffer.concat([
        crypto.createHash('sha512').update(random).digest(), KDF_SALT,
    ])).digest();
    const cipher = crypto.createCipheriv('aes-128-cbc', derived.subarray(0, 16), derived.subarray(16, 32));
    const plaintext = Buffer.concat([crypto.createHash('sha512').update(compressed).digest(), compressed]);
    const data = Buffer.concat([Buffer.from('746305100000', 'hex'), random, cipher.update(plaintext), cipher.final()]);
    const options = {
        method: 'POST',
        headers: {
            'User-Agent': PLAYBACK_UA,
            Accept: 'application/json', 'Content-Type': 'application/octet-stream;tt-data=a',
            'log-encode-type': 'gzip', 'x-ss-dp': '8662', 'x-ss-req-ticket': String(now),
            'x-vc-bdturing-sdk-version': '4.0.3.cn', lc: '101', 'sdk-version': '2',
            'passport-sdk-version': '5051452', 'x-neptune': '-8|50:51:59:30:40:47:49:39',
            'x-ss-stub': crypto.createHash('md5').update(data).digest('hex').toUpperCase(),
        },
        data,
    };
    return { options, cdid };
}


module.exports={createRegistrationRequest,REGISTER_URL};

},
"./mp4":function(module,exports,require,process){
// SPDX-License-Identifier: GPL-3.0-only
function parseBoxes(data, start, end, depth = 0) {
  if (depth > 32) throw new Error('MP4 box nesting exceeds limit');
  const boxes = [];
  let off = start;
  while (off + 8 <= end) {
    let size = data.readUInt32BE(off);
    const typ = data.subarray(off + 4, off + 8).toString('latin1');
    let hdr = 8;
    if (size === 1) {
      if (off + 16 > end) throw new Error('Truncated MP4 box header');
      size = Number(data.readBigUInt64BE(off + 8));
      hdr = 16;
    } else if (size === 0) {
      size = end - off;
    }
    if (!Number.isSafeInteger(size) || size < hdr || off + size > end) throw new Error('Invalid MP4 box size');
    let children = null;
    if (['moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'dinf', 'udta'].includes(typ)) {
      children = parseBoxes(data, off + hdr, off + size, depth + 1);
    }
    boxes.push({ typ, off, size, hdr, children });
    off += size;
  }
  if (off !== end) throw new Error('Truncated MP4 box');
  return boxes;
}

/**
 * 重建 moov box
 */
function rebuildMoov(data, moovOff, moovSize, top, order = top, relocate) {
  const moovBox = top.find(b => b.typ === 'moov');
  if (!moovBox) throw new Error('no moov box');

  function clone(box) {
    return {
      typ: box.typ,
      off: box.off,
      size: box.size,
      hdr: box.hdr,
      children: box.children ? box.children.map(clone) : null
    };
  }

  function prune(box) {
    if (!box.children) return box;
    const keep = [];
    for (const c of box.children) {
      if (['senc', 'saio', 'saiz', 'sgpd', 'sbgp'].includes(c.typ)) continue;
      keep.push(prune(c));
    }
    box.children = keep;
    return box;
  }

  const tree = prune(clone(moovBox));

  function* walkChildren(box) {
    for (const c of (box.children || [])) {
      yield c;
      for (const x of walkChildren(c)) yield x;
    }
  }

  const patches = {};
  for (const b of walkChildren(tree)) {
    if (b.typ === 'stsd') {
      const content = b.off + 8;
      const count = data.readUInt32BE(content + 4);
      let p = content + 8;
      const entries = [];
      for (let i = 0; i < count; i++) {
        let esize = data.readUInt32BE(p);
        const etyp = data.subarray(p + 4, p + 8).toString('latin1');
        if (etyp === 'encv' || etyp === 'enca') {
          const hdrSize = etyp === 'encv' ? 78 : 28;
          const children = parseBoxes(data, p + 8 + hdrSize, p + esize);
          let newType;
          if (etyp === 'enca') {
            if (data.readUInt16BE(p + 16) !== 0) throw new Error('Unsupported audio sample entry version');
            const sinf = children.find(child => child.typ === 'sinf');
            const frma = sinf && parseBoxes(data, sinf.off + sinf.hdr, sinf.off + sinf.size).find(child => child.typ === 'frma');
            newType = frma && frma.size === frma.hdr + 4 ? data.toString('latin1', frma.off + frma.hdr, frma.off + frma.hdr + 4) : null;
            if (!['mp4a', 'ac-3', 'ec-3', 'Opus', 'fLaC'].includes(newType)) throw new Error('Unsupported protected audio codec');
          }
          if (etyp === 'encv') {
            const sinf = children.find(child => child.typ === 'sinf');
            const frma = sinf && parseBoxes(data, sinf.off + sinf.hdr, sinf.off + sinf.size).find(child => child.typ === 'frma');
            const original = frma && frma.size === frma.hdr + 4
              ? data.toString('latin1', frma.off + frma.hdr, frma.off + frma.hdr + 4) : null;
            const avc = children.some(child => child.typ === 'avcC');
            const hevc = children.some(child => child.typ === 'hvcC');
            newType = original || (avc && !hevc ? 'avc1' : hevc && !avc ? 'hvc1' : null);
            if (!['avc1', 'avc3', 'hvc1', 'hev1'].includes(newType)
              || (newType.startsWith('avc') ? !avc || hevc : !hevc || avc)) {
              throw new Error('无法确定加密视频的原始编码（codec），请更换片源重试。');
            }
          }
          const entry = Buffer.alloc(8 + hdrSize);
          entry.writeUInt32BE(0, 0);
          entry.write(newType, 4, 4, 'latin1');
          data.copy(entry, 8, p + 8, p + 8 + hdrSize);

          const entryExtra = Buffer.concat(children.filter(child => child.typ !== 'sinf')
            .map(child => data.subarray(child.off, child.off + child.size)));
          const fullEntry = Buffer.concat([entry, entryExtra]);
          fullEntry.writeUInt32BE(fullEntry.length, 0);
          entries.push(fullEntry);
        } else {
          entries.push(data.subarray(p, p + esize));
        }
        p += esize;
      }
      const stsdHdr = Buffer.alloc(16);
      data.copy(stsdHdr, 0, b.off, content + 8);
      stsdHdr.writeUInt32BE(entries.length, 12);
      const fullStsd = Buffer.concat([stsdHdr, ...entries]);
      fullStsd.writeUInt32BE(fullStsd.length, 0);
      patches[b.off] = fullStsd;
    }
  }

  function serialize(box) {
    if (!box.children) {
      return patches[box.off] || data.subarray(box.off, box.off + box.size);
    }
    const body = Buffer.concat(box.children.map(serialize));
    const hdrb = Buffer.alloc(box.hdr);
    data.copy(hdrb, 0, box.off, box.off + box.hdr);
    if (box.hdr === 8) {
      hdrb.writeUInt32BE(8 + body.length, 0);
    } else {
      hdrb.writeUInt32BE(1, 0);
      hdrb.writeBigUInt64BE(BigInt(16 + body.length), 8);
    }
    return Buffer.concat([hdrb, body]);
  }

  const first = serialize(tree);
  const destinations = new Map();
  let destination = 0;
  for (const box of order) {
    destinations.set(box.off, destination);
    destination += box.typ === 'moov' ? first.length : box.size;
  }
  for (const b of walkChildren(tree)) {
    if (b.typ === 'stco' || b.typ === 'co64') {
      const count = data.readUInt32BE(b.off + b.hdr + 4);
      const stride = b.typ === 'co64' ? 8 : 4;
      if (b.hdr + 8 + count * stride > b.size) throw new Error('Invalid MP4 chunk table');
      for (let i = 0; i < count; i++) {
        const position = b.off + b.hdr + 8 + i * stride;
        const old = stride === 8 ? Number(data.readBigUInt64BE(position)) : data.readUInt32BE(position);
        if (relocate) {
          const updated = relocate(old, first.length);
          if (stride === 8) data.writeBigUInt64BE(BigInt(updated), position);
          else data.writeUInt32BE(updated, position);
          continue;
        }
        const source = top.find(box => old >= box.off && old < box.off + box.size);
        if (!Number.isSafeInteger(old) || !source) throw new Error('Invalid MP4 chunk offset');
        const updated = old + destinations.get(source.off) - source.off;
        if (stride === 8) data.writeBigUInt64BE(BigInt(updated), position);
        else data.writeUInt32BE(updated, position);
      }
    }
  }

  return serialize(tree);
}

function mp4TrackInfo(data, top, total) {
  const getBox = (boxes, type) => (boxes || []).find(box => box.typ === type);
  function* walkBoxes(boxes) {
    for (const box of boxes) { if (box.children) yield* walkBoxes(box.children); yield box; }
  }
  if (top.some(box => box.typ === 'moof')) throw new Error('Fragmented MP4 is not supported');
  const stbls = Array.from(walkBoxes(top)).filter(b => b.typ === 'stbl');
  const trackInfo = [];
  let sampleBudget = 0;
  for (const stbl of stbls) {
    const stsz = getBox(stbl.children, 'stsz');
    const stco = getBox(stbl.children, 'stco') || getBox(stbl.children, 'co64');
    const stsc = getBox(stbl.children, 'stsc');
    const senc = getBox(stbl.children, 'senc');
    const stsd = getBox(stbl.children, 'stsd');
    let encrypted = false;
    if (stsd) {
      let cursor = stsd.off + 16;
      const count = data.readUInt32BE(stsd.off + 12);
      for (let i = 0; i < count; i++) {
        if (cursor + 8 > stsd.off + stsd.size) throw new Error('Truncated MP4 sample description');
        const size = data.readUInt32BE(cursor);
        if (size < 8 || cursor + size > stsd.off + stsd.size) throw new Error('Invalid MP4 sample description');
        const type = data.toString('latin1', cursor + 4, cursor + 8);
        encrypted ||= type === 'encv' || type === 'enca';
        cursor += size;
      }
    }
    if (encrypted && (!stsz || !stco || !stsc || !senc)) throw new Error('Unsupported encrypted MP4 track layout');
    if (!stsz || !stco || !stsc) continue;

    const ss = data.readUInt32BE(stsz.off + 12);
    const n = data.readUInt32BE(stsz.off + 16);
    sampleBudget += n;
    if (sampleBudget > 100000) throw new Error('MP4 sample count exceeds budget');
    if (n > 100000 || (ss === 0 && 20 + n * 4 > stsz.size)) throw new Error('Invalid MP4 sample sizes');
    let sizes = [];
    if (ss === 0) {
      for (let i = 0; i < n; i++) {
        sizes.push(data.readUInt32BE(stsz.off + 20 + i * 4));
      }
    } else {
      sizes = new Array(n).fill(ss);
    }

    const nc = data.readUInt32BE(stco.off + 12);
    const chunkStride = stco.typ === 'co64' ? 8 : 4;
    if (16 + nc * chunkStride > stco.size) throw new Error('Invalid MP4 chunk offsets');
    const chunkOffs = [];
    for (let i = 0; i < nc; i++) {
      const position = stco.off + 16 + i * chunkStride;
      const offset = chunkStride === 8 ? Number(data.readBigUInt64BE(position)) : data.readUInt32BE(position);
      if (!Number.isSafeInteger(offset)) throw new Error('Unsafe MP4 chunk offset');
      chunkOffs.push(offset);
    }

    const ns = data.readUInt32BE(stsc.off + 12);
    if (16 + ns * 12 > stsc.size) throw new Error('Invalid MP4 sample-to-chunk table');
    const stscTab = [];
    for (let i = 0; i < ns; i++) {
      stscTab.push([
        data.readUInt32BE(stsc.off + 16 + i * 12),
        data.readUInt32BE(stsc.off + 20 + i * 12),
        data.readUInt32BE(stsc.off + 24 + i * 12),
      ]);
    }

    const ivs = [];
    if (senc) {
      const sc = data.readUInt32BE(senc.off + 12);
      if (data.readUInt32BE(senc.off + 8) !== 0 || sc !== n || senc.size !== 16 + sc * 8) {
        throw new Error('Unsupported CENC encryption layout (requires full samples and 8-byte IVs)');
      }
      for (let i = 0; i < sc; i++) {
        ivs.push(data.subarray(senc.off + 16 + i * 8, senc.off + 24 + i * 8));
      }
    }

    if (!senc && stbl.children.some(box => ['saio', 'saiz'].includes(box.typ))) throw new Error('Unsupported external CENC auxiliary data');
    if (n > 0 && (!stscTab.length || stscTab[0][0] !== 1)) throw new Error('Invalid first MP4 chunk');
    for (let i = 0; i < stscTab.length; i++) {
      const [first, samples] = stscTab[i];
      if (first < 1 || first > nc || samples < 1 || samples > n || (i && first <= stscTab[i - 1][0])) throw new Error('Invalid MP4 chunk mapping');
    }
    const chunkSpc = {};
    for (let i = 0; i < stscTab.length; i++) {
      const fc = stscTab[i][0];
      const spc = stscTab[i][1];
      const nxt = (i + 1 < stscTab.length) ? stscTab[i + 1][0] : (nc + 1);
      for (let ci = fc - 1; ci < nxt - 1; ci++) {
        chunkSpc[ci] = spc;
      }
    }

    const sampleOffs = [];
    let si = 0;
    for (let ci = 0; ci < nc; ci++) {
      let off = chunkOffs[ci];
      const spc = chunkSpc[ci] || 1;
      for (let s = 0; s < spc; s++) {
        if (si >= n) break;
        sampleOffs.push(off);
        off += sizes[si];
        si++;
      }
    }

    if (si !== n) throw new Error('MP4 sample-to-chunk count mismatch');
    trackInfo.push({ sizes, offs: sampleOffs, ivs, stco, encrypted });
  }

  return trackInfo;
}

function hasSampleEncryption(boxes) {
  return boxes.some(box => box.typ === 'senc' || (box.children && hasSampleEncryption(box.children)));
}

function createMp4StreamingPlan(metadata, boxes, total) {
  if (boxes.some(box => box.typ === 'moof')) throw new Error('Fragmented MP4 is not supported');
  const localBoxes = parseBoxes(metadata, 0, metadata.length);
  const moov = boxes.find(box => box.typ === 'moov');
  const order = boxes.filter(box => box !== moov);
  const firstMedia = order.findIndex(box => box.typ === 'mdat');
  if (!moov || firstMedia < 0) throw new Error('MP4 requires moov and mdat');
  order.splice(firstMedia, 0, moov);
  const tracks = mp4TrackInfo(metadata, localBoxes, total);
  const relocate = (offset, moovSize) => {
    if (!Number.isSafeInteger(offset)) throw new Error('Unsafe MP4 offset');
    let destination = 0;
    for (const box of order) {
      if (box.typ !== 'moov' && offset >= box.off && offset < box.off + box.size) return destination + offset - box.off;
      destination += box.typ === 'moov' ? moovSize : box.size;
    }
    throw new Error('MP4 offset outside media');
  };
  const rebuilt = rebuildMoov(metadata, 0, metadata.length, localBoxes, localBoxes, relocate);
  let size = 0;
  const segments = order.map(box => {
    const segment = { start: size, size: box.typ === 'moov' ? rebuilt.length : box.size,
      ...(box.typ === 'moov' ? { buffer: rebuilt } : { remote: box.off }) };
    size += segment.size;
    return segment;
  });
  const samples = tracks.flatMap(track => track.ivs.map((iv, index) => ({ offset: track.offs[index], size: track.sizes[index], iv })))
    .sort((a, b) => a.offset - b.offset);
  if (samples.length > 100000) throw new Error('MP4 sample count exceeds streaming budget');
  for (const sample of samples) if (!Number.isSafeInteger(sample.offset) || sample.offset + sample.size > total) throw new Error('Invalid encrypted MP4 sample');
  return { size, segments, samples, encrypted: hasSampleEncryption(localBoxes) || tracks.some(track => track.encrypted || track.ivs.length) };
}


module.exports={createMp4StreamingPlan};

}
};
const SITE='https://hongguoduanju.com',META='https://api5-normal-sinfonlineb.fqnovel.com';
const VIDEO_APIS=['https://reading.snssdk.com/novel/player/multi_video_model/player/v1','https://api5-normal-sinfonlinea.fqnovel.com/novel/player/multi_video_model/player/v1','https://api5-normal-lq.fqnovel.com/novel/player/multi_video_model/player/v1'];
const UA='Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/122.0.0.0 Mobile Safari/537.36';
const MEDIA_UA='com.phoenix.read/73932 (Linux; U; Android 12; zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)';
const clean=x=>String(x??'').replace(/<[^>]*>/g,'').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();
const id=x=>{const s=String(x??'');if(!/^\d{1,30}$/.test(s))throw Error('内容身份无效');return s;};
const parse=s=>JSON.parse(String(s).replace(/([:\[,])(\s*)(\d{16,})(?=\s*[,}\]])/g,'$1$2"$3"'));
function fail(ctx,code,message){ctx.fail(code,message);}
async function request(ctx,url,options={}){
 ctx.signal.throwIfAborted();const response=await ctx.http[options.bytes!==undefined||options.json!==undefined?'post':'get'](url,{responseType:'text',timeoutMs:12000,maxResponseBytes:2*1024*1024,...options});
 if(response.status<200||response.status>=300)fail(ctx,'NETWORK','红果接口 HTTP '+response.status);
 if(!response.data)fail(ctx,'INVALID_RESPONSE','红果 '+url.split('?')[0].split('/').slice(-3).join('/')+' 返回空正文，请稍后重试');
 return parse(response.data);
}
async function identity(ctx){
 const lib=libraries(ctx);if(currentIdentity)return currentIdentity;
 const stored=await ctx.store.get('device.v1');
 if(stored&&/^\d+$/.test(stored.device_id)&&/^\d+$/.test(stored.iid)&&/^[a-f0-9-]{36}$/i.test(stored.cdid)){currentIdentity=stored;return stored;}
 const r=lib.register.createRegistrationRequest(),value=await request(ctx,lib.register.REGISTER_URL,{headers:r.options.headers,bytes:r.options.data.toString('base64')});
 const device_id=id(value.device_id_str||value.device_id),iid=id(value.install_id_str||value.install_id);
 if(!/[1-9]/.test(device_id)||!/[1-9]/.test(iid))fail(ctx,'INVALID_RESPONSE','红果匿名设备注册失败');
 currentIdentity={device_id,iid,cdid:r.cdid};await ctx.store.set('device.v1',currentIdentity);return currentIdentity;
}
async function signed(ctx,s){const d=await identity(ctx);return request(ctx,s.url,{headers:{...s.headers,Cookie:`install_id=${d.iid}; store-region=cn-bj; store-region-src=did`},...(s.body?{bytes:s.body.toString('base64')}:{})});}
function cover(value){
 const url=String(value||'').trim().replace(/&amp;/g,'&');
 const match=/^https:\/\/([^/@:?#]+)(\/[^?#]*)(?:\?[^#]*)?$/i.exec(url);
 if(!match)return '';
 if(!/\.heic$/i.test(match[2]))return url;
 if(!/(?:^|\.)(?:fqnovelpic\.com|byteimg\.com)$/i.test(match[1])||!match[2].startsWith('/novel-pic/')||!match[2].includes('~'))return '';
 return 'https://p3-novel.byteimg.com'+match[2].split('~',1)[0]+'~tplv-shrink:640:0.image';
}
function card(v,ctx){
 const title=clean(v.title||v.series_name||v.series_title);if(!title)return null;
 const poster=cover(v.series_cover)||cover(v.cover),summary=clean(v.video_desc||v.series_intro||'').slice(0,65536);
 const tags=Array.isArray(v.sub_title_list)?v.sub_title_list.map(x=>clean(x?.content)).filter(Boolean).slice(0,3):[];
 const count=clean(v.episode_right_text||(v.episode_cnt?'共'+v.episode_cnt+'集':''));
 return {id:id(v.series_id),title,kind:'series',...(poster?{poster}:{}),...(summary&&ctx?.capabilities?.cardSummary?{summary}:{}),subtitle:[count,...tags].filter(Boolean).join(' · ').slice(0,1024)};
}
async function filters(){return [{key:'category',label:'分类',type:'select',default:'hot',options:[{value:'hot',label:'热播榜'},{value:'real',label:'真人短剧'},{value:'comic',label:'漫剧'},{value:'ai',label:'AI 短剧'}]}];}
async function list(ctx,req){
 await identity(ctx);const category=req.filters.category||'hot';const cursor=req.cursor?parse(req.cursor):{offset:0,session:''};
 if(cursor.category&&cursor.category!==category)fail(ctx,'INVALID_RESPONSE','分类分页状态已变化，请刷新');
 const meta=libraries(ctx).metadata;let s;
 if(category==='hot')s=meta.signedMetadataRequest('/reading/bookapi/bookmall/cell/change/v',{tab_type:cursor.offset?'18':'26',client_req_type:'2',client_template:'2',background_selected_items:'',category_id:'0',limit:'20',cell_sub_id:'0',gender:'2',cell_id:'7470092475068071998',selected_items:'all',sub_selected_items:'ranklist_hot_play_sc',panel_selected_items:'',offset:String(cursor.offset),session_id:cursor.session,filter_ids:'',unlimited_selector_change_type:'0'});
 else {const scene={real:['default','short_play'],comic:['comic_series','comic_series'],ai:['ai_series','ai_series']}[category];if(!scene)fail(ctx,'INVALID_RESPONSE','分类无效');s=meta.signedMetadataRequest('/reading/distribution/category/landpage/v/',{},{filter_ids:'',req_scene:scene[0],offset:cursor.offset,need_selector_panel:!cursor.offset,limit:15,select_items:{genre:[scene[1]],sort:['hot_score'],category_dim_theme:[],category_dim_role:[],category_dim_epoch:[],gender:[],online_time:[],creation_status:[]},session_id:cursor.session,req_type:cursor.offset?'only_content':'default',client_req_type:3});}
 const result=await signed(ctx,s);if(Number(result.code)!==0)fail(ctx,'NETWORK','红果目录暂不可用');const data=result.data||{},view=data.cell_view||{};
 const rows=category==='hot'?(view.cell_data||[]).flatMap(x=>Array.isArray(x.video_data)?x.video_data:x.video_data?[x.video_data]:[]):data.video_data;
 if(!Array.isArray(rows))fail(ctx,'INVALID_RESPONSE','红果目录结构已变化');const seen=new Set(),items=[];
 for(const v of rows){if(![1,1004].includes(Number(v.content_type)))continue;const c=card(v,ctx);if(c&&!seen.has(c.id)){seen.add(c.id);items.push(c);}}
 const more=(data.has_more??view.has_more)===true,offset=Number(data.next_offset??view.next_offset),session=data.session_id??view.session_id;
 if(more&&(!Number.isSafeInteger(offset)||offset<=cursor.offset||typeof session!=='string'||!session))fail(ctx,'INVALID_RESPONSE','目录分页游标无效');
 return {items,nextCursor:more?JSON.stringify({category,offset,session}):null};
}
async function search(ctx,req){const page=req.cursor?Number(req.cursor):1;const r=await request(ctx,SITE+'/api/search/result?aid=8662&query='+encodeURIComponent(req.query)+'&page='+page,{headers:{'User-Agent':UA,Referer:SITE+'/'}});if(!Array.isArray(r.searchList))fail(ctx,'INVALID_RESPONSE','红果搜索结构已变化');const items=[],seen=new Set();for(const row of r.searchList){const v=row.video_data&&Object.keys(row.video_data).length?row.video_data:row;const c=card({...v,series_id:v.series_id||row.keyword,title:v.series_name||v.series_title||row.name||v.title},ctx);if(c&&!seen.has(c.id)){seen.add(c.id);items.push(c);}}return {items,nextCursor:r.hasMore===true&&items.length?String(page+1):null};}
function router(html){const m=html.match(/(?:window\.)?_ROUTER_DATA\s*=\s*(\{)/);if(!m)throw Error('官网缺少分集数据');let depth=0,quoted=false,escaped=false;const start=m.index+m[0].length-1;for(let i=start;i<html.length;i++){const c=html[i];if(quoted){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c==='"')quoted=false;}else if(c==='"')quoted=true;else if(c==='{')depth++;else if(c==='}'&&--depth===0)return parse(html.slice(start,i+1));}throw Error('官网分集数据不完整');}
async function series(ctx,sid){id(sid);let last;for(const url of [SITE+'/player/'+sid,SITE+'/detail?series_id='+sid]){try{const r=await ctx.http.get(url,{headers:{'User-Agent':UA,Referer:SITE+'/'},responseType:'text',timeoutMs:8000,maxResponseBytes:2*1024*1024});if(r.status!==200)continue;const data=router(r.data).loaderData||{},page=data['player_(series_id)/page']||data['player_(series_id)/(vid)/page']||data.detail_page;const v=page?.seriesDetail;if(String(v?.series_id)!==sid||page.isSuccess===false||!Array.isArray(v.vid_list)||!v.vid_list.length)continue;const vids=v.vid_list.map(id);if(new Set(vids).size!==vids.length)throw Error('重复分集');return {...v,vid_list:vids};}catch(e){ctx.signal.throwIfAborted();last=e;}}fail(ctx,'INVALID_RESPONSE','红果分集加载失败，请重试');}
async function detail(ctx,req){const v=await series(ctx,id(req.id));return {id:req.id,title:clean(v.series_name),poster:cover(v.series_cover),summary:clean(v.series_intro),kind:'series',groups:[{id:'main',name:'红果',episodes:v.vid_list.map((vid,i)=>({id:vid,name:'第'+(i+1)+'集'}))}]};}
function contentKey(value){const raw=Buffer.from(value,'base64');if(raw.length<3)throw Error('无效媒体密钥');const n=Math.min(raw.length-(raw[0]^raw[1]^raw[2])+47,raw.length-1);if(n<33)throw Error('媒体密钥不完整');const b=Buffer.from(raw.subarray(1,1+n));let a=85,c=246;for(let i=0;i<n;i++){const old=b[i],prev=i&1?a:c;if(i&1)a=old;else c=old;b[i]=(-21-(i.toString(2).split('1').length-1)+(prev^old))&255;}const key=b.subarray(1,33).toString('ascii');if(!/^[0-9a-f]{32}$/i.test(key))throw Error('无效媒体密钥');return key;}
function mediaUrl(ctx,value,seed){let url=value;if(seed){const raw=Buffer.from(value,'base64');if(raw[0]!==168||raw[2]!==1||raw[3]!==0)throw Error('媒体地址编码无效');const crypto=cryptoAdapter(),h1=crypto.createHash('sha512').update(Buffer.from(seed,'base64')).digest();const constants=Buffer.from('4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58','hex');const h=crypto.createHash('sha512').update(Buffer.concat([h1,constants])).digest();const d=crypto.createDecipheriv('aes-128-cbc',h.subarray(0,16),h.subarray(16,32));d.setAutoPadding(false);let b=d.update(raw.subarray(4,4+Math.floor((raw.length-4)/16)*16)),n=b[b.length-1];if(n>=1&&n<=16)b=b.subarray(0,b.length-n);while(b.length&&b[b.length-1]===0)b=b.subarray(0,b.length-1);url=b.toString();}url=String(url).replace(/\\\//g,'/').replace(/&amp;/g,'&');if(!/^https:\/\/[^/@:]+\.(?:qznovelvod|fqnovelvod|douyinvod)\.com\//i.test(url))fail(ctx,'INVALID_RESPONSE','红果返回了无效媒体域名');return url;}
async function range(ctx,url,start,end,total){const r=await ctx.http.get(url,{headers:{'User-Agent':MEDIA_UA,Range:`bytes=${start}-${end}`,'Accept-Encoding':'identity'},responseType:'base64',timeoutMs:12000,maxResponseBytes:Math.min(end-start+2,4194304)});const m=/^bytes (\d+)-(\d+)\/(\d+)$/.exec(r.headers['content-range']||'');const data=Buffer.from(r.data,'base64');if(r.status!==206||!m||Number(m[1])!==start||Number(m[2])!==Math.min(end,Number(m[3])-1)||data.length!==Number(m[2])-start+1||(total&&Number(m[3])!==total))fail(ctx,'INVALID_RESPONSE','红果媒体区间响应无效');return {data,total:Number(m[3]),validator:r.headers.etag?.startsWith('W/')?r.headers['last-modified']:(r.headers.etag||r.headers['last-modified'])};}
async function prepare(ctx,url,key){const first=await range(ctx,url,0,65535),total=first.total;if(total>1073741824)fail(ctx,'UNSUPPORTED','媒体超过处理范围');const read=async(a,b)=>b<first.data.length?first.data.subarray(a,b+1):(await range(ctx,url,a,b,total)).data;const boxes=[];let metadata;
 for(let off=0;off<total;){if(boxes.length>=128)throw Error('媒体索引过多');const header=await read(off,Math.min(off+15,total-1));let size=header.readUInt32BE(0);if(size===1)size=Number(header.readBigUInt64BE(8));else if(size===0)size=total-off;if(!Number.isSafeInteger(size)||size<8||size>total-off)throw Error('媒体索引无效');const typ=header.toString('latin1',4,8);boxes.push({off,size,typ});if(typ==='moov'){if(metadata||size>4194303)throw Error('媒体元数据过大');metadata=Buffer.from(await read(off,off+size-1));}off+=size;}
 if(!metadata)throw Error('缺少媒体索引');const plan=libraries(ctx).mp4.createMp4StreamingPlan(metadata,boxes,total);
 if(plan.encrypted&&!key)fail(ctx,'INVALID_RESPONSE','加密片源没有有效密钥');
 return {key:key||'00000000000000000000000000000000',total,size:plan.size,segments:plan.segments.map(s=>({start:s.start,size:s.size,...(s.buffer?{data:s.buffer.toString('base64')}:{remote:s.remote})})),samples:plan.samples.map(s=>({offset:s.offset,size:s.size,iv:s.iv.toString('base64')})),...(first.validator?{validator:first.validator}:{})};
}
async function play(ctx,req){
 if(req.purpose==='download')fail(ctx,'UNSUPPORTED','红果首版仅支持在线播放');if(!ctx.capabilities.cencMp4)fail(ctx,'UNSUPPORTED','请更新 WeBox 后使用红果播放');
 const v=await series(ctx,id(req.contentId)),vid=id(req.episodeId);if(req.groupId!=='main'||!v.vid_list.includes(vid))fail(ctx,'NOT_FOUND','分集已变化，请重新打开详情');
 const d=await identity(ctx),lib=libraries(ctx),payload=JSON.stringify({biz_param:{detail_page_version:0,device_level:1,disable_digg_stat:false,disable_video_relate_book:false,need_all_video_definition:true,need_mp4_align:false,use_os_player:false,use_server_dns:false,video_platform:1024},mixed_video_id_map:{'1004':[vid]},dr_scene:'player'});
 const crypto=cryptoAdapter(),body=Buffer.from(ctx.crypto.gzip(payload),'base64');let entry,last;
 for(const api of VIDEO_APIS){try{const s=lib.v5.signPlaybackV5(api,{aid:'8662',app_name:'novelread',version_code:'74332',version_name:'7.4.3.32',channel:'vivo_8662_64',device_platform:'android',device_type:'PGT-AN10',os_version:'12',update_version_code:'74332',iid:d.iid,cdid:d.cdid,device_id:d.device_id},body);const r=await signed(ctx,{...s,body,headers:{...s.headers,'User-Agent':MEDIA_UA,Accept:'application/json','Content-Encoding':'gzip'}});if(Number(r.code??r.Code??0)!==0)throw Error('播放服务拒绝请求');entry=r.data?.[vid];if(entry?.video_model)break;}catch(e){ctx.signal.throwIfAborted();last=e;}}
 if(!entry?.video_model)fail(ctx,'NETWORK','红果暂未返回本集播放信息，请稍后重试');const model=typeof entry.video_model==='string'?parse(entry.video_model):entry.video_model;let info=model;
 if(!Array.isArray(model.video_list)||!model.video_list.length){let fallback=model.fallback_api;if(typeof fallback==='string'){try{fallback=parse(fallback).fallback_api||fallback;}catch(_){}}else fallback=Array.isArray(fallback)?fallback[0]:fallback?.fallback_api;if(!/^https:\/\/[^/@:]+\.(?:fqnovel|snssdk)\.com\//.test(fallback||''))fail(ctx,'INVALID_RESPONSE','播放模型缺少有效回退地址');const r=await request(ctx,fallback,{headers:{'User-Agent':MEDIA_UA}});info=r.video_info?.data;if(!info)fail(ctx,'INVALID_RESPONSE','缺少媒体信息');}
 const rows=Object.values(info.video_list||{}).map(x=>({x,codec:String(x.codec_type||x.video_meta?.codec_type||'').toLowerCase(),pixels:Math.min(Number(x.vwidth||x.width||x.video_meta?.vwidth||x.video_meta?.width||0),Number(x.vheight||x.height||x.video_meta?.vheight||x.video_meta?.height||0))})).filter(x=>['h264','avc','avc1','hevc','h265','hvc1','hev1','bytevc1'].includes(x.codec)).sort((a,b)=>b.pixels-a.pixels||Number(a.codec.includes('he')||a.codec==='bytevc1')-Number(b.codec.includes('he')||b.codec==='bytevc1'));
 if(!rows.length)fail(ctx,'UNSUPPORTED','本集暂无兼容的 H.264/HEVC 片源，ByteVC2 尚未支持');
 for(const row of rows){const x=row.x;let key;try{key=x.spade_a||x.encrypt_info?.spade_a;key=key?contentKey(key):null;if(!key&&x.encrypt_info?.encrypt&&!['0','false'].includes(String(x.encrypt_info.encrypt)))continue;}catch(_){continue;}
  for(const raw of [x.main_url,x.backup_url,...(Array.isArray(x.backup_url_list)?x.backup_url_list:[])]){if(typeof raw!=='string'||!raw)continue;try{const url=mediaUrl(ctx,raw,info.key_seed),cenc=await prepare(ctx,url,key);return {sources:[{id:'main',name:'红果 · '+(row.pixels?row.pixels+'p':row.codec),url,mime:'video/mp4',headers:{'User-Agent':MEDIA_UA},downloadable:false,cenc}]};}catch(e){ctx.signal.throwIfAborted();last=e;}}
 }
 fail(ctx,'NETWORK','本集媒体索引读取失败，请重试或切换分集');
}
WeBox.define({api:'1.5',id:'dev.webox.hongguo',name:'红果短剧',version:'0.1.1',allowHttp:false,requires:['crypto','cencMp4'],cache:{list:60,detail:60,filters:3600},filters,list,search,detail,play});

})();
