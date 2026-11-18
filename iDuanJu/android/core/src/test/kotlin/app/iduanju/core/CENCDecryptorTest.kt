package app.iduanju.core

import app.iduanju.core.cenc.CENCDecryptor
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class CENCDecryptorTest {
    private val key = ByteArray(16) { it.toByte() }
    private val hex = key.joinToString("") { "%02x".format(it) }
    private fun be(n: Int) = ByteBuffer.allocate(4).putInt(n).array()
    private fun short(n: Int) = byteArrayOf((n shr 8).toByte(), n.toByte())
    private fun box(type: String, body: ByteArray) = be(body.size + 8) + type.toByteArray() + body
    private fun full(type: String, body: ByteArray, flags: Int = 0) = box(type, be(flags) + body)
    private fun crypt(data: ByteArray, iv: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/CTR/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv.copyOf(16)))
        return c.doFinal(data)
    }

    private fun fixture(aux: Boolean, subs: Boolean, clearOnly: Boolean = false, constant: Boolean = false): Pair<ByteArray, ByteArray> {
        val iv = ByteArray(8) { (it + 10).toByte() }
        val plain = ByteArray(57) { (it * 7).toByte() }
        val ciphertext = if (!subs) crypt(plain, iv) else if (clearOnly) plain else {
            val encrypted = crypt(plain.copyOfRange(5, 22) + plain.copyOfRange(29, 57), iv)
            plain.copyOfRange(0, 5) + encrypted.copyOfRange(0, 17) + plain.copyOfRange(22, 29) + encrypted.copyOfRange(17, encrypted.size)
        }
        val records = (if (constant) byteArrayOf() else iv) + if (!subs) byteArrayOf() else if (clearOnly) short(1) + short(57) + be(0)
            else short(2) + short(5) + be(17) + short(7) + be(28)
        val tenc = full("tenc", byteArrayOf(0, 0, 1, if (constant) 0 else 8) + ByteArray(16) + if (constant) byteArrayOf(8) + iv else byteArrayOf())
        val sinf = box("sinf", box("frma", "avc1".toByteArray()) + full("schm", "cenc".toByteArray() + be(65536)) + box("schi", tenc))
        val stsd = full("stsd", be(1) + box("encv", ByteArray(78) + sinf))
        val ftyp = box("ftyp", "isom".toByteArray() + be(1))
        fun moov(offset: Int, auxOffset: Int): ByteArray {
            val info = if (aux) full("saiz", byteArrayOf(records.size.toByte()) + be(1)) + full("saio", be(1) + be(auxOffset))
                else full("senc", be(1) + records, if (subs) 2 else 0)
            val stbl = box("stbl", stsd + full("stsz", be(0) + be(1) + be(plain.size)) +
                full("stsc", be(1) + be(1) + be(1) + be(1)) + full("stco", be(1) + be(offset)) + info)
            return box("moov", box("trak", full("tkhd", ByteArray(8) + be(1) + ByteArray(68)) + box("mdia", box("minf", stbl))))
        }
        val headLen = ftyp.size + moov(0, 0).size
        return (ftyp + moov(headLen + 8 + if (aux) records.size else 0, headLen + 8) +
            box("mdat", (if (aux) records else byteArrayOf()) + ciphertext)) to plain
    }

    @Test fun knownPlaintextAcrossLayouts() {
        for (aux in listOf(false, true)) for (subs in listOf(false, true)) for (constant in listOf(false, true)) {
            val (file, plain) = fixture(aux, subs, constant = constant)
            val out = CENCDecryptor.decryptCopy(file, hex)
            assertArrayEquals("aux=$aux subs=$subs const=$constant", plain, out.takeLast(plain.size).toByteArray())
            assertFalse(String(out, Charsets.ISO_8859_1).contains("encv"))
            assertTrue(String(out, Charsets.ISO_8859_1).contains("avc1"))
        }
    }
    @Test fun entirelyClearSubsampleStaysClear() {
        for (aux in listOf(false, true)) {
            val (file, plain) = fixture(aux, true, clearOnly = true)
            assertArrayEquals(plain, CENCDecryptor.decryptCopy(file, hex).takeLast(plain.size).toByteArray())
        }
    }
    @Test fun badKeyRejected() {
        assertThrows(CENCDecryptor.Failure::class.java) { CENCDecryptor.decryptCopy(fixture(false, false).first, "aa") }
    }

    @Test fun fragmentedDefaultSizeAndMultipleRuns() {
        val iv1 = ByteArray(8) { (it + 1).toByte() }; val iv2 = ByteArray(8) { (it + 20).toByte() }
        val a = ByteArray(32) { (it * 3).toByte() }; val c = ByteArray(32) { (it * 5).toByte() }
        val tenc = full("tenc", byteArrayOf(0, 0, 1, 8) + ByteArray(16))
        val sinf = box("sinf", box("frma", "avc1".toByteArray()) + full("schm", "cenc".toByteArray() + be(65536)) + box("schi", tenc))
        val stsd = full("stsd", be(1) + box("encv", ByteArray(78) + sinf))
        val trak = box("trak", full("tkhd", ByteArray(8) + be(1) + ByteArray(68)) + box("mdia", box("minf", box("stbl", stsd))))
        val head = box("ftyp", "isom".toByteArray() + be(1)) + box("moov", trak)
        fun fragment(offset: Int): ByteArray = box("moof", box("traf",
            full("tfhd", be(1) + be(1000) + be(32), 0x20018) +
            full("trun", be(1) + be(offset), 1) + full("trun", be(1)) + full("senc", be(2) + iv1 + iv2)))
        val moof = fragment(fragment(0).size + 8)
        val encrypted = head + moof + box("mdat", crypt(a, iv1) + crypt(c, iv2))
        assertArrayEquals(a + c, CENCDecryptor.decryptCopy(encrypted, hex).takeLast(64).toByteArray())
    }
}
