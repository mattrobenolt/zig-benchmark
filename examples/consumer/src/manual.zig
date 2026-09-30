const std = @import("std");
const bench = @import("benchmark");
const benchmarks = @import("benchmarks.zig");

pub fn main(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    const options: bench.Options = try .parse(&args, .{ .io = init.io });
    return @intFromBool(!try bench.runModuleBenchmarks(benchmarks, std.heap.smp_allocator, options));
}
