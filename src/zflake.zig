const std = @import("std");

pub const SnowflakeError = error{ ClockMovedBackwards, InvalidDataCenterId, InvalidWorkerId };

/// ID components returned by decode
pub const IdComponents = struct {
    timestamp: i64,
    dataCenterId: u32,
    workerId: u32,
    sequence: u32,
};

/// The internal state of a Snowflake generator - implementation detail
const State = struct {
    // Configuration
    epoch: i64,
    dataCenterId: u32,
    workerId: u32,
    dataCenterIdBits: u6,
    workerIdBits: u6,
    sequenceBits: u6,
    
    // Computed from configuration
    sequenceMask: i64,
    maxDataCenterId: i64,
    maxWorkerId: i64,
    timestampLeftShift: u6,
    
    // Internal state variables
    lastTimestamp: i64,
    sequence: i64,
};

/// A handle to a Snowflake ID generator with its own internal state
pub const Generator = struct {
    state: State,
    
    /// Generate a new unique Snowflake ID
    pub fn generate(self: *Generator) !i64 {
        var timestamp = std.time.milliTimestamp();

        if (timestamp < self.state.lastTimestamp) {
            return SnowflakeError.ClockMovedBackwards;
        }

        if (self.state.lastTimestamp == timestamp) {
            // Same millisecond: increment sequence
            self.state.sequence = (self.state.sequence + 1) & self.state.sequenceMask;
            if (self.state.sequence == 0) {
                // Sequence exhausted, wait till next millisecond
                timestamp = try waitTillNextMilis(self.state.lastTimestamp);
            }
        } else {
            // Different millisecond: reset sequence
            self.state.sequence = 0;
        }

        self.state.lastTimestamp = timestamp;
        
        return ((timestamp - self.state.epoch) << self.state.timestampLeftShift) |
            (@as(i64, self.state.dataCenterId) << (self.state.sequenceBits + self.state.workerIdBits)) |
            (@as(i64, self.state.workerId) << self.state.sequenceBits) |
            self.state.sequence;
    }

    /// Decode a Snowflake ID back into its component parts
    pub fn decode(self: Generator, id: i64) IdComponents {
        return .{
            .timestamp = (id >> self.state.timestampLeftShift) + self.state.epoch,
            .dataCenterId = @as(u32, @intCast((id >> (self.state.workerIdBits + self.state.sequenceBits)) & self.state.maxDataCenterId)),
            .workerId = @as(u32, @intCast((id >> self.state.sequenceBits) & self.state.maxWorkerId)),
            .sequence = @as(u32, @intCast(id & self.state.sequenceMask)),
        };
    }
};

/// Initialize a new Snowflake ID generator
/// epoch: Custom epoch start time in milliseconds
/// dataCenterId: ID of the datacenter (0-31 with default settings)
/// workerId: ID of the worker (0-31 with default settings)
pub fn init(epoch: i64, dataCenterId: u32, workerId: u32) !Generator {
    // Default bit allocation
    return initWithBits(epoch, dataCenterId, workerId, 5, 5, 12);
}

/// Initialize a new Snowflake ID generator with custom bit allocation
pub fn initWithBits(
    epoch: i64, 
    dataCenterId: u32, 
    workerId: u32, 
    dataCenterIdBits: u6, 
    workerIdBits: u6, 
    sequenceBits: u6
) !Generator {
    var state = State{
        .epoch = epoch,
        .dataCenterId = dataCenterId,
        .workerId = workerId,
        .dataCenterIdBits = dataCenterIdBits,
        .workerIdBits = workerIdBits,
        .sequenceBits = sequenceBits,
        .sequenceMask = 0,
        .maxDataCenterId = 0,
        .maxWorkerId = 0,
        .timestampLeftShift = 0,
        .lastTimestamp = 0,
        .sequence = 0,
    };

    // Calculate bit masks and shifts
    state.sequenceMask = ~@as(i64, 0) ^ (~@as(i64, 0) << state.sequenceBits);
    state.maxDataCenterId = ~@as(i64, 0) ^ (~@as(i64, 0) << state.dataCenterIdBits);
    state.maxWorkerId = ~@as(i64, 0) ^ (~@as(i64, 0) << state.workerIdBits);
    state.timestampLeftShift = state.sequenceBits + state.workerIdBits + state.dataCenterIdBits;

    // Validate configuration
    if (state.dataCenterId > @as(u32, @intCast(state.maxDataCenterId))) {
        return SnowflakeError.InvalidDataCenterId;
    }

    if (state.workerId > @as(u32, @intCast(state.maxWorkerId))) {
        return SnowflakeError.InvalidWorkerId;
    }

    return Generator{ .state = state };
}

/// Helper function to wait until the next millisecond
fn waitTillNextMilis(last_timestamp: i64) !i64 {
    var timestamp = std.time.milliTimestamp();
    while (timestamp <= last_timestamp) {
        timestamp = std.time.milliTimestamp();
    }
    return timestamp;
}
