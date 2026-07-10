// Architecture A/B round 2 — realistic recognizer noise:
// in-alphabet substitutions (homophone-like), error BURSTS, insertions,
// deletions, and live revision churn of the transcript tail.
import Foundation
extension Unicode.Scalar { var isCJK: Bool { (0x4E00...0x9FFF).contains(Int(value)) } }
func normalize(_ t: String) -> String { t.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace } }
func charLevelMatch(src: [Character], spoken: String, anchorWindow: Int = 300) -> Int {
    let spk = Array(normalize(spoken))
    var si = 0, ri = 0, last = 0
    while si < src.count && ri < spk.count {
        let sc = src[si], rc = spk[ri]
        if !sc.isLetter && !sc.isNumber { si += 1; continue }
        if !rc.isLetter && !rc.isNumber { ri += 1; continue }
        if sc == rc { si += 1; ri += 1; last = si }
        else {
            var found = false
            let mR = min(5, spk.count - ri - 1)
            if mR >= 1 { for s in 1...mR where spk[ri+s] == sc { ri += s; found = true; break } }
            if found { continue }
            let mS = min(5, src.count - si - 1)
            if mS >= 1 { for s in 1...mS where src[si+s] == rc { si += s; found = true; break } }
            if found { continue }
            var anchor: [Character] = []; var scan = ri
            while scan < spk.count && anchor.count < 3 {
                if spk[scan].isLetter || spk[scan].isNumber { anchor.append(spk[scan]) }
                scan += 1
            }
            if anchor.count == 3 {
                var sj = si + 1, ex = 0
                while sj < src.count && ex < anchorWindow {
                    if src[sj].isLetter || src[sj].isNumber {
                        var k = 0, pos = sj
                        while pos < src.count && k < 3 {
                            if !src[pos].isLetter && !src[pos].isNumber { pos += 1; continue }
                            if src[pos] == anchor[k] { k += 1; pos += 1 } else { break }
                        }
                        if k == 3 { si = sj; found = true; break }
                        ex += 1
                    }
                    sj += 1
                }
            }
            if found { continue }
            ri += 1
        }
    }
    return last
}
var seed: UInt64 = 20260710
func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
let pool = Array("天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜海咸河淡鳞潜羽翔龙师火帝鸟官人皇始制文字乃服衣裳推位让国有虞陶唐吊民伐罪周发殷汤坐朝问道垂拱平章爱育黎首臣伏戎羌遐迩一体率宾归王鸣凤在竹白驹食场化被草木赖及万方")
let hanzi: [Character] = (0..<500).map { _ in pool[rnd(pool.count)] }
let srcSpaced = Array(hanzi.map(String.init).joined(separator: " "))

// recognizer output: bursty in-alphabet errors + ins/del, precomputed per hanzi
enum Tok { case ok(Character); case sub(Character); case del; case ins(Character, Character) }
var toks: [Tok] = []
var i = 0
while i < hanzi.count {
    if rnd(100) < 6 {           // burst: 3-5 chars mangled
        let len = 3 + rnd(3)
        for j in i..<min(i+len, hanzi.count) {
            let r = rnd(10)
            if r < 6 { toks.append(.sub(pool[rnd(pool.count)])) }
            else if r < 8 { toks.append(.del) }
            else { toks.append(.ins(hanzi[j], pool[rnd(pool.count)])) }
            _ = j
        }
        i += len
    } else {
        let r = rnd(100)
        if r < 8 { toks.append(.sub(pool[rnd(pool.count)])) }
        else if r < 11 { toks.append(.del) }
        else { toks.append(.ok(hanzi[i])) }
        i += 1
    }
}
func emit(_ range: Range<Int>) -> String {
    var out = ""
    for t in toks[range.clamped(to: 0..<toks.count)] {
        switch t {
        case .ok(let c): out.append(c)
        case .sub(let c): out.append(c)
        case .del: break
        case .ins(let c, let extra): out.append(c); out.append(extra)
        }
    }
    return out
}
func simulate(newArch: Bool) -> (Int, Double, Double) {
    var rec = 0, recent: [Int] = []
    var taskStart = 0, matchStart = 0
    var maxLag = 0, lagSum = 0.0, lagCnt = 0.0, stall = 0.0
    var lastRec = 0, lastMove = 0.0, t = 0.0, spoken = 0
    var nextRestart = 55.0
    while spoken < 500 {
        t += 0.4
        spoken = min(500, Int(t * 5))
        if t >= nextRestart { nextRestart += 55; taskStart = spoken; matchStart = rec }
        guard spoken > taskStart else { continue }
        var transcript = emit(taskStart..<spoken)
        // revision churn: recognizer's last few chars are unstable
        let churn = rnd(4)
        if churn > 0 && transcript.count > churn {
            transcript = String(transcript.dropLast(churn)) + String((0..<churn).map { _ in pool[rnd(pool.count)] })
        }
        let base: Int, evidence: String
        if newArch { evidence = String(transcript.suffix(36)); base = max(0, rec - 80) }
        else { evidence = transcript; base = matchStart }
        let m = charLevelMatch(src: Array(srcSpaced.dropFirst(base)), spoken: evidence)
        let cand = min(base + m, srcSpaced.count)
        var confirmed = false
        if cand > rec {
            recent.append(cand); if recent.count > 3 { recent.removeFirst() }
            if recent.count >= 2 { confirmed = recent.filter { abs($0 - cand) <= 10 }.count >= 2 }
        }
        if cand > rec && (confirmed || cand - rec <= 15) { rec = cand }
        let lag = spoken * 2 - rec
        maxLag = max(maxLag, lag)
        if t > 50 { lagSum += Double(lag); lagCnt += 1 }
        if rec != lastRec { lastRec = rec; lastMove = t } else if t - lastMove > 2.5 { stall += 0.4 }
    }
    return (maxLag, lagSum / max(lagCnt, 1), stall)
}
let o = simulate(newArch: false)
let n = simulate(newArch: true)
print("旧架构: 最大滞后=\(o.0)  后半均滞后=\(String(format:"%.0f",o.1))  卡顿累计=\(String(format:"%.1f",o.2))s")
print("新架构: 最大滞后=\(n.0)  后半均滞后=\(String(format:"%.0f",n.1))  卡顿累计=\(String(format:"%.1f",n.2))s")
