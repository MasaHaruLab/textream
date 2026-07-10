// v3 harness: source modeled EXACTLY like the app (splitTextIntoWords + " " join
// => a space between every hanzi). v2 = shipped re-anchor (40-window),
// v3 = extended window (300). Spoken gets scattered substitution noise.
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

func normalize(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
}

func charLevelMatch(srcArr: [Character], spoken: String, anchorWindow: Int) -> Int {
    let src = srcArr
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
                for skipR in 1...maxSkipR where spk[ri + skipR] == sc { ri += skipR; found = true; break }
            }
            if found { continue }
            let maxSkipS = min(5, src.count - si - 1)
            if maxSkipS >= 1 {
                for skipS in 1...maxSkipS where src[si + skipS] == rc { si += skipS; found = true; break }
            }
            if found { continue }
            if anchorWindow > 0 {
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
                    while sj < src.count && examined < anchorWindow {
                        if src[sj].isLetter || src[sj].isNumber {
                            var k = 0, pos = sj
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

let zhHanzi = Array("大家好今天想跟大家聊一个我最近特别有感触的话题做内容这件事最难的从来不是技术而是坚持很多人问我每天哪来这么多想法可以写可以拍其实答案很简单就是把生活里每一个让你心里动了一下的瞬间都记下来然后用自己的话讲给别人听坚持九十天你会看到完全不一样的自己再坚持一年你会感谢今天开始的这个决定每一条视频都是未来的你回头看时的里程碑")
let srcSpaced = Array(zhHanzi.map(String.init).joined(separator: " "))

// deterministic ~12% substitution noise
let noisePool = Array("琪拾旦鹅浮鸽喉衣渐科")
func addNoise(_ chars: [Character]) -> [Character] {
    var out = chars
    var seed = 7
    for i in 0..<out.count {
        seed = (seed &* 1103515245 &+ 12345) % 100
        if seed < 12 { out[i] = noisePool[i % noisePool.count] }
    }
    return out
}

struct Case { let name: String; let committedHanzi: Int; let gapHanzi: Int; let noisy: Bool }
let cases = [
    Case(name: "gap5-clean",   committedHanzi: 15, gapHanzi: 5,  noisy: false),
    Case(name: "gap12-clean",  committedHanzi: 15, gapHanzi: 12, noisy: false),
    Case(name: "gap30-clean",  committedHanzi: 15, gapHanzi: 30, noisy: false),   // 她读过头才发现
    Case(name: "gap50-clean",  committedHanzi: 15, gapHanzi: 50, noisy: false),
    Case(name: "gap12-noisy",  committedHanzi: 15, gapHanzi: 12, noisy: true),
    Case(name: "gap30-noisy",  committedHanzi: 15, gapHanzi: 30, noisy: true),
]

print("case          | v1(无锚) v2(窗40) v3(窗300) | 读者实际(spaced)")
for c in cases {
    let matchStart = c.committedHanzi * 2
    let postGap = c.committedHanzi + c.gapHanzi
    var results: [Int] = []
    for window in [0, 40, 300] {
        var recognized = matchStart
        for n in 1...12 {
            let end = min(postGap + n * 5, zhHanzi.count)
            guard postGap < end else { break }
            var spokenChars = Array(zhHanzi[postGap..<end])
            if c.noisy { spokenChars = addNoise(spokenChars) }
            let sub = Array(srcSpaced.dropFirst(matchStart))
            let m = charLevelMatch(srcArr: sub, spoken: String(spokenChars), anchorWindow: window)
            let cand = matchStart + m
            if cand > recognized { recognized = cand }   // simplified commit (smallStep/confirmed converge over 12 partials)
        }
        results.append(recognized)
    }
    let readerAt = min((postGap + 12 * 5), zhHanzi.count) * 2
    print("\(c.name)  |  \(results[0])  \(results[1])  \(results[2])  |  \(readerAt)")
}
