# zig-benchmark

A Zig benchmark package modeled closely on Go 1.26's `testing.B` runner.

The core shape is intentionally Go-ish, with Zig names and error returns where Go uses goroutine exits:

```zig
fn benchmarkThing(b: *bench.B) !void {
    var value: u64 = 0;
    while (try b.loop()) {
        value +%= doThing();
    }
    b.keepAlive(value);
}
```

`B.N`-style benchmarks are supported as `b.n`:

```zig
fn benchmarkThingN(b: *bench.B) !void {
    var i: u64 = 0;
    while (i < b.n) : (i += 1) {
        _ = doThing();
    }
}
```

Implemented so far: `B.loop`, `startTimer`, `stopTimer`, `resetTimer`, `elapsed`, `setBytes`, `reportMetric`, `reportAllocs`, sub-benchmarks via `run`, `runParallel`/`PB.next`, `setParallelism`, `benchmark`, `runBenchmarks`, CLI parsing, substring filtering, environment headers, Go-style iteration prediction, Go benchmark-result formatting, and allocation metrics for allocations made through `b.allocator`.

Use `b.keepAlive(value)` or `bench.keepAlive(value)` to keep measured work observable. Zig cannot do Go's `B.Loop` compiler rewrite from a library, so this stays explicit:

```zig
fn benchmarkThing(b: *bench.B) !void {
    var sink: u64 = 0;
    while (try b.loop()) {
        sink +%= doThing();
    }
    b.keepAlive(sink);
}
```

Use `b.blackBox(value)` or `bench.blackBox(value)` when you want to hide an input value from constant propagation.

Use `b.allocator` in the code under benchmark when you want `B/op` and `allocs/op`:

```zig
fn benchmarkAlloc(b: *bench.B) !void {
    while (try b.loop()) {
        const memory = try b.allocator.alloc(u8, 256);
        defer b.allocator.free(memory);
    }
}
```

For command-line handling, examples use `parseCliOptions`, which walks `std.process.ArgIterator` instead of allocating an argument array:

```zig
var cli = try bench.parseCliOptions(allocator, .{
    .benchtime = .{ .duration_ns = 250 * std.time.ns_per_ms },
    .benchmem = true,
});
defer cli.deinit();

_ = try bench.runBenchmarks(allocator, &benchmarks, cli.options);
```

Supported flags:

```text
--count=N
--benchtime=250ms
--benchtime=1000x
--filter=substring
--benchmem
--parallelism=N
--no-env
```

The runner emits Zig environment metadata before benchmark rows by default:

```text
zig_os: macos
zig_arch: aarch64
zig_abi: none
zig_cpu: apple_m1
zig_mode: ReleaseFast
```

Writers are flushed after every benchmark row so long benchmark suites stream useful output instead of hoarding it like a dragon.

Run the checks and examples:

```sh
zig build test
zig build run-example -- --count=2 --filter=Alloc
zig build run-compare -Doptimize=ReleaseFast -- --count=10 --benchtime=100ms
```

The comparison example is shaped for `benchstat`:

```sh
zig build run-compare -Doptimize=ReleaseFast -- --count=10 --benchtime=100ms > compare.txt
benchstat -row .name -col .fullname compare.txt
```

`examples/compare.zig` compares two ASCII lowercase counting implementations as `BenchmarkAsciiCount/Scalar` and `BenchmarkAsciiCount/Table`, plus an allocation-heavy benchmark to exercise `B/op` and `allocs/op`.

## License

MIT.
