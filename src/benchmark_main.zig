const std = @import("std");

const b = @import("benchmark");
const root = @import("benchmark_root");

pub const main = if (@hasDecl(std.process, "Init")) main016 else main015;

fn main015() !u8 {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    const opt: b.Options = try .parse(&args, .{});
    return @intFromBool(!try b.runModuleBenchmarks(root, allocator, opt));
}

fn main016(init: std.process.Init) !u8 {
    const allocator = std.heap.smp_allocator;
    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    const opt: b.Options = try .parse(&args, .{ .io = init.io });
    return @intFromBool(!try b.runModuleBenchmarks(root, allocator, opt));
}
