@file:OptIn(ExperimentalUnsignedTypes::class)
package app.iduanju.core.hongguo

import java.util.Base64
import java.security.SecureRandom

/** Current player dialect, ported from gateway 0613b49 playersign/current*.go.
 * Apache-2.0 transform provenance and modifications: HGCurrentPlayer-NOTICE.md.
 * Category requests retain HGPlaybackSign (551); no SDK token or phone dependency.
 */
object HGCurrentPlayer {
    private val s = HGPlayerSign
    private val profile = HGCurrentProfile.bytes
    private val material = profile.copyOfRange(0, 32)
    private val header = profile.copyOfRange(32, 48)
    private val boxes = Array(4) { profile.copyOfRange(48 + it * 256, 48 + (it + 1) * 256) }
    private val initial = Array(4) { profile.copyOfRange(1072 + it * 4, 1076 + it * 4) }
    private val checksum = ULongArray(256) { s.rdLE64(profile, 1088 + it * 8) }
    private val factorIV = UIntArray(8) { le(profile, 3136 + it * 4) }
    private val factorTable = UIntArray(64) { le(profile, 3168 + it * 4) }
    private val padding = profile.copyOfRange(3424, 3428)
    private fun u(b: ByteArray, i: Int) = b[i].toInt() and 255
    private fun le(b: ByteArray, i: Int) = (0..3).fold(0u) { v, j -> v or (u(b, i+j).toUInt() shl (j*8)) }
    private fun be(b: ByteArray, i: Int) = (0..3).fold(0u) { v, j -> (v shl 8) or u(b,i+j).toUInt() }
    private fun rr(v: UInt, n: Int): UInt = v.rotateRight(n)
    private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)

    fun sign(pairs: List<Pair<String,String>>, nowMillis: Long, deviceID: String, versionName: String, body: ByteArray,
             entropy: ByteArray = ByteArray(24).also { SecureRandom().nextBytes(it) }): Pair<String, Map<String,String>> {
        require(nowMillis in 1000..(Int.MAX_VALUE.toLong()*1000-128) && deviceID.isNotEmpty() && deviceID.length <= 64 && versionName.isNotEmpty() && versionName.length <= 32 && entropy.size == 24)
        val base = pairs.filter { it.first != "ts" && it.first != "_rticket" }
        val digest = s.md5(body)
        for (offset in 0..127) {
            val ticket = nowMillis + offset; val seconds = (ticket/1000).toUInt()
            val query = s.encodeQuery(base + listOf("ts" to seconds.toString(), "_rticket" to ticket.toString()))
            require(query.length <= 32768)
            val qhash = s.sm3(query.toByteArray())
            val input = qhash + digest + s.le32(seconds)
            val selector = (s.getIV(0x20230928u, input) and 15u).toInt()
            if (selector % 3 != 0) continue
            val factor = factor(input, seconds, selector)
            val pb = protobuf(seconds, deviceID, versionName, le(entropy, 0), factor, qhash.copyOf(6))
            val headers = compute(query, digest, pb, material, "646637794", "8662", seconds.toULong(), u(entropy,0) or (u(entropy,1) shl 8), 0x101,
                le(entropy,4), le(entropy,8), le(entropy,12), 0x10000000uL, le(entropy,16)).first.toMutableMap()
            headers.putAll(mapOf("Accept" to "application/json; charset=utf-8,application/x-protobuf", "Content-Type" to "application/json; charset=utf-8",
                "x-xs-from-web" to "0", "sdk-version" to "2", "x-ss-req-ticket" to ticket.toString(), "x-ss-stub" to s.hexStr(digest)))
            return query to headers
        }
        error("current player factor selector search exhausted")
    }

    private fun protobuf(t: UInt, did: String, version: String, nonce: UInt, factor: ByteArray, hash: ByteArray): ByteArray {
        fun n(tag: UInt, v: Long) = s.pSInt(tag,v)
        fun str(tag: UInt, v: String) = s.pStr(tag,v)
        var pb = s.pBytes(1u,header) + n(2u,5) + n(3u,nonce.toLong()) + str(4u,"8662") + str(5u,did) + str(6u,"646637794")
        pb += str(7u,version) + str(8u,"v04.10.03-ml-android") + n(9u,135529984/2) + s.pBytes(10u,ByteArray(8)) + n(12u,t.toLong())
        pb += s.pBytes(13u,factor) + s.pBytes(14u,hash) + s.pBytes(15u,n(1u,1)+n(2u,1)+n(3u,1)) + n(17u,t.toLong()) + str(20u,"none") + n(21u,377)
        pb += s.pBytes(23u,n(1u,100)+n(5u,7)+str(6u,"v04.10.03.04-bugfix")+n(7u,10001)+str(14u,version))
        return pb + str(24u,"""{"cmr":16777216,"cmr2":16777216,"vpn":0,"kd":0,"dyn":"","do":0,"tk":false}""")
    }

    internal fun factor(input: ByteArray, seconds: UInt, selector: Int): ByteArray {
        require(input.size == 52 && selector in listOf(0,3,6,9,12,15))
        val cfg = arrayOf(intArrayOf(15,100),intArrayOf(13,96),intArrayOf(62,94),intArrayOf(79,97),intArrayOf(66,96),intArrayOf(127,99))[selector/3]
        val adjusted = seconds + cfg[0].toUInt() - 15u
        val rotation = adjusted + 0xee47628fu
        val init = UIntArray(8) { rr(factorIV[it],(rotation and 31u).toInt()) }
        val table = UIntArray(64) { rr(factorTable[it],((rotation+1u) and 31u).toInt()) }
        val block = input.copyOf(64)
        val shift = ((rotation+2u) and 7u).toInt()
        for (i in 0..3) { val x=u(padding,i); block[52+i]=((x ushr shift) or (x shl ((8-shift) and 7))).toByte() }
        block[62]=1; block[63]=0xa0.toByte()
        val w = UIntArray(128)
        for(i in 0..15) w[i]=be(block,i*4)
        for(i in 16..127) { val x=w[i-15]; val y=w[i-2]; w[i]=w[i-16]+(rr(x,7) xor rr(x,18) xor (x shr 3))+w[i-7]+(rr(y,17) xor rr(y,19) xor (y shr 10)) }
        var v=init.copyOf()
        fun sigma(x: UInt)=rr(x,6) xor rr(x,11) xor rr(x,25)
        fun upper(x: UInt)=rr(x,2) xor rr(x,13) xor rr(x,22)
        for(round in 0 until cfg[1]) {
            val a=v[0];val b=v[1];val c=v[2];val d=v[3];val e=v[4];val f=v[5];val g=v[6];val h=v[7]
            val kw=table[(cfg[0]+round) and 63]+w[(cfg[0]+round) and 127]
            v=when(selector) {
                0 -> { val t=kw+(c xor (e and (f xor c)))+sigma(e)+g; uintArrayOf(t+h,a,b,c,d,e,f,((a and b) or ((b or a) and d))+upper(a)+t) }
                3 -> { val t=kw+(h xor (a and (c xor h)))+sigma(a)+b; uintArrayOf(h,a,((f and d) or ((d or f) and g))+upper(f)+t,c,d,t+e,f,g) }
                6 -> { val t=kw+(a xor (d and (b xor a)))+sigma(d)+c; uintArrayOf(h,a,b,((h and g) or ((g or h) and f))+upper(h)+t,d,t+e,f,g) }
                9 -> { val t=kw+(b xor (c and (f xor b)))+sigma(c)+d; uintArrayOf(h,t+a,b,c,((g and h) or ((h or g) and e))+upper(g)+t,e,f,g) }
                12 -> { val t=kw+(e xor (b and (a xor e)))+sigma(b)+g; uintArrayOf(t+h,a,b,c,d,e,f,((d and f) or ((f or d) and c))+upper(d)+t) }
                else -> { val t=kw+(a xor (b and (d xor a)))+sigma(b)+f; uintArrayOf(h,a,b,c,d,t+e,((g and c) or ((c or g) and h))+upper(g)+t,g) }
            }
        }
        val digest=(0..7).flatMap { s.be32(init[it]+v[it]).toList() }.toByteArray()
        val out=ByteArray(20)
        for(i in 0..15) out[i]=(u(digest,i) xor u(digest,i+16)).toByte()
        var state=0x20220420u
        for(i in 0..7) { val x=u(out,i).toUInt(); state=if(i%2==1) (state xor ((state shl 11) or x) xor (state shr 5)).inv() else state xor (state shl 7) xor x xor (state shr 3) }
        s.le32((state and 0x24u.inv()) xor 0x01000000u).copyInto(out,16)
        return out
    }

    internal fun compute(query: String, digest: ByteArray, pb: ByteArray, mat: ByteArray, license: String, aid: String,
        seconds: ULong, nonce: Int, flags: Int, heliosRandom: UInt, random1: UInt, random2: UInt, local: ULong, previous: UInt): Pair<Map<String,String>,UInt> {
        require(mat.size==32 && digest.size==16 && pb.size in 2..32768)
        var crc=0uL
        for(ch in license.toByteArray()) crc=checksum[((crc and 255uL).toInt() xor (ch.toInt() and 255))] xor (crc shr 8)
        val state=(crc xor seconds xor local).rotateLeft(4).toUInt() xor previous
        val headers=linkedMapOf("x-khronos" to seconds.toString(), "x-argus" to b64(s.le32(seconds.toUInt())), "x-ladon" to b64(s.be32(state)),
            "x-gorgon" to gorgon(query,digest,seconds,nonce,flags), "x-helios" to helios(seconds,license,aid,heliosRandom),
            "x-medusa" to medusa(pb,mat,seconds,random1,random2))
        return headers to state
    }

    private fun gorgon(query: String,digest: ByteArray,t: ULong,nonce: Int,flags: Int): String {
        val key=intArrayOf(0x4a,flags and 255,0x16,nonce ushr 8,0x47,0x6c,flags ushr 8,nonce and 255)
        val table=IntArray(256){it};var j=0
        for(i in 0..255) { j=(j+table[i]+key[i%8]) and 255;table[i]=table[j] }
        val seed=s.md5(query.toByteArray()).copyOf(4)+digest.copyOf(4)+ByteArray(4)+byteArrayOf(0,9,9,4)+s.be32(t.toUInt())
        val out=IntArray(20);j=0
        for(n in 0..19) { val i=n+1;j+=table[i and 255];val y=table[j and 255];table[i and 255]=y;out[n]=u(seed,n) xor table[(y+y) and 255] }
        for(i in 0..19) { val x=out[i];val swapped=((x ushr 4) or (x shl 4)) and 255; out[i]=((Integer.reverse(out[(i+1)%20] xor swapped) ushr 24) xor 20).inv() and 255 }
        return s.hexStr(byteArrayOf(0x84.toByte(),4,nonce.toByte(),(nonce ushr 8).toByte(),flags.toByte(),(flags ushr 8).toByte())+out.map{it.toByte()}.toByteArray())
    }

    private fun helios(t: ULong, license: String, aid: String, random: UInt): String {
        val key=s.hexStr(s.md5(s.le32(random)+aid.toByteArray())).toByteArray()
        val keys=ULongArray(35);keys[0]=s.rdLE64(key,0)
        var a=keys[0];var b=s.rdLE64(key,8);val queue=ArrayDeque(listOf(s.rdLE64(key,16),s.rdLE64(key,24)))
        for(i in 0..33) { var x=(b.rotateRight(8)+a) xor i.toULong();queue.addLast(x);x=x xor a.rotateRight(61);keys[i+1]=x;a=x;b=queue.removeFirst() }
        val raw="$t-$license-$aid".toByteArray();val n=16-raw.size%16;val plain=raw+ByteArray(n){n.toByte()};var out=s.le32(random)
        for(at in plain.indices step 16) { var l=s.rdLE64(plain,at);var r=s.rdLE64(plain,at+8);for(i in 0..33){r=keys[i] xor (l+r.rotateRight(8));l=r xor l.rotateRight(61)};out+=s.wrLE64(l)+s.wrLE64(r) }
        return b64(out)
    }

    private fun ks(pb: ByteArray, mat: ByteArray, t: ByteArray): ByteArray {
        val box=s.sm3(mat+t+mat);val n=pb.size;val b=ByteArray(n)
        for(i in pb.indices){val a=u(box,4*i%32).toUInt();val c=u(box,(4*i+1)%32).toUInt();val x=u(pb,i).toUInt();val w=(((x shr 4) or (x shl 4))+a xor c).inv();val rot=((w shl 3) and 0xfffffff8u) or ((w shr 5) and 7u);b[n-1-i]=(a xor (rot+c)).inv().toByte()}
        val last=u(b,n-1);val prev=u(b,n-2)
        b[0]=(u(b,0)+(last xor prev).inv()).toByte();b[1]=((u(b,0) xor last xor 254)+u(b,1)).toByte()
        for(j in 2 until n-1){val v=u(b,j-1);val rot=((v ushr 5) and 7) or (v shl 3);b[j]=(u(b,j)+((u(b,j-2) xor rot) xor j).inv()).toByte()}
        b[n-1]=(u(b,n-1) xor u(b,n-2)).toByte()
        val sum=(1 until n).sumOf{u(b,it)};b[0]=((u(b,0) xor u(b,1))+sum).toByte()
        val reg=(((u(t,2) shl 11) or u(t,3)) xor u(t,2) xor (u(t,2) ushr 5)).inv()
        val mask=s.be32(reg.toUInt());val stream=ByteArray(8)+b
        return ByteArray(stream.size){(u(mask,it%4) xor u(stream,stream.lastIndex-it)).toByte()}
    }

    private val con=arrayOf(intArrayOf(2,0,3,1),intArrayOf(1,3,2,0),intArrayOf(3,2,1,0),intArrayOf(2,3,1,0))
    private val order=arrayOf(intArrayOf(0,9,14,15,4,13,2,7,8,1,6,3,12,5,10,11),intArrayOf(0,9,14,11,4,13,2,3,8,1,6,15,12,5,10,7),intArrayOf(0,9,14,3,4,13,2,15,8,1,6,11,12,5,10,7),intArrayOf(0,9,14,15,4,13,2,3,8,1,6,11,12,5,10,7))
    internal fun transform(plain: ByteArray,key: ByteArray,iv: ByteArray,branch: Int): ByteArray {
        require(key.size==16 && iv.size==16 && branch in 0..3)
        val expanded=ByteArray(48);val box=boxes[branch];val init=le(initial[branch],0)
        for(i in 0..15) expanded[i]=(u(key,i) xor u(initial[branch],i%4)).toByte()
        var rounds=8
        for(i in 4..11){val at=4*(i-1);var a=u(expanded,at);var b=u(expanded,at+1);var c=u(expanded,at+2);var d=u(expanded,at+3)
            if(i and 3==0){val old=a;a=((init shr (rounds and 24)).toInt() xor u(box,b)) and 255;b=u(box,c);c=u(box,d);d=u(box,old)}
            rounds+=2;for((j,v) in listOf(a,b,c,d).withIndex()) expanded[at+4+j]=(v xor u(expanded,at-12+j)).toByte()}
        val pad=16-plain.size%16;val source=plain+ByteArray(pad){pad.toByte()};var previous=iv;val out=ByteArray(source.size);val co=con[branch]
        for(at in source.indices step 16){var state=IntArray(16){i->u(source,at+i) xor u(previous,i) xor u(expanded,4*(i/4)+co[i%4])}
            for(round in 1..2){var old=state;state=IntArray(16){i->u(box,old[co[i/4]*4+i%4])};old=state;state=IntArray(16){old[order[branch][it]]}
                if(round==1){old=state;state=IntArray(16){i->old[4*(i/4)+co[i%4]]};for(j in 0..3){val total=state[j] xor state[4+j] xor state[8+j] xor state[12+j];val first=state[j]
                    for(i in 0..3){val next=if(i<3) state[(i+1)*4+j] else first;val x=state[i*4+j] xor next;val xt=((x shl 1) xor (if(x and 128!=0) 0x1b else 0)) and 255;state[i*4+j]=state[i*4+j] xor total xor xt}}}
                for(i in 0..15) state[i]=state[i] xor u(expanded,16*round+4*(i/4)+co[i%4])}
            previous=ByteArray(16){(state[it] xor u(expanded,16+it)).toByte()};previous.copyInto(out,at)}
        return out
    }

    private fun mid(pb: ByteArray): Int {
        var at=0;val first=IntArray(2){-1}
        fun read(): ULong { var v=0uL;for(i in 0..9){require(at<pb.size);val b=u(pb,at++);require(i<9||b<=1);v=v or ((b and 127).toULong() shl (7*i));if(b and 128==0)return v};error("protobuf varint") }
        while(at<pb.size){val tag=read();require(tag shr 3 != 0uL);when((tag and 7uL).toInt()){0->read();1->at+=8;5->at+=4;2->{val n=read().toInt();require(n>=0&&n<=pb.size-at);val field=(tag shr 3).toInt();if(field in 13..14&&n>0)first[field-13]=u(pb,at);at+=n};else->error("protobuf wire")};require(at<=pb.size)}
        require(first.all{it>=0});return (first[0] and 63) or ((first[1] and 63) shl 6)
    }
    private fun medusa(pb: ByteArray,mat: ByteArray,t: ULong,r1: UInt,r2: UInt): String {
        val mid=mid(pb);val t4=s.le32(r1);var prefix=0u
        for(i in mat.indices){val x=u(mat,i).toUInt();prefix=if(i%2==0) prefix xor (prefix shl 7) xor x xor (prefix shr 3) else prefix xor ((prefix shl 11) xor x xor (prefix shr 5)).inv()}
        val pre=byteArrayOf(prefix.toByte())+s.le32(r2)+byteArrayOf(1,mid.toByte(),(mid ushr 8).toByte(),0x18)+ks(pb,mat,t4)+t4.copyOfRange(2,4)
        require(pre.size>=248);val lane=intArrayOf(6,5,3,4,2,7,1,0);val bits=intArrayOf(1,7,3,6,2,0,4,5);val plain=ByteArray(31)
        for(i in 0..247)plain[i/8]=(u(plain,i/8) or (((u(pre,i) ushr lane[i%8]) and 1) shl bits[i%8])).toByte()
        val channel=transform(plain,s.md5(mat.copyOfRange(0,16)),s.md5(mat.copyOfRange(16,32)),(t and 3uL).toInt());val body=pre.copyOf()
        for(i in 0..247)body[i]=((u(body,i) and (1 shl lane[i%8]).inv()) or (((u(channel,i/8) ushr bits[i%8]) and 1) shl lane[i%8])).toByte()
        val hdr=s.le32(5u)+header;val mask=s.le32(t.toUInt());for(i in hdr.indices)hdr[i]=(u(hdr,i) xor u(mask,i%4)).toByte()
        return b64(hdr+t4.copyOf(2)+byteArrayOf(0,1,channel[31])+body)
    }
}
