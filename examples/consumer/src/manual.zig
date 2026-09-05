const std = @import("std");
const bench = @import("benchmark");
const benchmarks = @import("benchmarks.zig");

pub const main = if (@hasDecl(std.process, "Init")) main016 else main015;

fn main015() !u8 {
    var args = try std.process.argsWithAllocator(std.heap.smp_allocator);
    defer args.deinit();
    return run(try bench.Options.parse(&args, .{}));
}

fn main016(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    return run(try bench.Options.parse(&args, .{ .io = init.io }));
}

fn run(options: bench.Options) !u8 {
    return @intFromBool(!try bench.runModuleBenchmarks(benchmarks, std.heap.smp_allocator, options));
}
