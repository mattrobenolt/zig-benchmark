const std = @import("std");

const b = @import("benchmark");
const root = @import("benchmark_root");

pub fn main() !u8 {
    const allocator = std.heap.smp_allocator;
    var args = std.process.args();
    const opt: b.Options = try .parse(&args, .{});
    return @intFromBool(!try b.runModuleBenchmarks(root, allocator, opt));
}
