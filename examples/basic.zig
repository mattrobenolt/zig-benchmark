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
    var args = std.process.args();
    const allocator = std.heap.smp_allocator;

    const benchmarks = [_]bench.Spec{
        .{ .name = "BenchmarkSum", .func = benchmarkSum },
        .{ .name = "BenchmarkSumN", .func = benchmarkSumN },
        .{ .name = "BenchmarkAlloc", .func = benchmarkAlloc },
    };

    const options: bench.Options = try .parse(&args, .{
        .benchtime = .{ .duration_ns = 100 * std.time.ns_per_ms },
        .benchmem = true,
    });

    _ = try bench.runBenchmarks(allocator, &benchmarks, options);
}
