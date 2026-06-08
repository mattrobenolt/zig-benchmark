const std = @import("std");

fn addExample(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    source: []const u8,
) *std.Build.Step.Run {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("benchmark", module);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    return run;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("benchmark", .{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const run_basic = addExample(b, module, target, optimize, "basic", "examples/basic.zig");
    const run_basic_step = b.step("run-example", "Run the basic benchmark example");
    run_basic_step.dependOn(&run_basic.step);

    const run_compare = addExample(b, module, target, optimize, "compare", "examples/compare.zig");
    const run_compare_step = b.step("run-compare", "Run the comparison benchmark example");
    run_compare_step.dependOn(&run_compare.step);
}
