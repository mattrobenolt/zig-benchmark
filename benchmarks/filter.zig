const bench = @import("benchmark");
const filter = @import("benchmark_filter");

const name = "BenchmarkAsciiCount/Table";
const cases = [_]struct {
    pattern: []const u8,
    expected: bool,
}{
    .{ .pattern = "Ascii", .expected = true },
    .{ .pattern = "^BenchmarkAscii", .expected = true },
    .{ .pattern = "Table$", .expected = true },
    .{ .pattern = "^BenchmarkAsciiCount/Table$", .expected = true },
    .{ .pattern = "Ascii*Table", .expected = true },
    .{ .pattern = "^Benchmark*/*Table$", .expected = true },
    .{ .pattern = "^Benchmark*/*Scalar$", .expected = false },
};

pub fn benchmarkFilter(b: *bench.B) !void {
    _ = try b.run("Substring", benchmarkFilterSubstring);
    _ = try b.run("Prefix", benchmarkFilterPrefix);
    _ = try b.run("Suffix", benchmarkFilterSuffix);
    _ = try b.run("Exact", benchmarkFilterExact);
    _ = try b.run("Glob", benchmarkFilterGlob);
    _ = try b.run("Mixed", benchmarkFilterMixed);
}

fn benchmarkFilterSubstring(b: *bench.B) !void {
    var matched = false;
    while (try b.loop()) {
        matched = filter.matches(b.blackBox("Ascii"), b.blackBox(name));
    }
    b.keepAlive(matched);
}

fn benchmarkFilterPrefix(b: *bench.B) !void {
    var matched = false;
    while (try b.loop()) {
        matched = filter.matches(b.blackBox("^BenchmarkAscii"), b.blackBox(name));
    }
    b.keepAlive(matched);
}

fn benchmarkFilterSuffix(b: *bench.B) !void {
    var matched = false;
    while (try b.loop()) {
        matched = filter.matches(b.blackBox("Table$"), b.blackBox(name));
    }
    b.keepAlive(matched);
}

fn benchmarkFilterExact(b: *bench.B) !void {
    var matched = false;
    while (try b.loop()) {
        matched = filter.matches(b.blackBox("^BenchmarkAsciiCount/Table$"), b.blackBox(name));
    }
    b.keepAlive(matched);
}

fn benchmarkFilterGlob(b: *bench.B) !void {
    var matched = false;
    while (try b.loop()) {
        matched = filter.matches(b.blackBox("^Benchmark*/*Table$"), b.blackBox(name));
    }
    b.keepAlive(matched);
}

fn benchmarkFilterMixed(b: *bench.B) !void {
    var matched_count: usize = 0;
    while (try b.loop()) {
        var count: usize = 0;
        inline for (cases) |case| {
            if (filter.matches(b.blackBox(case.pattern), b.blackBox(name)) == case.expected) count += 1;
        }
        matched_count = count;
    }
    b.keepAlive(matched_count);
}
