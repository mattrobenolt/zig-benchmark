const std = @import("std");

pub const BenchmarkOptions = struct {
    name: []const u8 = "benchmark",
    dependency: *std.Build.Dependency,
    root_module: *std.Build.Module,
};

pub fn addTest(b: *std.Build, options: BenchmarkOptions) *std.Build.Step.Compile {
    const write_files = b.addWriteFiles();
    const main_source = write_files.add("benchmark-main.zig", @embedFile("src/benchmark_main.zig"));

    const target = options.root_module.resolved_target orelse b.graph.host;
    const optimize = options.root_module.optimize orelse .Debug;

    const benchmark_module = options.dependency.module("benchmark");
    options.root_module.addImport("benchmark", benchmark_module);

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = b.createModule(.{
            .root_source_file = main_source,
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("benchmark", benchmark_module);
    exe.root_module.addImport("benchmark_root", options.root_module);
    return exe;
}

pub fn addRunTest(b: *std.Build, options: BenchmarkOptions) *std.Build.Step.Run {
    return b.addRunArtifact(addTest(b, options));
}

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

    const run_consumer = b.addSystemCommand(&.{ "zig", "build", "bench", "--", "--count=2", "--benchtime=100x", "--benchmem" });
    run_consumer.setCwd(b.path("examples/consumer"));
    const run_consumer_step = b.step("run-consumer", "Run the external consumer integration example");
    run_consumer_step.dependOn(&run_consumer.step);
}
