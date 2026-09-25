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

pub const main = if (@hasDecl(std.process, "Init")) main016 else main015;

fn main015() !void {
    var args = try std.process.argsWithAllocator(std.heap.smp_allocator);
    defer args.deinit();
    try run(&args, .{});
}

fn main016(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(std.heap.smp_allocator);
    defer args.deinit();
    try run(&args, .{ .io = init.io });
}

fn run(args: anytype, defaults: bench.Options) !void {
    const allocator = std.heap.smp_allocator;

    const benchmarks = [_]bench.Spec{
        .{ .name = "BenchmarkSum", .func = benchmarkSum },
        .{ .name = "BenchmarkSumN", .func = benchmarkSumN },
        .{ .name = "BenchmarkAlloc", .func = benchmarkAlloc },
    };

    var options = defaults;
    options.benchtime = .{ .duration_ns = 100 * std.time.ns_per_ms };
    options.benchmem = true;
    options = try .parse(args, options);

    _ = try bench.runBenchmarks(allocator, &benchmarks, options);
}
