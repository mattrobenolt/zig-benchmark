const std = @import("std");

pub const BenchmarkOptions = struct {
    name: []const u8 = "benchmark",
    dependency: *std.Build.Dependency,
    root_module: *std.Build.Module,
};

pub fn addTest(b: *std.Build, options: BenchmarkOptions) *std.Build.Step.Compile {
    return addTestModule(b, .{
        .name = options.name,
        .benchmark_module = options.dependency.module("benchmark"),
        .root_module = options.root_module,
    });
}

pub fn addRunTest(b: *std.Build, options: BenchmarkOptions) *std.Build.Step.Run {
    return b.addRunArtifact(addTest(b, options));
}

const ModuleBenchmarkOptions = struct {
    name: []const u8 = "benchmark",
    benchmark_module: *std.Build.Module,
    root_module: *std.Build.Module,
};

fn addTestModule(b: *std.Build, options: ModuleBenchmarkOptions) *std.Build.Step.Compile {
    const write_files = b.addWriteFiles();
    const main_source = write_files.add("benchmark-main.zig", @embedFile("src/benchmark_main.zig"));

    const target = options.root_module.resolved_target orelse b.graph.host;
    const optimize = options.root_module.optimize orelse .Debug;

    options.root_module.addImport("benchmark", options.benchmark_module);

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = b.createModule(.{
            .root_source_file = main_source,
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("benchmark", options.benchmark_module);
    exe.root_module.addImport("benchmark_root", options.root_module);
    return exe;
}

fn addExample(
    b: *std.Build,
    check: *std.Build.Step,
    module: *std.Build.Module,
    filter_module: *std.Build.Module,
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
    exe.root_module.addImport("benchmark_filter", filter_module);
    check.dependOn(&exe.step);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    return run;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const check = b.step("check", "Compile tests, examples, and generated benchmark runner without running");

    const filter_module = b.addModule("benchmark_filter", .{
        .root_source_file = b.path("src/filter.zig"),
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("benchmark", .{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("benchmark_filter", filter_module);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("benchmark_filter", filter_module);

    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    check.dependOn(&tests.step);

    const filter_tests = b.addTest(.{ .root_module = filter_module });
    test_step.dependOn(&b.addRunArtifact(filter_tests).step);
    check.dependOn(&filter_tests.step);

    const run_basic = addExample(b, check, module, filter_module, target, optimize, "basic", "examples/basic.zig");
    const run_basic_step = b.step("run-example", "Run the basic benchmark example");
    run_basic_step.dependOn(&run_basic.step);

    const run_compare = addExample(
        b,
        check,
        module,
        filter_module,
        target,
        optimize,
        "compare",
        "examples/compare.zig",
    );
    const run_compare_step = b.step("run-compare", "Run the comparison benchmark example");
    run_compare_step.dependOn(&run_compare.step);

    const filter_benchmark_module = b.createModule(.{
        .root_source_file = b.path("benchmarks/filter.zig"),
        .target = target,
        .optimize = optimize,
    });
    filter_benchmark_module.addImport("benchmark_filter", filter_module);

    const filter_benchmark = addTestModule(b, .{
        .name = "filter-benchmark",
        .benchmark_module = module,
        .root_module = filter_benchmark_module,
    });
    check.dependOn(&filter_benchmark.step);
    const run_filter_benchmark = b.addRunArtifact(filter_benchmark);
    if (b.args) |args| run_filter_benchmark.addArgs(args);

    const run_benchmark_step = b.step("run-benchmark", "Run internal benchmarks");
    run_benchmark_step.dependOn(&run_filter_benchmark.step);

    const run_consumer = b.addSystemCommand(&.{
        b.graph.zig_exe, "build", "bench", "--", "--count=2", "--benchtime=100x", "--benchmem",
    });
    run_consumer.setCwd(b.path("examples/consumer"));
    const run_consumer_step = b.step("run-consumer", "Run the external consumer integration example");
    run_consumer_step.dependOn(&run_consumer.step);
}
