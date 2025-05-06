const std = @import("std");
const zf = @import("zflake");
const expect = std.testing.expect;

test "basic generation" {
    const epoch = std.time.milliTimestamp();
    var sf = try zf.Snowflake.init(epoch, 1, 1);
    const id = try sf.generate();
    const decoded = sf.decode(id);
    
    try std.testing.expect(decoded.timestamp >= epoch);
    try std.testing.expectEqual(@as(u32, 1), decoded.dataCenterId);
    try std.testing.expectEqual(@as(u32, 1), decoded.workerId);
}