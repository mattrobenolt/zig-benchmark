const std = @import("std");

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

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var args = std.process.args();
    const options: bench.Options = try .parse(&args, .{
        .benchtime = .{ .duration_ns = 100 * std.time.ns_per_ms },
    });

    const benchmarks = [_]bench.Spec{
        .{ .name = "BenchmarkFilter/Substring", .func = benchmarkFilterSubstring },
        .{ .name = "BenchmarkFilter/Prefix", .func = benchmarkFilterPrefix },
        .{ .name = "BenchmarkFilter/Suffix", .func = benchmarkFilterSuffix },
        .{ .name = "BenchmarkFilter/Exact", .func = benchmarkFilterExact },
        .{ .name = "BenchmarkFilter/Glob", .func = benchmarkFilterGlob },
        .{ .name = "BenchmarkFilter/Mixed", .func = benchmarkFilterMixed },
    };

    _ = try bench.runBenchmarks(allocator, &benchmarks, options);
}
