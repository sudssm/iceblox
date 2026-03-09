package com.iceblox.app.processing

import com.iceblox.app.config.AppConfig
import java.util.LinkedList

object LookalikeExpander {
    private val groups: List<Set<Char>> = listOf(
        setOf('0', 'O', 'D', 'Q', '8', 'B'),
        setOf('1', 'I', 'L'),
        setOf('5', 'S'),
        setOf('2', 'Z'),
        setOf('A', '4')
    )

    private val charToGroup: Map<Char, Set<Char>> = buildMap {
        for (group in groups) {
            for (ch in group) {
                put(ch, group)
            }
        }
    }

    fun expand(text: String, maxVariants: Int = AppConfig.MAX_LOOKALIKE_VARIANTS): List<Pair<String, Int>> {
        val confusablePositions = mutableListOf<Int>()
        for (i in text.indices) {
            val group = charToGroup[text[i]]
            if (group != null && group.size > 1) {
                confusablePositions.add(i)
            }
        }

        if (confusablePositions.isEmpty()) {
            return listOf(text to 0)
        }

        val results = mutableListOf<Pair<String, Int>>()
        val seen = mutableSetOf<String>()

        data class State(val chars: CharArray, val nextIdx: Int, val substitutions: Int)

        val queue = LinkedList<State>()
        queue.add(State(text.toCharArray(), 0, 0))
        seen.add(text)
        results.add(text to 0)

        while (queue.isNotEmpty() && results.size < maxVariants) {
            val state = queue.poll()

            for (posIdx in state.nextIdx until confusablePositions.size) {
                val pos = confusablePositions[posIdx]
                val group = charToGroup[state.chars[pos]] ?: continue
                val originalChar = state.chars[pos]

                for (alt in group) {
                    if (alt == originalChar) continue
                    val newChars = state.chars.copyOf()
                    newChars[pos] = alt
                    val variant = String(newChars)

                    if (seen.add(variant)) {
                        val subs = state.substitutions + 1
                        results.add(variant to subs)
                        if (results.size >= maxVariants) return results
                        queue.add(State(newChars, posIdx + 1, subs))
                    }
                }
            }
        }

        return results
    }
}
