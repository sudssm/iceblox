package com.iceblox.app.processing

import com.iceblox.app.BuildConfig
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object PlateHasher {
    private val pepperKey: ByteArray = BuildConfig.PEPPER.toByteArray(Charsets.UTF_8)

    fun hash(normalizedPlate: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(pepperKey, "HmacSHA256"))
        val digest = mac.doFinal(normalizedPlate.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
