const std = @import("std");

const b = @import("benchmark");
const root = @import("benchmark_root");

pub fn main(init: std.process.Init) !u8 {
    var args = try init.minimal.args.iterate();
    defer args.deinit();
    const opt: b.Options = try .parse(&args, .{ .io = init.io });
    return @intFromBool(!try b.runModuleBenchmarks(root, init.gpa, opt));
}
