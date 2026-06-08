const std = @import("std");
const benchmark = @import("benchmark");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const benchmark_dep = b.dependency("benchmark", .{
        .target = target,
        .optimize = optimize,
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/benchmarks.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_benchmarks = benchmark.addRunTest(b, .{
        .dependency = benchmark_dep,
        .root_module = root_module,
    });
    if (b.args) |args| run_benchmarks.addArgs(args);

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_benchmarks.step);
}
