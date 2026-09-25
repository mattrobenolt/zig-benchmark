const std = @import("std");
const Io = std.Io;
const testing = std.testing;

pub const Timer = if (@hasDecl(std.time, "Timer")) std.time.Timer else struct {
    const Self = @This();

    io: Io,
    started: Io.Timestamp,

    pub fn start(io: Io) !Timer {
        return .{ .io = io, .started = .now(io, .awake) };
    }

    pub fn reset(self: *Self) void {
        self.started = .now(self.io, .awake);
    }

    pub fn read(self: *Self) u64 {
        // Subtract complete timestamps, not independently clamped seconds/nanoseconds.
        return @intCast(self.started.durationTo(.now(self.io, .awake)).toNanoseconds());
    }
};

test "monotonic timer reads same-second and second-boundary intervals and resets" {
    if (!@hasDecl(Io, "Clock")) return error.SkipZigTest;

    const Clock = struct {
        fn now(userdata: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
            std.debug.assert(clock == .awake);
            const ns: *i96 = @ptrCast(@alignCast(userdata.?));
            return .{ .nanoseconds = ns.* };
        }
    };
    var ns: i96 = 10 * std.time.ns_per_s + 800_000_000;
    var vtable = testing.io.vtable.*;
    vtable.now = Clock.now;
    const io: Io = .{ .userdata = &ns, .vtable = &vtable };
    var timer = try Timer.start(io);
    try testing.expectEqual(@as(u64, 0), timer.read());
    ns += 100_000_000;
    try testing.expectEqual(@as(u64, 100_000_000), timer.read());
    ns += 200_000_000;
    try testing.expectEqual(@as(u64, 300_000_000), timer.read());
    timer.reset();
    try testing.expectEqual(@as(u64, 0), timer.read());
    ns += 2 * std.time.ns_per_s + 50_000_000;
    try testing.expectEqual(@as(u64, 2_050_000_000), timer.read());
}
