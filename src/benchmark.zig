//! A Zig benchmark runner modeled after Go's testing.B.

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const time = std.time;
const Timer = @import("timer.zig").Timer;
const Io = std.Io;
const Thread = std.Thread;
const testing = std.testing;
const doNotOptimizeAway = mem.doNotOptimizeAway;
const builtin = @import("builtin");

const filter = @import("benchmark_filter");

const AtomicU64 = std.atomic.Value(u64);
const has_io = @hasDecl(Io, "Clock");
const OptionalIo = if (has_io) ?Io else void;

pub const Error = error{
    BenchmarkFailed,
    BenchmarkSkipped,
    TimerUnsupported,
    InvalidMetricUnit,
    MissingIo,
};

pub const Options = struct {
    /// Required by measurement and runner entrypoints on Zig 0.16; unused on 0.15.
    io: OptionalIo = if (has_io) null else {},
    benchtime: DurationOrCount = .{ .duration_ns = time.ns_per_s },
    benchmem: bool = false,
    count: usize = 1,
    parallelism: usize = 1,
    filter: ?[]const u8 = null,
    emit_environment: bool = true,
    help: bool = false,
    writer: ?*Io.Writer = null,

    /// Accepts either supported standard-library argument iterator. Skips argv[0].
    /// Returned filter strings borrow the iterator's storage.
    pub fn parse(args: anytype, defaults: Options) !Options {
        _ = args.skip();

        var options = defaults;
        while (args.next()) |arg| {
            if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
                options.help = true;
            } else if (mem.eql(u8, arg, "--benchmem") or mem.eql(u8, arg, "-m")) {
                options.benchmem = true;
            } else if (mem.eql(u8, arg, "--no-env")) {
                options.emit_environment = false;
            } else if (mem.eql(u8, arg, "--count")) {
                options.count = try std.fmt.parseInt(usize, try nextFlagValue(args), 10);
            } else if (mem.startsWith(u8, arg, "--count=")) {
                options.count = try std.fmt.parseInt(usize, arg["--count=".len..], 10);
            } else if (try shortFlagValue(arg, "-c", args)) |value| {
                options.count = try std.fmt.parseInt(usize, value, 10);
            } else if (mem.eql(u8, arg, "--benchtime")) {
                options.benchtime = try .parse(try nextFlagValue(args));
            } else if (mem.startsWith(u8, arg, "--benchtime=")) {
                options.benchtime = try .parse(arg["--benchtime=".len..]);
            } else if (try shortFlagValue(arg, "-t", args)) |value| {
                options.benchtime = try .parse(value);
            } else if (mem.eql(u8, arg, "--filter")) {
                options.filter = try nextFlagValue(args);
            } else if (mem.startsWith(u8, arg, "--filter=")) {
                options.filter = arg["--filter=".len..];
            } else if (try shortFlagValue(arg, "-f", args)) |value| {
                options.filter = value;
            } else if (mem.eql(u8, arg, "--parallelism")) {
                options.parallelism = try std.fmt.parseInt(usize, try nextFlagValue(args), 10);
            } else if (mem.startsWith(u8, arg, "--parallelism=")) {
                options.parallelism = try std.fmt.parseInt(usize, arg["--parallelism=".len..], 10);
            } else if (try shortFlagValue(arg, "-p", args)) |value| {
                options.parallelism = try std.fmt.parseInt(usize, value, 10);
            } else return error.UnknownBenchmarkOption;
        }

        if (options.help) return options;
        if (options.count == 0) return error.InvalidCount;
        if (options.parallelism == 0) options.parallelism = 1;

        return options;
    }
};

fn nextFlagValue(args: anytype) ![]const u8 {
    return args.next() orelse error.MissingBenchmarkOptionValue;
}

fn shortFlagValue(arg: []const u8, flag: []const u8, args: anytype) !?[]const u8 {
    if (!mem.startsWith(u8, arg, flag)) return null;
    const value = arg[flag.len..];
    if (value.len == 0) return @as(?[]const u8, try nextFlagValue(args));
    if (mem.startsWith(u8, value, "=")) return value[1..];
    return value;
}

pub const DurationOrCount = union(enum) {
    duration_ns: u64,
    count: u64,

    pub fn parse(s: []const u8) !DurationOrCount {
        if (mem.endsWith(u8, s, "x")) {
            const n = try std.fmt.parseInt(u64, s[0 .. s.len - 1], 10);
            if (n == 0) return error.InvalidCount;
            return .{ .count = n };
        }

        return .{ .duration_ns = try parseDurationNs(s) };
    }
};

pub fn runModuleBenchmarks(comptime root: type, allocator: Allocator, options: Options) !bool {
    const benchmarks = comptime moduleBenchmarks(root);
    return runBenchmarks(allocator, &benchmarks, options);
}

fn moduleBenchmarks(comptime root: type) [countModuleBenchmarks(root)]Spec {
    @setEvalBranchQuota(100_000);
    var benchmarks: [countModuleBenchmarks(root)]Spec = undefined;
    var i: usize = 0;
    fillModuleBenchmarks(root, &benchmarks, &i);
    return benchmarks;
}

fn fillModuleBenchmarks(comptime root: type, benchmarks: anytype, i: *usize) void {
    @setEvalBranchQuota(100_000);
    const decls = @typeInfo(root).@"struct".decls;

    inline for (decls) |decl| {
        if (comptime isBenchmarkDecl(decl.name, @field(root, decl.name))) {
            benchmarks[i.*] = .{
                .name = normalizedBenchmarkName(decl.name),
                .func = @field(root, decl.name),
            };
            i.* += 1;
        } else if (comptime isBenchmarkModule(@field(root, decl.name))) {
            fillModuleBenchmarks(@field(root, decl.name), benchmarks, i);
        }
    }
}

fn countModuleBenchmarks(comptime root: type) comptime_int {
    @setEvalBranchQuota(100_000);
    const decls = @typeInfo(root).@"struct".decls;
    var count: comptime_int = 0;
    for (decls) |decl| {
        if (isBenchmarkDecl(decl.name, @field(root, decl.name))) {
            count += 1;
        } else if (isBenchmarkModule(@field(root, decl.name))) {
            count += countModuleBenchmarks(@field(root, decl.name));
        }
    }
    return count;
}

fn isBenchmarkModule(comptime value: anytype) bool {
    if (@TypeOf(value) != type) return false;
    return @typeInfo(value) == .@"struct";
}

fn isBenchmarkDecl(comptime name: []const u8, comptime value: anytype) bool {
    return isBenchmarkName(name) and isBenchmarkFunction(value);
}

fn isBenchmarkName(comptime name: []const u8) bool {
    return mem.startsWith(u8, name, "Benchmark") or mem.startsWith(u8, name, "benchmark");
}

fn isBenchmarkFunction(comptime value: anytype) bool {
    const info = @typeInfo(@TypeOf(value));
    const fn_info = switch (info) {
        .@"fn" => |fn_info| fn_info,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |fn_info| fn_info,
            else => return false,
        },
        else => return false,
    };

    if (fn_info.params.len != 1 or fn_info.params[0].type != *B) return false;
    const return_type = fn_info.return_type orelse return false;
    return @typeInfo(return_type) == .error_union and
        @typeInfo(return_type).error_union.payload == void;
}

fn normalizedBenchmarkName(comptime name: []const u8) []const u8 {
    if (mem.startsWith(u8, name, "Benchmark")) return name;
    return std.fmt.comptimePrint("Benchmark{s}", .{name["benchmark".len..]});
}

pub inline fn keepAlive(value: anytype) void {
    doNotOptimizeAway(value);
}

pub inline fn blackBox(value: anytype) @TypeOf(value) {
    var runtime_value = value;
    doNotOptimizeAway(&runtime_value);
    return runtime_value;
}

pub const Result = struct {
    n: u64 = 0,
    t_ns: u64 = 0,
    bytes: i64 = 0,
    mem_allocs: u64 = 0,
    mem_bytes: u64 = 0,
    extra: MetricMap = .empty,

    pub fn deinit(self: *Result, allocator: Allocator) void {
        freeMetricKeys(allocator, &self.extra);
        self.extra.deinit(allocator);
        self.* = undefined;
    }

    pub fn nsPerOp(self: *const Result) i64 {
        if (self.extra.get("ns/op")) |v| return @intFromFloat(v);
        if (self.n == 0) return 0;
        return @intCast(self.t_ns / self.n);
    }

    pub fn mbPerSec(self: *const Result) f64 {
        if (self.extra.get("MB/s")) |v| return v;
        if (self.bytes <= 0 or self.t_ns == 0 or self.n == 0) return 0;
        const bytes: f64 = @floatFromInt(self.bytes);
        const n: f64 = @floatFromInt(self.n);
        const seconds = @as(f64, @floatFromInt(self.t_ns)) / time.ns_per_s;
        return (bytes * n / 1e6) / seconds;
    }

    pub fn allocsPerOp(self: *const Result) i64 {
        if (self.extra.get("allocs/op")) |v| return @intFromFloat(v);
        if (self.n == 0) return 0;
        return @intCast(self.mem_allocs / self.n);
    }

    pub fn allocedBytesPerOp(self: *const Result) i64 {
        if (self.extra.get("B/op")) |v| return @intFromFloat(v);
        if (self.n == 0) return 0;
        return @intCast(self.mem_bytes / self.n);
    }

    pub fn format(self: *const Result, writer: *Io.Writer) !void {
        try writer.print("{d:>8}", .{self.n});

        const ns = self.extra.get("ns/op") orelse blk: {
            if (self.n == 0) break :blk 0;
            break :blk @as(f64, @floatFromInt(self.t_ns)) / @as(f64, @floatFromInt(self.n));
        };
        if (ns != 0) {
            try writer.writeByte('\t');
            try prettyPrint(writer, ns, "ns/op");
        }

        const mbs = self.mbPerSec();
        if (mbs != 0) try writer.print("\t{d:>7.2} MB/s", .{mbs});

        var it = self.extra.iterator();
        while (it.next()) |entry| {
            const unit = entry.key_ptr.*;
            if (mem.eql(u8, unit, "ns/op") or
                mem.eql(u8, unit, "MB/s") or
                mem.eql(u8, unit, "B/op") or
                mem.eql(u8, unit, "allocs/op")) continue;

            try writer.writeByte('\t');
            try prettyPrint(writer, entry.value_ptr.*, unit);
        }
    }

    pub fn formatMem(self: *const Result, writer: *Io.Writer) !void {
        try writer.print("{d:>8} B/op\t{d:>8} allocs/op", .{
            @as(u64, @intCast(self.allocedBytesPerOp())),
            @as(u64, @intCast(self.allocsPerOp())),
        });
    }
};

const MetricMap = std.StringArrayHashMapUnmanaged(f64);

pub const CountingAllocator = struct {
    child: Allocator,
    total_allocs: AtomicU64 = .init(0),
    total_bytes: AtomicU64 = .init(0),

    pub fn init(child: Allocator) CountingAllocator {
        return .{ .child = child };
    }

    pub fn allocator(self: *CountingAllocator) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn reset(self: *CountingAllocator) void {
        self.total_allocs.store(0, .seq_cst);
        self.total_bytes.store(0, .seq_cst);
    }

    pub fn allocs(self: *CountingAllocator) u64 {
        return self.total_allocs.load(.seq_cst);
    }

    pub fn bytes(self: *CountingAllocator) u64 {
        return self.total_bytes.load(.seq_cst);
    }

    fn record(self: *CountingAllocator, len: usize) void {
        _ = self.total_allocs.fetchAdd(1, .seq_cst);
        _ = self.total_bytes.fetchAdd(@intCast(len), .seq_cst);
    }

    fn recordGrowth(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len > old_len) _ = self.total_bytes.fetchAdd(@intCast(new_len - old_len), .seq_cst);
    }

    fn rawAlloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.record(len);
        return ptr;
    }

    fn rawResize(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.recordGrowth(memory.len, new_len);
        return true;
    }

    fn rawRemap(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.recordGrowth(memory.len, new_len);
        return ptr;
    }

    fn rawFree(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
    }

    const vtable: Allocator.VTable = .{
        .alloc = rawAlloc,
        .resize = rawResize,
        .remap = rawRemap,
        .free = rawFree,
    };
};

pub const B = struct {
    internal_allocator: Allocator,
    allocator: Allocator,
    counting_allocator: *CountingAllocator,
    name: []const u8 = "",
    n: u64 = 0,
    failed: bool = false,
    skipped: bool = false,

    bench_func: *const fn (*B) anyerror!void,
    bench_time: DurationOrCount,
    bytes: i64 = 0,
    timer: Timer,
    timer_on: bool = false,
    duration_ns: u64 = 0,
    start_allocs: u64 = 0,
    start_bytes: u64 = 0,
    net_allocs: u64 = 0,
    net_bytes: u64 = 0,
    show_alloc_result: bool = false,
    writer: ?*Io.Writer = null,
    benchmem: bool = false,
    filter_pattern: ?[]const u8 = null,
    result: Result = .{},
    parallelism: usize = 1,
    previous_n: u64 = 0,
    previous_duration_ns: u64 = 0,
    loop_state: LoopState = .{},
    has_sub: bool = false,
    missing_bytes: bool = false,
    extra: MetricMap = .empty,

    const LoopState = struct {
        n: u64 = 0,
        i: u64 = 0,
        done: bool = false,
    };

    pub fn init(allocator: Allocator, func: *const fn (*B) anyerror!void, options: Options) !B {
        if (has_io and options.io == null) return Error.MissingIo;
        const counting_allocator = try allocator.create(CountingAllocator);
        errdefer allocator.destroy(counting_allocator);
        counting_allocator.* = .init(allocator);

        return .{
            .internal_allocator = allocator,
            .allocator = counting_allocator.allocator(),
            .counting_allocator = counting_allocator,
            .bench_func = func,
            .bench_time = options.benchtime,
            .timer = if (has_io) try .start(options.io.?) else try .start(),
            .parallelism = options.parallelism,
            .writer = options.writer,
            .benchmem = options.benchmem,
            .filter_pattern = options.filter,
        };
    }

    pub fn deinit(self: *B) void {
        freeMetricKeys(self.internal_allocator, &self.extra);
        self.extra.deinit(self.internal_allocator);
        self.result.deinit(self.internal_allocator);
        self.internal_allocator.destroy(self.counting_allocator);
        self.* = undefined;
    }

    pub fn startTimer(self: *B) void {
        if (!self.timer_on) {
            self.start_allocs = self.counting_allocator.allocs();
            self.start_bytes = self.counting_allocator.bytes();
            self.timer.reset();
            self.timer_on = true;
        }
    }

    pub fn stopTimer(self: *B) void {
        if (self.timer_on) {
            self.duration_ns += self.timer.read();
            self.net_allocs += self.counting_allocator.allocs() - self.start_allocs;
            self.net_bytes += self.counting_allocator.bytes() - self.start_bytes;
            self.timer_on = false;
        }
    }

    pub fn resetTimer(self: *B) void {
        self.duration_ns = 0;
        self.net_allocs = 0;
        self.net_bytes = 0;
        if (self.timer_on) {
            self.start_allocs = self.counting_allocator.allocs();
            self.start_bytes = self.counting_allocator.bytes();
            self.timer.reset();
        }
        freeMetricKeys(self.internal_allocator, &self.extra);
        self.extra.clearRetainingCapacity();
    }

    pub fn elapsed(self: *B) u64 {
        var d = self.duration_ns;
        if (self.timer_on) d += self.timer.read();
        return d;
    }

    pub fn setBytes(self: *B, n: i64) void {
        self.bytes = n;
    }

    pub fn reportAllocs(self: *B) void {
        self.show_alloc_result = true;
    }

    pub fn reportMetric(self: *B, n: f64, unit: []const u8) !void {
        if (unit.len == 0) return Error.InvalidMetricUnit;
        for (unit) |c| if (std.ascii.isWhitespace(c)) return Error.InvalidMetricUnit;

        if (self.extra.getKey(unit)) |old_key| {
            try self.extra.put(self.internal_allocator, old_key, n);
            return;
        }
        const owned_unit = try self.internal_allocator.dupe(u8, unit);
        errdefer self.internal_allocator.free(owned_unit);
        try self.extra.put(self.internal_allocator, owned_unit, n);
    }

    pub fn fail(self: *B) Error!void {
        self.failed = true;
        return Error.BenchmarkFailed;
    }

    pub fn skip(self: *B) Error!void {
        self.skipped = true;
        return Error.BenchmarkSkipped;
    }

    pub fn loop(self: *B) !bool {
        if (self.loop_state.i < self.loop_state.n) {
            self.loop_state.i += 1;
            return true;
        }
        return self.loopSlowPath();
    }

    pub fn run(self: *B, name: []const u8, func: *const fn (*B) anyerror!void) !bool {
        self.has_sub = true;

        const full_name = if (self.name.len == 0)
            try self.internal_allocator.dupe(u8, name)
        else
            try std.fmt.allocPrint(self.internal_allocator, "{s}/{s}", .{ self.name, name });
        defer self.internal_allocator.free(full_name);

        if (self.filter_pattern) |pattern| {
            if (!filter.matchesAny(pattern, self.name) and !filter.matchesAny(pattern, full_name)) return true;
        }

        var sub: B = try .init(self.internal_allocator, func, .{
            .io = if (has_io) self.timer.io else {},
            .benchtime = self.bench_time,
            .benchmem = self.benchmem,
            .parallelism = self.parallelism,
            .writer = self.writer,
            .filter = self.filter_pattern,
        });
        defer sub.deinit();
        sub.name = full_name;

        try sub.run1AndMaybeLaunch();
        if (self.writer) |writer| try printBenchmarkResult(writer, sub.name, &sub, self.benchmem);
        if (!sub.failed and !sub.skipped) self.add(sub.result);
        if (sub.failed) self.failed = true;
        return !sub.failed;
    }

    pub fn runParallel(self: *B, body: *const fn (*PB) anyerror!void) !void {
        if (self.n == 0) return;

        var grain: u64 = 1;
        if (self.previous_n > 0 and self.previous_duration_ns > 0) {
            grain = 100_000 * self.previous_n / self.previous_duration_ns;
            if (grain < 1) grain = 1;
            if (grain > 10_000) grain = 10_000;
        }

        var global_n: AtomicU64 = .init(0);
        const cpu_count = Thread.getCpuCount() catch 1;
        const thread_count = @max(@as(usize, 1), self.parallelism * cpu_count);
        const threads = try self.internal_allocator.alloc(std.Thread, thread_count);
        defer self.internal_allocator.free(threads);

        var ctx: ParallelContext = .{
            .global_n = &global_n,
            .grain = grain,
            .b_n = self.n,
            .body = body,
            .failed = .init(0),
        };

        for (threads) |*thread| thread.* = try .spawn(.{}, parallelWorker, .{&ctx});
        for (threads) |thread| thread.join();

        if (ctx.failed.load(.seq_cst) != 0) return Error.BenchmarkFailed;
        if (global_n.load(.seq_cst) <= self.n and !self.failed) return self.fail();
    }

    pub fn setParallelism(self: *B, p: usize) void {
        if (p >= 1) self.parallelism = p;
    }

    pub inline fn keepAlive(_: *B, value: anytype) void {
        mem.doNotOptimizeAway(value);
    }

    pub inline fn blackBox(_: *B, value: anytype) @TypeOf(value) {
        var runtime_value = value;
        mem.doNotOptimizeAway(&runtime_value);
        return runtime_value;
    }

    fn run1AndMaybeLaunch(self: *B) !void {
        try self.runN(1);
        if (!self.failed and !self.skipped and !self.has_sub) try self.launch();
    }

    fn runN(self: *B, n: u64) !void {
        self.n = n;
        self.loop_state = .{};
        self.parallelism = @max(self.parallelism, 1);
        self.resetTimer();
        self.startTimer();
        self.bench_func(self) catch |err| switch (err) {
            Error.BenchmarkSkipped => self.skipped = true,
            Error.BenchmarkFailed => self.failed = true,
            else => return err,
        };
        self.stopTimer();
        self.previous_n = n;
        self.previous_duration_ns = self.duration_ns;

        if (self.loop_state.n > 0 and !self.loop_state.done and !self.failed) {
            self.failed = true;
            return Error.BenchmarkFailed;
        }
    }

    fn launch(self: *B) !void {
        if (self.loop_state.n == 0) switch (self.bench_time) {
            .count => |count| if (count > 1) try self.runN(count),
            .duration_ns => |goal| {
                var n: u64 = 1;
                while (!self.failed and self.duration_ns < goal and n < max_predict_iters) {
                    const last = n;
                    n = predictN(goal, self.n, self.duration_ns, last);
                    try self.runN(n);
                }
            },
        };

        self.result.deinit(self.internal_allocator);
        self.result = .{
            .n = self.n,
            .t_ns = self.duration_ns,
            .bytes = self.bytes,
            .mem_allocs = self.net_allocs,
            .mem_bytes = self.net_bytes,
            .extra = try cloneMetrics(self.internal_allocator, self.extra),
        };
    }

    fn loopSlowPath(self: *B) !bool {
        if (!self.timer_on) {
            try self.fail();
            return false;
        }

        if (self.loop_state.n == 0) {
            self.loop_state.n = switch (self.bench_time) {
                .count => |count| count,
                .duration_ns => 1,
            };
            self.n = 0;
            self.resetTimer();
            self.loop_state.i += 1;
            return true;
        }

        const more = switch (self.bench_time) {
            .count => false,
            .duration_ns => |goal| blk: {
                const t = self.elapsed();
                if (t >= goal) break :blk false;
                const prev = self.loop_state.n;
                self.loop_state.n = predictN(goal, prev, t, prev);
                break :blk prev < self.loop_state.n;
            },
        };

        if (!more) {
            self.stopTimer();
            self.n = self.loop_state.n;
            self.loop_state.done = true;
            return false;
        }

        self.loop_state.i += 1;
        return true;
    }

    fn add(self: *B, other: Result) void {
        self.result.n = 1;
        self.result.t_ns += @intCast(other.nsPerOp());
        if (other.bytes == 0) {
            self.missing_bytes = true;
            self.result.bytes = 0;
        }
        if (!self.missing_bytes) self.result.bytes += other.bytes;
        self.result.mem_allocs += @intCast(other.allocsPerOp());
        self.result.mem_bytes += @intCast(other.allocedBytesPerOp());
    }
};

pub const Function = *const fn (*B) anyerror!void;

pub const Spec = struct {
    name: []const u8,
    func: Function,
};

pub const PB = struct {
    global_n: *AtomicU64,
    grain: u64,
    cache: u64 = 0,
    b_n: u64,

    pub fn next(self: *PB) bool {
        if (self.cache == 0) {
            const n = self.global_n.fetchAdd(self.grain, .seq_cst) + self.grain;
            if (n <= self.b_n) {
                self.cache = self.grain;
            } else if (n < self.b_n + self.grain) {
                self.cache = self.b_n + self.grain - n;
            } else {
                return false;
            }
        }
        self.cache -= 1;
        return true;
    }
};

const ParallelContext = struct {
    global_n: *AtomicU64,
    grain: u64,
    b_n: u64,
    body: *const fn (*PB) anyerror!void,
    failed: AtomicU64,
};

fn parallelWorker(ctx: *ParallelContext) void {
    var pb: PB = .{ .global_n = ctx.global_n, .grain = ctx.grain, .b_n = ctx.b_n };
    ctx.body(&pb) catch ctx.failed.store(1, .seq_cst);
}

pub fn benchmark(allocator: Allocator, func: Function, options: Options) !Result {
    var b: B = try .init(allocator, func, options);
    defer b.deinit();
    try b.run1AndMaybeLaunch();
    return .{
        .n = b.result.n,
        .t_ns = b.result.t_ns,
        .bytes = b.result.bytes,
        .mem_allocs = b.result.mem_allocs,
        .mem_bytes = b.result.mem_bytes,
        .extra = try cloneMetrics(allocator, b.result.extra),
    };
}

pub fn runBenchmarks(allocator: Allocator, benchmarks: []const Spec, options: Options) !bool {
    if (has_io and options.io == null) return Error.MissingIo;
    var stdout_buf: [4096]u8 = undefined;
    var stdout = if (has_io)
        Io.File.stdout().writerStreaming(options.io.?, &stdout_buf)
    else
        std.fs.File.stdout().writerStreaming(&stdout_buf);
    const writer = options.writer orelse &stdout.interface;
    defer writer.flush() catch {};

    if (options.help) {
        try printUsage(writer);
        return true;
    }

    if (options.emit_environment) try emitEnvironment(writer);

    var ok = true;
    for (benchmarks) |entry| {
        if (options.filter) |pattern| {
            if (!filter.matchesAny(pattern, entry.name) and !filter.mayMatchAnyChild(pattern, entry.name)) continue;
        }

        var i: usize = 0;
        while (i < options.count) : (i += 1) {
            var run_options = options;
            run_options.writer = writer;

            var b: B = try .init(allocator, entry.func, run_options);
            defer b.deinit();
            b.name = entry.name;
            try b.run1AndMaybeLaunch();

            if (b.has_sub) {
                if (b.failed) ok = false;
                continue;
            }

            try printBenchmarkResult(writer, entry.name, &b, options.benchmem);
            if (b.failed) ok = false;
        }
    }
    return ok;
}

pub fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Usage: benchmark [options]
        \\
        \\Options:
        \\  -h, --help                         show this help
        \\  -c N, -cN, --count N, --count=N    run each benchmark N times
        \\  -t D, -tD, --benchtime D           run each benchmark for duration D
        \\  -t Nx, -tNx, --benchtime Nx        run exactly N iterations
        \\  -f P, -fP, --filter P              run benchmarks matching pattern P
        \\  -m, --benchmem                     print B/op and allocs/op
        \\  -p N, -pN, --parallelism N         default B.runParallel multiplier
        \\  --no-env                           suppress environment header lines
        \\
        \\Durations use ns, us, µs, ms, s, m, or h. Filters are comma-separated glob-like patterns:
        \\plain text contains, ^ anchors start, $ anchors end, * matches any bytes.
        \\
    );
}

fn printBenchmarkResult(writer: *Io.Writer, name: []const u8, b: *const B, benchmem: bool) !void {
    try writer.print("{s}\t", .{name});
    if (b.failed) {
        try writer.writeAll("FAIL\n");
        try writer.flush();
        return;
    }
    if (b.skipped) {
        try writer.writeAll("SKIP\n");
        try writer.flush();
        return;
    }

    try b.result.format(writer);
    if (benchmem or b.show_alloc_result) {
        try writer.writeByte('\t');
        try b.result.formatMem(writer);
    }
    try writer.writeByte('\n');
    try writer.flush();
}

fn emitEnvironment(writer: *Io.Writer) !void {
    try writer.print("zig_os: {s}\n", .{@tagName(builtin.target.os.tag)});
    try writer.print("zig_arch: {s}\n", .{@tagName(builtin.target.cpu.arch)});
    try writer.print("zig_abi: {s}\n", .{@tagName(builtin.target.abi)});
    try writer.print("zig_cpu: {s}\n", .{builtin.cpu.model.name});
    try writer.print("zig_mode: {s}\n", .{@tagName(builtin.mode)});
}

const max_predict_iters = 1_000_000_000;

fn predictN(goal_ns: u64, prev_iters: u64, prev_ns_raw: u64, last: u64) u64 {
    const prev_ns = if (prev_ns_raw == 0) 1 else prev_ns_raw;
    var n = goal_ns * prev_iters / prev_ns;
    n += n / 5;
    n = @min(n, 100 * last);
    n = @max(n, last + 1);
    n = @min(n, max_predict_iters);
    return n;
}

fn prettyPrint(writer: *Io.Writer, x: f64, unit: []const u8) !void {
    const y = @abs(x);
    if (y == 0 or y >= 999.95) return writer.print("{d:>10.0} {s}", .{ x, unit });
    if (y >= 99.995) return writer.print("{d:>12.1} {s}", .{ x, unit });
    if (y >= 9.9995) return writer.print("{d:>13.2} {s}", .{ x, unit });
    if (y >= 0.99995) return writer.print("{d:>14.3} {s}", .{ x, unit });
    if (y >= 0.099995) return writer.print("{d:>15.4} {s}", .{ x, unit });
    if (y >= 0.0099995) return writer.print("{d:>16.5} {s}", .{ x, unit });
    if (y >= 0.00099995) return writer.print("{d:>17.6} {s}", .{ x, unit });
    return writer.print("{d:>18.7} {s}", .{ x, unit });
}

// Metric keys are owned slices; StringArrayHashMapUnmanaged.clone would only copy the slices.
fn cloneMetrics(allocator: Allocator, src: MetricMap) !MetricMap {
    var dst: MetricMap = .empty;
    errdefer {
        freeMetricKeys(allocator, &dst);
        dst.deinit(allocator);
    }

    var it = src.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(key);
        try dst.put(allocator, key, entry.value_ptr.*);
    }
    return dst;
}

fn freeMetricKeys(allocator: Allocator, map: *MetricMap) void {
    var it = map.iterator();
    while (it.next()) |entry| allocator.free(entry.key_ptr.*);
}

fn parseDurationNs(s: []const u8) !u64 {
    const units = [_]struct { suffix: []const u8, scale: u64 }{
        .{ .suffix = "ns", .scale = 1 },
        .{ .suffix = "us", .scale = time.ns_per_us },
        .{ .suffix = "µs", .scale = time.ns_per_us },
        .{ .suffix = "ms", .scale = time.ns_per_ms },
        .{ .suffix = "s", .scale = time.ns_per_s },
        .{ .suffix = "m", .scale = time.ns_per_min },
        .{ .suffix = "h", .scale = time.ns_per_hour },
    };

    for (units) |unit| {
        if (mem.endsWith(u8, s, unit.suffix)) {
            const value = try std.fmt.parseFloat(f64, s[0 .. s.len - unit.suffix.len]);
            if (value <= 0) return error.InvalidDuration;
            return @intFromFloat(value * @as(f64, @floatFromInt(unit.scale)));
        }
    }
    return error.InvalidDuration;
}

test "moduleBenchmarks discovers nested public modules" {
    const root = struct {
        pub fn BenchmarkRoot(_: *B) !void {}

        pub const nested = struct {
            pub fn benchmarkNested(_: *B) !void {}

            pub const deeper = struct {
                pub fn BenchmarkDeeper(_: *B) !void {}
            };
        };

        const private_nested = struct {
            pub fn BenchmarkPrivate(_: *B) !void {}
        };
    };

    const benchmarks = comptime moduleBenchmarks(root);
    try testing.expectEqual(@as(usize, 3), benchmarks.len);
    try testing.expectEqualStrings("BenchmarkRoot", benchmarks[0].name);
    try testing.expectEqualStrings("BenchmarkNested", benchmarks[1].name);
    try testing.expectEqualStrings("BenchmarkDeeper", benchmarks[2].name);
}

test "predictN matches Go growth constraints" {
    try testing.expectEqual(@as(u64, 100), predictN(1000, 1, 10, 1));
    try testing.expectEqual(@as(u64, 2), predictN(1, 1, 1000, 1));
}

test "Loop benchmark runs and records iterations" {
    const bench_fn = struct {
        fn run(b: *B) !void {
            var x: u64 = 0;
            while (try b.loop()) x +%= 1;
            try b.reportMetric(@floatFromInt(x), "iters");
        }
    }.run;

    var result = try benchmark(testing.allocator, bench_fn, .{
        .io = if (has_io) testing.io else {},
        .benchtime = .{ .count = 5 },
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(u64, 5), result.n);
    try testing.expectEqual(@as(f64, 5), result.extra.get("iters").?);
}

test "B.N style benchmark runs requested count" {
    const bench_fn = struct {
        fn run(b: *B) !void {
            var i: u64 = 0;
            while (i < b.n) : (i += 1) {}
        }
    }.run;

    var result = try benchmark(testing.allocator, bench_fn, .{
        .io = if (has_io) testing.io else {},
        .benchtime = .{ .count = 7 },
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(u64, 7), result.n);
}

test "b.allocator records timed allocations" {
    const bench_fn = struct {
        fn run(b: *B) !void {
            while (try b.loop()) {
                const memory = try b.allocator.alloc(u8, 16);
                defer b.allocator.free(memory);
            }
        }
    }.run;

    var result = try benchmark(testing.allocator, bench_fn, .{
        .io = if (has_io) testing.io else {},
        .benchtime = .{ .count = 3 },
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(u64, 3), result.mem_allocs);
    try testing.expectEqual(@as(u64, 48), result.mem_bytes);
    try testing.expectEqual(@as(i64, 1), result.allocsPerOp());
    try testing.expectEqual(@as(i64, 16), result.allocedBytesPerOp());
}

const TestArgs = if (@hasDecl(std.process, "Args"))
    std.process.Args.IteratorGeneral(.{})
else
    std.process.ArgIteratorGeneral(.{});

test "CLI split equal and short flags preserve options" {
    const commands = [_][]const u8{
        "bench --count 2 --benchtime 7x --filter Alloc --parallelism 3 --benchmem --no-env",
        "bench --count=2 --benchtime=7x --filter=Alloc --parallelism=3 --benchmem --no-env",
        "bench -c 2 -t 7x -f Alloc -p 3 -m --no-env",
        "bench -c2 -t7x -fAlloc -p3 -m --no-env",
        "bench -c=2 -t=7x -f=Alloc -p=3 -m --no-env",
    };
    for (commands) |command| {
        var args = try TestArgs.init(testing.allocator, command);
        defer args.deinit();
        const options = try Options.parse(&args, .{});
        try testing.expectEqual(@as(usize, 2), options.count);
        try testing.expectEqual(@as(u64, 7), options.benchtime.count);
        try testing.expectEqualStrings("Alloc", options.filter.?);
        try testing.expectEqual(@as(usize, 3), options.parallelism);
        try testing.expect(options.benchmem);
        try testing.expect(!options.emit_environment);
    }
}

test "CLI help durations defaults and errors" {
    var args = try TestArgs.init(testing.allocator, "bench --help --benchtime=1.5ms");
    defer args.deinit();
    const options = try Options.parse(&args, .{ .count = 3 });
    try testing.expect(options.help);
    try testing.expectEqual(@as(usize, 3), options.count);
    try testing.expectEqual(@as(u64, 1_500_000), options.benchtime.duration_ns);

    const cases = .{
        .{ "bench --count", error.MissingBenchmarkOptionValue },
        .{ "bench --count=0", error.InvalidCount },
        .{ "bench --benchtime=0x", error.InvalidCount },
        .{ "bench --unknown", error.UnknownBenchmarkOption },
    };
    inline for (cases) |case| {
        var invalid = try TestArgs.init(testing.allocator, case[0]);
        defer invalid.deinit();
        try testing.expectError(case[1], Options.parse(&invalid, .{}));
    }
}

test "Zig 0.16 requires explicit Io before allocating or writing" {
    if (!has_io) return error.SkipZigTest;
    const func = struct {
        fn run(_: *B) !void {
            return error.TestUnexpectedResult;
        }
    }.run;
    // A failing allocator proves validation precedes allocation.
    try testing.expectError(Error.MissingIo, B.init(.failing, func, .{}));
    try testing.expectError(Error.MissingIo, benchmark(.failing, func, .{}));
    var buffer: [1024]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);
    try testing.expectError(Error.MissingIo, runBenchmarks(.failing, &.{}, .{
        .writer = &writer,
        .help = true,
    }));
    try testing.expectEqual(@as(usize, 0), writer.buffered().len);
}

test "nested discovery filtering counts and custom memory results" {
    const root = struct {
        pub const nested = struct {
            pub fn benchmarkParent(b: *B) !void {
                _ = try b.run("Selected", selected);
                _ = try b.run("Excluded", excluded);
            }
            fn selected(b: *B) !void {
                while (try b.loop()) {
                    const bytes = try b.allocator.alloc(u8, 16);
                    b.allocator.free(bytes);
                }
                try b.reportMetric(42, "ns/op");
                b.setBytes(16);
            }
            fn excluded(_: *B) !void {
                return error.TestUnexpectedResult;
            }
        };
    };
    var buffer: [4096]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);
    try testing.expect(try runModuleBenchmarks(root, testing.allocator, .{
        .io = if (has_io) testing.io else {},
        .writer = &writer,
        .emit_environment = false,
        .filter = "^BenchmarkParent/Selected$",
        .count = 2,
        .benchtime = .{ .count = 7 },
        .benchmem = true,
    }));
    const output = writer.buffered();
    try testing.expectEqual(@as(usize, 2), mem.count(u8, output, "BenchmarkParent/Selected\t       7"));
    try testing.expectEqual(@as(usize, 2), mem.count(u8, output, "42.00 ns/op"));
    try testing.expectEqual(@as(usize, 2), mem.count(u8, output, "      16 B/op\t       1 allocs/op"));
    try testing.expect(!mem.containsAtLeast(u8, output, 1, "Excluded"));
}

test "parallel benchmark preserves iteration accounting" {
    const work = struct {
        var completed: AtomicU64 = .init(0);
        fn body(pb: *PB) !void {
            while (pb.next()) _ = completed.fetchAdd(1, .seq_cst);
        }
        fn run(b: *B) !void {
            try b.runParallel(body);
        }
    };
    work.completed.store(0, .seq_cst);
    var result = try benchmark(testing.allocator, work.run, .{
        .io = if (has_io) testing.io else {},
        .benchtime = .{ .count = 7 },
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(u64, 7), result.n);
    try testing.expectEqual(@as(u64, 8), work.completed.load(.seq_cst)); // warmup plus measured run
}
