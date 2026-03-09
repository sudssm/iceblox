import Foundation

enum LookalikeExpander {
    private static let groups: [[Character]] = [
        ["0", "O", "D", "Q", "8", "B"],
        ["1", "I", "L"],
        ["5", "S"],
        ["2", "Z"],
        ["A", "4"]
    ]

    private static let charToGroup: [Character: [Character]] = {
        var map = [Character: [Character]]()
        for group in groups {
            for ch in group {
                map[ch] = group
            }
        }
        return map
    }()

    static func expand(_ text: String, maxVariants: Int = AppConfig.maxLookalikeVariants) -> [(String, Int)] {
        let chars = Array(text)
        var confusablePositions = [Int]()
        for i in chars.indices {
            if let group = charToGroup[chars[i]], group.count > 1 {
                confusablePositions.append(i)
            }
        }

        if confusablePositions.isEmpty {
            return [(text, 0)]
        }

        var results = [(String, Int)]()
        var seen = Set<String>()

        struct State {
            let chars: [Character]
            let nextIdx: Int
            let substitutions: Int
        }

        var queue = [State]()
        queue.append(State(chars: chars, nextIdx: 0, substitutions: 0))
        seen.insert(text)
        results.append((text, 0))

        var head = 0

        while head < queue.count && results.count < maxVariants {
            let state = queue[head]
            head += 1

            for posIdx in state.nextIdx..<confusablePositions.count {
                let pos = confusablePositions[posIdx]
                guard let group = charToGroup[state.chars[pos]] else { continue }
                let originalChar = state.chars[pos]

                for alt in group {
                    if alt == originalChar { continue }
                    var newChars = state.chars
                    newChars[pos] = alt
                    let variant = String(newChars)

                    if seen.insert(variant).inserted {
                        let subs = state.substitutions + 1
                        results.append((variant, subs))
                        if results.count >= maxVariants { return results }
                        queue.append(State(chars: newChars, nextIdx: posIdx + 1, substitutions: subs))
                    }
                }
            }
        }

        return results
    }
}
