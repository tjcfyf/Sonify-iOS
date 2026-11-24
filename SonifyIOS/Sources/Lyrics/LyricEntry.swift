import Foundation

/// 词级片段。`time` 是**该词高亮结束的时间（毫秒）**，与 Android `LyricEntry.mainLyric` 的
/// `Pair<Float, String>` 语义完全一致——不是开始时间。开始时间取前一个片段的 `time`。
struct LyricSpan: Equatable {
    var time: Float
    var text: String
}

/// 一行歌词。对齐 Android `LyricEntry`：
/// `mainLyric` 首元素是行起点锚点（文本为空），末尾再补一个空锚点，中间是逐词片段。
struct LyricEntry: Equatable {
    var spans: [LyricSpan]
    var translation: String?
    var romanization: String?

    var startTime: Float { spans.first?.time ?? 0 }
    var endTime: Float { spans.last?.time ?? startTime }
    var plainText: String { spans.map { $0.text }.joined() }
    var isWordLevel: Bool { spans.count > 2 }
}

extension Array where Element == LyricEntry {
    /// 当前时间（毫秒）命中的行索引；都给不出时返回 0。
    func currentIndex(at timeMs: Float) -> Int {
        guard !isEmpty else { return 0 }
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if self[mid].startTime <= timeMs {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

/// 单行内某词的播放进度（0…1）。`index` 是 spans 下标（跳过首锚点）。
func spanProgress(in entry: LyricEntry, spanIndex: Int, timeMs: Float) -> Double {
    guard entry.spans.indices.contains(spanIndex), spanIndex > 0 else { return 0 }
    let end = entry.spans[spanIndex].time
    let start = entry.spans[spanIndex - 1].time
    guard end > start else { return timeMs >= end ? 1 : 0 }
    return Double(min(max((timeMs - start) / (end - start), 0), 1))
}
