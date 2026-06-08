const std = @import("std");
const bench = @import("benchmark");

fn benchmarkSum(b: *bench.B) !void {
    var sink: u64 = 0;
    while (try b.loop()) {
        var i: u64 = 0;
        while (i < 1024) : (i += 1) sink +%= i;
    }
    b.keepAlive(sink);
    b.setBytes(1024 * @sizeOf(u64));
}

fn benchmarkSumN(b: *bench.B) !void {
    var sink: u64 = 0;
    var n: u64 = 0;
    while (n < b.n) : (n += 1) {
        var i: u64 = 0;
        while (i < 1024) : (i += 1) sink +%= i;
    }
    b.keepAlive(sink);
    b.setBytes(1024 * @sizeOf(u64));
}

fn benchmarkAlloc(b: *bench.B) !void {
    while (try b.loop()) {
        const memory = try b.allocator.alloc(u8, 256);
        defer b.allocator.free(memory);
        b.keepAlive(memory.ptr);
    }
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const benchmarks = [_]bench.InternalBenchmark{
        .{ .name = "BenchmarkSum", .func = benchmarkSum },
        .{ .name = "BenchmarkSumN", .func = benchmarkSumN },
        .{ .name = "BenchmarkAlloc", .func = benchmarkAlloc },
    };

    var cli = try bench.parseCliOptions(allocator, .{
        .benchtime = .{ .duration_ns = 100 * std.time.ns_per_ms },
        .benchmem = true,
    });
    defer cli.deinit();

    _ = try bench.runBenchmarks(allocator, &benchmarks, cli.options);
}
