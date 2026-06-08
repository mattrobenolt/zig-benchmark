const bench = @import("benchmark");

pub fn benchmarkAdd(b: *bench.B) !void {
    var x: u64 = 0;
    while (try b.loop()) x +%= 1;
    b.keepAlive(x);
}

pub fn BenchmarkAlloc(b: *bench.B) !void {
    while (try b.loop()) {
        const memory = try b.allocator.alloc(u8, 32);
        defer b.allocator.free(memory);
    }
}
