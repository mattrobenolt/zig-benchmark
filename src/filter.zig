const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub fn matches(pattern: []const u8, name: []const u8) bool {
    var glob = pattern;
    const anchor_start = mem.startsWith(u8, glob, "^");
    if (anchor_start) glob = glob[1..];

    const anchor_end = mem.endsWith(u8, glob, "$");
    if (anchor_end) glob = glob[0 .. glob.len - 1];

    if (!mem.containsAtLeast(u8, glob, 1, "*")) {
        if (anchor_start and anchor_end) return mem.eql(u8, name, glob);
        if (anchor_start) return mem.startsWith(u8, name, glob);
        if (anchor_end) return mem.endsWith(u8, name, glob);
        return mem.containsAtLeast(u8, name, 1, glob);
    }

    if (anchor_start and anchor_end) return globMatch(glob, name);
    if (anchor_start) {
        var end: usize = 0;
        while (end <= name.len) : (end += 1) {
            if (globMatch(glob, name[0..end])) return true;
        }
        return false;
    }
    if (anchor_end) {
        var start: usize = 0;
        while (start <= name.len) : (start += 1) {
            if (globMatch(glob, name[start..])) return true;
        }
        return false;
    }

    var start: usize = 0;
    while (start <= name.len) : (start += 1) {
        var end = start;
        while (end <= name.len) : (end += 1) {
            if (globMatch(glob, name[start..end])) return true;
        }
    }
    return false;
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    var pattern_index: usize = 0;
    var text_index: usize = 0;
    var star_index: ?usize = null;
    var retry_text_index: usize = 0;

    while (text_index < text.len) {
        if (pattern_index < pattern.len and pattern[pattern_index] == '*') {
            star_index = pattern_index;
            retry_text_index = text_index;
            pattern_index += 1;
        } else if (pattern_index < pattern.len and pattern[pattern_index] == text[text_index]) {
            pattern_index += 1;
            text_index += 1;
        } else if (star_index) |star| {
            pattern_index = star + 1;
            retry_text_index += 1;
            text_index = retry_text_index;
        } else {
            return false;
        }
    }

    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;
    return pattern_index == pattern.len;
}

test "filter matches substrings anchors and globs" {
    try testing.expect(matches("Alloc", "BenchmarkAllocPerLine"));
    try testing.expect(!matches("Table", "BenchmarkAllocPerLine"));

    try testing.expect(matches("^BenchmarkAscii", "BenchmarkAsciiCount/Table"));
    try testing.expect(!matches("^Ascii", "BenchmarkAsciiCount/Table"));

    try testing.expect(matches("Table$", "BenchmarkAsciiCount/Table"));
    try testing.expect(!matches("Table$", "BenchmarkAsciiCount/TableLarge"));

    try testing.expect(matches("^BenchmarkAsciiCount/Table$", "BenchmarkAsciiCount/Table"));
    try testing.expect(!matches("^BenchmarkAsciiCount/Table$", "BenchmarkAsciiCount/TableLarge"));

    try testing.expect(matches("Ascii*Table", "BenchmarkAsciiCount/Table"));
    try testing.expect(matches("^Benchmark*/*Table$", "BenchmarkAsciiCount/Table"));
    try testing.expect(!matches("^Benchmark*/*Scalar$", "BenchmarkAsciiCount/Table"));
}
