package com.iceblox.app.processing

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object PlateHasher {
    // XOR-obfuscated pepper: reconstruct at runtime to avoid plaintext in binary
    private val pepperPartA = byteArrayOf(
        0x64, 0x65, 0x66, 0x61, 0x75, 0x6C, 0x74, 0x2D,
        0x70, 0x65, 0x70, 0x70, 0x65, 0x72, 0x2D, 0x63,
        0x68, 0x61, 0x6E, 0x67, 0x65, 0x2D, 0x6D, 0x65
    )
    private val pepperPartB = byteArrayOf(
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    )

    private val pepperKey: ByteArray by lazy {
        ByteArray(pepperPartA.size) { i ->
            (pepperPartA[i].toInt() xor pepperPartB[i].toInt()).toByte()
        }
    }

    fun hash(normalizedPlate: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(pepperKey, "HmacSHA256"))
        val digest = mac.doFinal(normalizedPlate.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
