const std = @import("std");
const benchmark = @import("benchmark");
const benchmark_root = @import("benchmark_root");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var cli = try benchmark.parseCliOptions(allocator, .{});
    defer cli.deinit();

    if (!try benchmark.runModuleBenchmarks(benchmark_root, allocator, cli.options)) {
        std.process.exit(1);
    }
}
