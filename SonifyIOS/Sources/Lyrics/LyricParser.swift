import Foundation

/// 歌词解析。Android 侧对应 `YosLrcFactory`（LRC / KRC / 无时间戳兜底三条路径）。
/// 这里做成纯函数 enum，方便直接写 XCTest（对应 Android 的 JVM 单测）。
enum LyricParser {

    // MARK: - 入口

    /// 自动识别 KRC / LRC / 纯文本。
    static func parse(text: String, translation: String? = nil, totalDuration: TimeInterval = 0) -> [LyricEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if krcLineRegex.firstMatch(in: trimmed, range: trimmed.nsRange) != nil {
            return parseKRC(trimmed, translation: translation)
        }
        let entries = parseLRC(trimmed, translation: translation)
        if entries.isEmpty {
            return synthesizeFromPlainText(trimmed, totalDuration: totalDuration, translation: translation)
        }
        return entries
    }

    // MARK: - LRC

    static func parseLRC(_ lrc: String, translation: String? = nil) -> [LyricEntry] {
        let rows = lrcRows(lrc)
        guard !rows.isEmpty else { return [] }
        let translations = translation.map { lrcRows($0) } ?? []
        return buildEntries(from: rows, translations: translations)
    }

    /// 无时间戳纯文本（M4A ©lyr / MP3 USLT 常见）：按总时长均分合成时间轴，
    /// 否则滚动 UI 依赖的"递增 startTime"不成立，整页歌词会卡在第一行。
    static func synthesizeFromPlainText(
        _ text: String,
        totalDuration: TimeInterval,
        translation: String? = nil
    ) -> [LyricEntry] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "//" }
        guard !lines.isEmpty else { return [] }

        let durationMs = totalDuration > 0 ? Float(totalDuration * 1000) : Float(lines.count * 5000)
        var synthesized = ""
        for (index, line) in lines.enumerated() {
            let timeMs = durationMs * Float(index) / Float(lines.count)
            let minute = Int(timeMs / 60000)
            let second = Int((timeMs.truncatingRemainder(dividingBy: 60000)) / 1000)
            let milli = Int(timeMs.truncatingRemainder(dividingBy: 1000))
            synthesized += String(format: "[%02d:%02d.%03d]%@\n", minute, second, milli, line)
        }
        return parseLRC(synthesized, translation: translation)
    }

    // MARK: - KRC

    /// KRC 结构：行 `[start,duration]`，词 `<offset,duration,0>字`，
    /// 词高亮结束 = `start + offset + duration`（offset 相对行起点）。
    /// 内嵌翻译/罗马音以 `[language:n]` 分块，必须按结构（是否逐字样式）判别，不能只看 language 值。
    static func parseKRC(_ krc: String, translation: String? = nil) -> [LyricEntry] {
        let languageBlocks = krcLanguageBlocks(krc)

        let embeddedTranslations = languageBlocks.first { block in
            block.language == 0 && !block.isSyllableStyle && block.hasText
        }?.rows.map { $0.text }

        let embeddedRomanizations = languageBlocks.first { block in
            block.language != 0 || block.isSyllableStyle
        }?.rows.map { $0.text }

        let explicitTranslations = translation.map { lrcRows($0) } ?? []
        let numericRowCount = krc
            .components(separatedBy: .newlines)
            .filter { krcLineRegex.firstMatch(in: $0.trimmingCharacters(in: .whitespaces), range: $0.trimmingCharacters(in: .whitespaces).nsRange) != nil }
            .count

        var entries: [LyricEntry] = []
        var sourceRowOrdinal = 0
        var lyricRowOrdinal = 0

        for rawLine in krc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = krcLineRegex.firstMatch(in: line, range: line.nsRange) else { continue }
            let rowOrdinal = sourceRowOrdinal
            sourceRowOrdinal += 1

            let start = Float(line.substring(with: match.range(at: 1))) ?? 0
            let duration = Float(line.substring(with: match.range(at: 2))) ?? 0
            let body = line.substring(with: match.range(at: 3))

            let words = krcWordRegex.matches(in: body, range: body.nsRange)
            guard !words.isEmpty else { continue }

            let lineText = words.map { body.substring(with: $0.range(at: 3)) }.joined()
            if isMetadata(lineText) { continue }

            let translationOrdinal = lyricRowOrdinal
            lyricRowOrdinal += 1

            // 内嵌翻译是"每行一条"还是"含元数据/空行全量对齐"，决定用哪个序号去取。
            let embeddedOrdinal: Int
            if (embeddedTranslations?.count ?? 0) >= numericRowCount {
                embeddedOrdinal = rowOrdinal
            } else {
                embeddedOrdinal = translationOrdinal
            }

            var spans: [LyricSpan] = [LyricSpan(time: start, text: "")]
            for word in words {
                let offset = Float(body.substring(with: word.range(at: 1))) ?? 0
                let wordDuration = Float(body.substring(with: word.range(at: 2))) ?? 0
                let text = body.substring(with: word.range(at: 3))
                guard !text.isEmpty else { continue }
                spans.append(LyricSpan(time: start + offset + wordDuration, text: text))
            }

            guard spans.count > 1 else { continue }
            spans.append(LyricSpan(time: start + duration, text: ""))

            let translated = nearest(rows: explicitTranslations, to: start)
                ?? embeddedTranslations?.safe(embeddedOrdinal)
            let romanization = embeddedRomanizations?.safe(translationOrdinal)

            entries.append(
                LyricEntry(
                    spans: spans,
                    translation: translated?.nilIfBlank,
                    romanization: romanization?.nilIfBlank
                )
            )
        }

        return entries
    }

    // MARK: - 内部结构

    private struct TimedText {
        var time: Float
        var text: String
        var words: [LyricSpan]?
    }

    private struct LanguageBlock {
        var language: Int
        var isSyllableStyle: Bool
        var hasText: Bool
        var rows: [(time: Float, text: String)]
    }

    private static let timeRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let lrcWordRegex = try! NSRegularExpression(
        pattern: #"<(\d+),(\d+)>([^<]*)"#
    )
    private static let krcLineRegex = try! NSRegularExpression(
        pattern: #"^\[(-?\d+),(-?\d+)\](.*)$"#
    )
    private static let krcWordRegex = try! NSRegularExpression(
        pattern: #"<(-?\d+),(-?\d+)(?:,-?\d+)?>([^<]*)"#
    )
    private static let languageRegex = try! NSRegularExpression(
        pattern: #"^\[language:(-?\d+)\]$"#
    )

    private static func lrcRows(_ text: String) -> [TimedText] {
        var rows: [TimedText] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let matches = timeRegex.matches(in: line, range: line.nsRange)
            guard !matches.isEmpty else { continue }
            let body = line.substring(fromUTF16: matches[matches.count - 1].range.upperBound)
            guard !body.isEmpty else { continue }

            let words = lrcWordRegex.matches(in: body, range: body.nsRange)
            var spans: [LyricSpan]? = nil

            for match in matches {
                let minute = Float(line.substring(with: match.range(at: 1))) ?? 0
                let second = Float(line.substring(with: match.range(at: 2))) ?? 0
                let fractionText = match.range(at: 3).location == NSNotFound
                    ? ""
                    : line.substring(with: match.range(at: 3))
                var fraction: Float = 0
                if !fractionText.isEmpty {
                    // [00:12.34] 是百分秒，[00:12.345] 是毫秒。
                    let digits = fractionText.count
                    let value = Double(Float(fractionText) ?? 0)
                    fraction = Float(value / pow(10.0, Double(digits)))
                }
                let timeMs = minute * 60000 + second * 1000 + fraction * 1000

                if !words.isEmpty {
                    var built: [LyricSpan] = []
                    for word in words {
                        let offset = Float(body.substring(with: word.range(at: 1))) ?? 0
                        let duration = Float(body.substring(with: word.range(at: 2))) ?? 0
                        let text = body.substring(with: word.range(at: 3))
                        built.append(LyricSpan(time: timeMs + offset + duration, text: text))
                    }
                    if !built.isEmpty { spans = built }
                }

                rows.append(TimedText(time: timeMs, text: body, words: spans))
            }
        }
        return rows
    }

    /// 同名时间戳合并（LRC 里一行常有多个时间标签），并完成逐字/非逐字两条构建路径。
    private static func buildEntries(
        from rows: [TimedText],
        translations: [TimedText]
    ) -> [LyricEntry] {
        let grouped = Dictionary(grouping: rows) { $0.time }
            .sorted { $0.key < $1.key }

        var entries: [LyricEntry] = []
        for (index, pair) in grouped.enumerated() {
            let time = pair.key
            let group = pair.value
            let texts = group.map { $0.text }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let mainText = texts.first ?? ""
            let inlineTranslation = texts.count > 1 ? texts.last : nil

            var spans: [LyricSpan]
            if let wordRow = group.first(where: { !($0.words ?? []).isEmpty }),
               let words = wordRow.words, !words.isEmpty {
                spans = [LyricSpan(time: time, text: "")]
                spans.append(contentsOf: words)
                spans.append(LyricSpan(time: words[words.count - 1].time, text: ""))
            } else {
                spans = [
                    LyricSpan(time: time, text: ""),
                    LyricSpan(time: time, text: normalize(mainText)),
                ]
            }

            if spans.map({ $0.text }).joined().isEmpty { continue }
            if isMetadata(spans.map { $0.text }.joined()) { continue }

            let translationText = nearest(rows: translations, to: time)
                ?? translations.safe(index)?.text
                ?? inlineTranslation

            entries.append(
                LyricEntry(
                    spans: spans,
                    translation: translationText?.nilIfBlank,
                    romanization: nil
                )
            )
        }
        return entries
    }

    private static func krcLanguageBlocks(_ krc: String) -> [LanguageBlock] {
        var blocks: [LanguageBlock] = []
        var current: LanguageBlock?

        for rawLine in krc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = languageRegex.firstMatch(in: line, range: line.nsRange) {
                if var finished = current, !finished.rows.isEmpty {
                    finished.hasText = finished.rows.contains { !$0.text.isEmpty }
                    blocks.append(finished)
                }
                let language = Int(line.substring(with: match.range(at: 1))) ?? 0
                current = LanguageBlock(language: language, isSyllableStyle: false, hasText: false, rows: [])
                continue
            }
            guard var block = current else { continue }
            guard let match = krcLineRegex.firstMatch(in: line, range: line.nsRange) else { continue }
            let start = Float(line.substring(with: match.range(at: 1))) ?? 0
            let body = line.substring(with: match.range(at: 3))
            let words = krcWordRegex.matches(in: body, range: body.nsRange)
            if !words.isEmpty {
                block.isSyllableStyle = true
                block.rows.append((start, words.map { body.substring(with: $0.range(at: 3)) }.joined()))
            } else if !body.isEmpty {
                block.rows.append((start, body))
            }
            current = block
        }

        if var finished = current, !finished.rows.isEmpty {
            finished.hasText = finished.rows.contains { !$0.text.isEmpty }
            blocks.append(finished)
        }
        return blocks
    }

    /// Android `nearestText`：按时间最近取翻译；超过 3 秒视为对不上，宁可留空也不串行。
    private static func nearest(rows: [TimedText], to time: Float) -> String? {
        var best: TimedText?
        var bestDiff = Float.greatestFiniteMagnitude
        for row in rows {
            let diff = abs(row.time - time)
            if diff < bestDiff {
                bestDiff = diff
                best = row
            }
        }
        guard bestDiff <= 3000 else { return nil }
        return best?.text
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 制作人员署名不是歌词，不上屏（对齐 Android 的 `isNonLyricMetadata`）。
    private static let metadataKeywords = [
        "作词", "作曲", "编曲", "制作人", "监制", "混音", "母带", "录音", "和声",
        "统筹", "发行", "出品", "词：", "曲：", "编：", "原唱", "演唱：",
        "Lyrics by", "Composed by", "Arranged by", "Produced by", "Mixed by", "Mastered by",
        "纯音乐，请欣赏", "此歌曲为没有填词的纯音乐",
    ]

    private static func isMetadata(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return metadataKeywords.contains { trimmed.contains($0) }
    }
}

// MARK: - 小工具

private extension String {
    var nsRange: NSRange { NSRange(startIndex..<endIndex, in: self) }

    func substring(with range: NSRange) -> String {
        guard let range = Range(range, in: self) else { return "" }
        return String(self[range])
    }

    /// NSRange 的 location 是 UTF-16 偏移，不能直接用 Character offset 换算（emoji/组合字符会错位）。
    func substring(fromUTF16 location: Int) -> String {
        let ns = self as NSString
        guard location >= 0, location <= ns.length else { return "" }
        return ns.substring(from: location)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension NSRegularExpression {
    func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: string, options: [], range: range)
    }

    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }
}

private extension Array {
    func safe(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
