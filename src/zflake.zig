const std = @import("std");

// let the user handle the error themselves?
// i see the stdlib does this so might just follow it
// example on this stdlib will be: OpenError in std.fs
pub const SnowflakeError = error{ ClockMovedBackwards, InvalidDataCenterId, InvalidWorkerId };

pub const Snowflake = struct {
    // TODO: research memory usage about using 64 everywhere
    // i am afraid of stackoverflow so lets just use 64 everywhere since
    // the scala implementation use long to handle of all operation
    epoch: i64,
    dataCenterId: i64,
    workerId: i64,

    // Default snowflake bit is 22
    // Make this field configurable from init
    dataCenterIdBits: u6 = 5,
    workerIdBits: u6 = 5,
    sequenceBits: u6 = 12,

    // I dont know why but i dont like this
    // Feels like oop but i guess it fine for now
    // TODO: Refactor it later
    sequenceMask: i64 = 0,
    maxDataCenterId: i64 = 0,
    maxWorkerId: i64 = 0,
    timestampLeftShift: u6 = 0,

    var lastTimestamp: i64 = 0;
    var sequence: i64 = 0;

    pub fn init(epoch: i64, dataCenterId: i64, workerId: i64) !Snowflake {
        var self = Snowflake{
            .epoch = epoch,
            .dataCenterId = dataCenterId,
            .workerId = workerId,
        };

        self.sequenceMask = ~@as(i64, 0) ^ (~@as(i64, 0) << self.sequenceBits);
        self.maxDataCenterId = ~@as(i64, 0) ^ (~@as(i64, 0) << self.dataCenterIdBits);
        self.maxWorkerId = ~@as(i64, 0) ^ (~@as(i64, 0) << self.dataCenterIdBits);
        self.timestampLeftShift = self.sequenceBits + self.workerIdBits + self.dataCenterIdBits;

        if (self.dataCenterId > self.maxDataCenterId) {
            return SnowflakeError.InvalidDataCenterId;
        }

        if (self.workerId > self.maxWorkerId) {
            return SnowflakeError.InvalidWorkerId;
        }

        return self;
    }

    pub fn generate(self: Snowflake) !i64 {
        var timestamp = std.time.milliTimestamp();

        if (timestamp < lastTimestamp) {
            std.debug.print("what the fuck ?", .{});
        }

        if (lastTimestamp == timestamp) {
            sequence = (sequence + 1) & self.sequenceMask;
            if (sequence == 0) {
                timestamp = try waitTillNextMilis(lastTimestamp);
            }
        }

        lastTimestamp = timestamp;
        return ((timestamp - self.epoch) << self.timestampLeftShift) |
            (self.dataCenterId << (self.sequenceBits + self.workerIdBits)) |
            (self.workerId << self.sequenceBits) |
            sequence;
    }

    pub fn decode(self: Snowflake, id: i64) struct {
        timestamp: i64,
        dataCenterId: u32,
        workerId: u32,
        sequence: u32,
    } {
        return .{
            .timestamp = (id >> self.timestampLeftShift) + self.epoch,
            .dataCenterId = @as(u32, @intCast((id >> (self.workerIdBits + self.sequenceBits)) & self.maxDataCenterId)),
            .workerId = @as(u32, @intCast((id >> self.sequenceBits) & self.maxWorkerId)),
            .sequence = @as(u32, @intCast(id & self.sequenceMask)),
        };
    }
};

fn waitTillNextMilis(lastTimestamp: i64) !i64 {
    var timestamp = std.time.milliTimestamp();
    while (timestamp <= lastTimestamp) {
        timestamp = std.time.milliTimestamp();
    }
    return timestamp;
}
