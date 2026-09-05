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

    const check = b.step("check", "Compile generated and manual runners without running");
    const benchmarks = benchmark.addTest(b, .{
        .dependency = benchmark_dep,
        .root_module = root_module,
    });
    check.dependOn(&benchmarks.step);

    const manual = b.addExecutable(.{
        .name = "manual",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/manual.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    manual.root_module.addImport("benchmark", benchmark_dep.module("benchmark"));
    check.dependOn(&manual.step);
    const run_manual = b.addRunArtifact(manual);
    if (b.args) |args| run_manual.addArgs(args);
    b.step("manual", "Run the custom benchmark runner").dependOn(&run_manual.step);
}
