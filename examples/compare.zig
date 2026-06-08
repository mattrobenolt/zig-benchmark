const std = @import("std");

const bench = @import("benchmark");

const input = "The Quick Brown Fox jumps over the lazy dog. 0123456789\n" ** 64;
const lower_table = makeLowerTable();

fn makeLowerTable() [256]u8 {
    var table: [256]u8 = @splat(0);
    for ('a'..('z' + 1)) |c| table[c] = 1;
    return table;
}

fn countLowerScalar(bytes: []const u8) usize {
    var count: usize = 0;
    for (bytes) |c| {
        if (c >= 'a' and c <= 'z') count += 1;
    }
    return count;
}

fn countLowerTable(bytes: []const u8) usize {
    var count: usize = 0;
    for (bytes) |c| count += lower_table[c];
    return count;
}

fn benchmarkCountScalar(b: *bench.B) !void {
    const bytes = b.blackBox(input[0..]);
    var count: usize = 0;
    while (try b.loop()) count = countLowerScalar(bytes);
    b.keepAlive(count);
    b.setBytes(input.len);
}

fn benchmarkCountTable(b: *bench.B) !void {
    const bytes = b.blackBox(input[0..]);
    var count: usize = 0;
    while (try b.loop()) count = countLowerTable(bytes);
    b.keepAlive(count);
    b.setBytes(input.len);
}

fn benchmarkAllocPerLine(b: *bench.B) !void {
    const bytes = b.blackBox(input[0..]);
    while (try b.loop()) {
        var lines: std.ArrayList([]const u8) = .empty;
        defer lines.deinit(b.allocator);

        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |line| try lines.append(b.allocator, line);
        b.keepAlive(lines.items.len);
    }
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var args = std.process.args();
    const options: bench.Options = try .parse(&args, .{
        .benchtime = .{ .duration_ns = 250 * std.time.ns_per_ms },
        .benchmem = true,
    });

    const benchmarks = [_]bench.Spec{
        .{ .name = "BenchmarkAsciiCount/Scalar", .func = benchmarkCountScalar },
        .{ .name = "BenchmarkAsciiCount/Table", .func = benchmarkCountTable },
        .{ .name = "BenchmarkAllocPerLine", .func = benchmarkAllocPerLine },
    };

    _ = try bench.runBenchmarks(allocator, &benchmarks, options);
}
