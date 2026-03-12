package com.iceblox.app.processing

import com.iceblox.app.config.AppConfig
import com.iceblox.app.detection.SlotCandidate
import java.util.PriorityQueue
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max

object LookalikeExpander {

    fun expand(
        text: String,
        charConfidences: FloatArray,
        slotCandidates: List<List<SlotCandidate>> = emptyList(),
        maxVariants: Int = AppConfig.MAX_LOOKALIKE_VARIANTS
    ): List<Triple<String, Int, Float>> {
        val slots = buildSlotLists(text, charConfidences, slotCandidates)

        var totalCombinations = 1L
        for (slot in slots) {
            totalCombinations *= slot.size
            if (totalCombinations > maxVariants) break
        }

        return if (totalCombinations <= maxVariants) {
            cartesianExpand(slots, text)
        } else {
            priorityQueueExpand(slots, text, maxVariants)
        }
    }

    private fun buildSlotLists(
        text: String,
        charConfidences: FloatArray,
        slotCandidates: List<List<SlotCandidate>>
    ): List<List<SlotCandidate>> {
        val result = mutableListOf<List<SlotCandidate>>()
        for (i in text.indices) {
            if (i < slotCandidates.size && slotCandidates[i].size > 1) {
                result.add(slotCandidates[i])
            } else {
                val conf = if (i < charConfidences.size) charConfidences[i] else 0f
                result.add(listOf(SlotCandidate(text[i], conf)))
            }
        }
        return result
    }

    private fun computeConfidence(slots: List<List<SlotCandidate>>, indices: IntArray): Float {
        val count = slots.size
        if (count == 0) return 0f
        var logSum = 0f
        for (i in 0 until count) {
            logSum += ln(max(slots[i][indices[i]].probability, 1e-6f))
        }
        return exp(logSum / count)
    }

    private fun cartesianExpand(
        slots: List<List<SlotCandidate>>,
        primaryText: String
    ): List<Triple<String, Int, Float>> {
        val results = mutableListOf<Triple<String, Int, Float>>()
        val n = slots.size
        val indices = IntArray(n)

        while (true) {
            val sb = StringBuilder(n)
            var subs = 0
            for (i in 0 until n) {
                sb.append(slots[i][indices[i]].char)
                if (indices[i] != 0) subs++
            }
            val conf = computeConfidence(slots, indices)
            results.add(Triple(sb.toString(), subs, conf))

            var pos = n - 1
            while (pos >= 0) {
                indices[pos]++
                if (indices[pos] < slots[pos].size) break
                indices[pos] = 0
                pos--
            }
            if (pos < 0) break
        }

        results.sortByDescending { it.third }
        val primaryIdx = results.indexOfFirst { it.first == primaryText }
        if (primaryIdx > 0) {
            val primary = results.removeAt(primaryIdx)
            results.add(0, primary)
        }
        return results
    }

    private fun priorityQueueExpand(
        slots: List<List<SlotCandidate>>,
        primaryText: String,
        maxVariants: Int
    ): List<Triple<String, Int, Float>> {
        val n = slots.size
        val results = mutableListOf<Triple<String, Int, Float>>()
        val seen = mutableSetOf<List<Int>>()

        data class Entry(
            val indices: IntArray,
            val lastModified: Int,
            val confidence: Float
        )

        val queue = PriorityQueue<Entry>(compareByDescending { it.confidence })

        val seedIndices = IntArray(n)
        val seedConf = computeConfidence(slots, seedIndices)
        queue.add(Entry(seedIndices, 0, seedConf))
        seen.add(seedIndices.toList())

        while (queue.isNotEmpty() && results.size < maxVariants) {
            val entry = queue.poll()!!
            val sb = StringBuilder(n)
            var subs = 0
            for (i in 0 until n) {
                sb.append(slots[i][entry.indices[i]].char)
                if (entry.indices[i] != 0) subs++
            }
            results.add(Triple(sb.toString(), subs, entry.confidence))

            for (pos in entry.lastModified until n) {
                val nextIdx = entry.indices[pos] + 1
                if (nextIdx < slots[pos].size) {
                    val childIndices = entry.indices.copyOf()
                    childIndices[pos] = nextIdx
                    val key = childIndices.toList()
                    if (seen.add(key)) {
                        val conf = computeConfidence(slots, childIndices)
                        queue.add(Entry(childIndices, pos, conf))
                    }
                }
            }
        }

        return results
    }
}
