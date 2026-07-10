// A/B regression harness: v1 = Textream 1.6.2 matching, v2 = patched
// (n-gram re-anchor in charLevelMatch + no-average-with-zero bestOffset).
import Foundation

extension Unicode.Scalar {
    var isCJK: Bool {
        switch value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF,
             0x3040...0x30FF, 0xAC00...0xD7AF: return true
        default: return false
        }
    }
}

func splitTextIntoWords(_ text: String) -> [String] {
    let tokens = text.replacingOccurrences(of: "\n", with: " ")
        .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        .map { String($0) }
    var result: [String] = []
    for token in tokens {
        guard token.unicodeScalars.contains(where: { $0.isCJK }) else {
            result.append(token); continue
        }
        var buffer = ""
        for char in token {
            if char.unicodeScalars.first.map({ $0.isCJK }) == true {
                if !buffer.isEmpty { result.append(buffer); buffer = "" }
                result.append(String(char))
            } else { buffer.append(char) }
        }
        if !buffer.isEmpty { result.append(buffer) }
    }
    return result
}

func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var dp = Array(0...b.count)
    for i in 1...a.count {
        var prev = dp[0]; dp[0] = i
        for j in 1...b.count {
            let temp = dp[j]
            dp[j] = a[i-1] == b[j-1] ? prev : min(prev, dp[j], dp[j-1]) + 1
            prev = temp
        }
    }
    return dp[b.count]
}

func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
    if a.isEmpty || b.isEmpty { return false }
    if a == b { return true }
    let shorter = min(a.count, b.count)
    if shorter >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
    let shared = zip(a, b).prefix(while: { $0 == $1 }).count
    if shorter >= 3 && shared >= max(3, shorter * 3 / 5) { return true }
    let dist = editDistance(a, b)
    if shorter <= 2 { return false }
    if shorter <= 4 { return dist <= 1 }
    if shorter <= 8 { return dist <= 2 }
    return dist <= max(a.count, b.count) / 3
}

func normalize(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
}

func charLevelMatch(source: String, matchStartOffset: Int, spoken: String, reanchor: Bool) -> Int {
    let remainingSource = String(source.dropFirst(matchStartOffset))
    let src = Array(remainingSource.lowercased())
    let spk = Array(normalize(spoken))
    var si = 0, ri = 0, lastGoodOrigIndex = 0
    while si < src.count && ri < spk.count {
        let sc = src[si], rc = spk[ri]
        if !sc.isLetter && !sc.isNumber { si += 1; continue }
        if !rc.isLetter && !rc.isNumber { ri += 1; continue }
        if sc == rc { si += 1; ri += 1; lastGoodOrigIndex = si }
        else {
            var found = false
            let maxSkipR = min(5, spk.count - ri - 1)
            if maxSkipR >= 1 {
                for skipR in 1...maxSkipR where spk[ri + skipR] == sc {
                    ri += skipR; found = true; break
                }
            }
            if found { continue }
            let maxSkipS = min(5, src.count - si - 1)
            if maxSkipS >= 1 {
                for skipS in 1...maxSkipS where src[si + skipS] == rc {
                    si += skipS; found = true; break
                }
            }
            if found { continue }
            if reanchor {
                let anchorLen = rc.unicodeScalars.first.map({ $0.isCJK }) == true ? 3 : 6
                var anchor: [Character] = []
                var scan = ri
                while scan < spk.count && anchor.count < anchorLen {
                    if spk[scan].isLetter || spk[scan].isNumber { anchor.append(spk[scan]) }
                    scan += 1
                }
                if anchor.count == anchorLen {
                    var sj = si + 1
                    var examined = 0
                    while sj < src.count && examined < 40 {
                        if src[sj].isLetter || src[sj].isNumber {
                            var k = 0
                            var pos = sj
                            while pos < src.count && k < anchor.count {
                                if !src[pos].isLetter && !src[pos].isNumber { pos += 1; continue }
                                if src[pos] == anchor[k] { k += 1; pos += 1 } else { break }
                            }
                            if k == anchor.count { si = sj; found = true; break }
                            examined += 1
                        }
                        sj += 1
                    }
                }
                if found { continue }
            }
            ri += 1
        }
    }
    return lastGoodOrigIndex
}

func wordLevelMatch(source: String, matchStartOffset: Int, spoken: String) -> Int {
    let remainingSource = String(source.dropFirst(matchStartOffset))
    let sourceWords = remainingSource.split(separator: " ").map { String($0) }
    let spokenWords = splitTextIntoWords(spoken.lowercased())
    var si = 0, ri = 0, matchedCharCount = 0
    while si < sourceWords.count && ri < spokenWords.count {
        let srcWord = sourceWords[si].lowercased().filter { $0.isLetter || $0.isNumber }
        let spkWord = spokenWords[ri].filter { $0.isLetter || $0.isNumber }
        if srcWord == spkWord || isFuzzyMatch(srcWord, spkWord) {
            matchedCharCount += sourceWords[si].count
            si += 1; ri += 1
            if si < sourceWords.count { matchedCharCount += 1 }
        } else {
            var foundSpk = false
            let maxSpkSkip = min(5, spokenWords.count - ri - 1)
            if maxSpkSkip >= 1 {
                for skip in 1...maxSpkSkip {
                    let nextSpk = spokenWords[ri + skip].filter { $0.isLetter || $0.isNumber }
                    if srcWord == nextSpk || isFuzzyMatch(srcWord, nextSpk) { ri += skip; foundSpk = true; break }
                }
            }
            if foundSpk { continue }
            var foundSrc = false
            let maxSrcSkip = min(5, sourceWords.count - si - 1)
            if maxSrcSkip >= 1 {
                for skip in 1...maxSrcSkip {
                    let nextSrc = sourceWords[si + skip].lowercased().filter { $0.isLetter || $0.isNumber }
                    if nextSrc == spkWord || isFuzzyMatch(nextSrc, spkWord) {
                        for s in 0..<skip { matchedCharCount += sourceWords[si + s].count + 1 }
                        si += skip; foundSrc = true; break
                    }
                }
            }
            if foundSrc { continue }
            if srcWord.isEmpty {
                matchedCharCount += sourceWords[si].count
                if si < sourceWords.count - 1 { matchedCharCount += 1 }
                si += 1; continue
            }
            ri += 1
        }
    }
    return matchedCharCount
}

func bestOffset(_ c: Int, _ w: Int, zeroFix: Bool) -> Int {
    if zeroFix && (c == 0 || w == 0) { return max(c, w) }
    if abs(c - w) <= 20 { return (c + w) / 2 }
    return max(c, w)
}

func shouldCommit(c: Int, w: Int, current: Int, candidate: Int, confirmed: Bool) -> Bool {
    let bothProgressed = min(c, w) > 0
    let smallStep = candidate - current <= 15
    return bothProgressed || confirmed || smallStep
}

struct Sim {
    let name: String
    let source: String
    let gapChars: Int
    let committedBeforeGap: Int
    var mutate: ((String) -> String)? = nil   // simulate STT errors on spoken
}

func run(_ sim: Sim, v2: Bool) -> Int {
    let src = Array(sim.source)
    let postGapStart = sim.committedBeforeGap + sim.gapChars
    let matchStart = sim.committedBeforeGap
    var recognized = sim.committedBeforeGap
    var recentPositions: [Int] = []
    for n in 1...12 {
        let endIdx = min(postGapStart + n * 5, src.count)
        guard postGapStart < endIdx else { break }
        var spoken = String(src[postGapStart..<endIdx])
        if let mutate = sim.mutate { spoken = mutate(spoken) }
        let c = charLevelMatch(source: sim.source, matchStartOffset: matchStart, spoken: spoken, reanchor: v2)
        let w = wordLevelMatch(source: sim.source, matchStartOffset: matchStart, spoken: spoken)
        let best = bestOffset(c, w, zeroFix: v2)
        let candidate = min(matchStart + best, sim.source.count)
        var confirmed = false
        if candidate > recognized {
            recentPositions.append(candidate)
            if recentPositions.count > 3 { recentPositions.removeFirst() }
            if recentPositions.count >= 2 {
                let agree = recentPositions.filter { abs($0 - candidate) <= 10 }.count
                confirmed = agree >= 2
            }
        }
        if candidate > recognized && shouldCommit(c: c, w: w, current: recognized, candidate: candidate, confirmed: confirmed) {
            recognized = candidate
        }
    }
    return recognized
}

let zh = "大家好今天想跟大家聊一个我最近特别有感触的话题做内容这件事最难的从来不是技术而是坚持很多人问我每天哪来这么多想法可以写可以拍其实答案很简单就是把生活里每一个让你心里动了一下的瞬间都记下来然后用自己的话讲给别人听坚持九十天你会看到完全不一样的自己"
let en = "hello everyone today i want to talk about something i have been thinking about for a long time making content is never about technique it is about persistence many people ask me where all these ideas come from every single day the answer is simple just write down every moment that moves you"

// 同音字 burst：spoken 开头 6 个字被识别成别的字（模拟发音/识别错误）
let homophoneBurst: (String) -> String = { s in
    let wrong = "琪拾旦鹅浮鸽"
    var chars = Array(s)
    for i in 0..<min(6, chars.count) { chars[i] = Array(wrong)[i % 6] }
    return String(chars)
}

let sims: [Sim] = [
    Sim(name: "中文·缺口3字",            source: zh, gapChars: 3,  committedBeforeGap: 30),
    Sim(name: "中文·缺口8字(55s重启)",   source: zh, gapChars: 8,  committedBeforeGap: 30),
    Sim(name: "中文·缺口15字(跳读)",     source: zh, gapChars: 15, committedBeforeGap: 30),
    Sim(name: "中文·缺口25字(大段跳读)", source: zh, gapChars: 25, committedBeforeGap: 30),
    Sim(name: "中文·同音字连错6字",      source: zh, gapChars: 0,  committedBeforeGap: 30, mutate: homophoneBurst),
    Sim(name: "English·gap 40 chars",   source: en, gapChars: 40, committedBeforeGap: 30),
    Sim(name: "English·gap 25 chars",   source: en, gapChars: 25, committedBeforeGap: 30),
]

print(String(format: "%-28s %8s %8s %10s", ("场景" as NSString).utf8String!, ("v1旧" as NSString).utf8String!, ("v2新" as NSString).utf8String!, ("读者实际" as NSString).utf8String!))
for sim in sims {
    let v1 = run(sim, v2: false)
    let v2 = run(sim, v2: true)
    let reader = min(sim.committedBeforeGap + sim.gapChars + 60, sim.source.count)
    let verdict = v2 >= reader - 15 ? "✓恢复" : (v2 > v1 ? "△改善" : "✗仍卡")
    print(String(format: "%-26s %6d %6d %8d   %@", (sim.name as NSString).utf8String!, v1, v2, reader, verdict))
}
