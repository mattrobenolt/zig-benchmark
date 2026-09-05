const bench = @import("benchmark");

pub fn benchmarkNested(b: *bench.B) !void {
    _ = try b.run("Alloc", alloc);
}

fn alloc(b: *bench.B) !void {
    while (try b.loop()) {
        const bytes = try b.allocator.alloc(u8, 64);
        defer b.allocator.free(bytes);
        b.keepAlive(bytes.ptr);
    }
    b.setBytes(64);
    try b.reportMetric(1, "items/op");
}
