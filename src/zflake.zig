const std = @import("std");

pub const SnowflakeError = error{ ClockMovedBackwards, InvalidDataCenterId, InvalidWorkerId };

/// Snowflake ID generator based on Twitter's snowflake format
/// Generates unique 64-bit IDs with embedded timestamp, worker ID, and sequence information
pub const Snowflake = struct {
    // Core configuration values
    epoch: i64,
    dataCenterId: u32,
    workerId: u32,
    
    // Bit allocation (configurable)
    dataCenterIdBits: u6 = 5,
    workerIdBits: u6 = 5,
    sequenceBits: u6 = 12,
    
    // Computed fields from bit allocation
    sequenceMask: i64,
    maxDataCenterId: i64,
    maxWorkerId: i64, 
    timestampLeftShift: u6,
    
    // Internal state - now instance variables for thread safety
    lastTimestamp: i64 = 0,
    sequence: i64 = 0,

    /// Initialize a new Snowflake ID generator
    /// epoch: Custom epoch start time in milliseconds
    /// dataCenterId: ID of the datacenter (must be within range for dataCenterIdBits)
    /// workerId: ID of the worker (must be within range for workerIdBits)
    pub fn init(epoch: i64, dataCenterId: u32, workerId: u32) !Snowflake {
        var self = Snowflake{
            .epoch = epoch,
            .dataCenterId = dataCenterId,
            .workerId = workerId,
            .sequenceMask = 0,
            .maxDataCenterId = 0,
            .maxWorkerId = 0,
            .timestampLeftShift = 0,
        };

        // Calculate bit masks and shifts
        self.sequenceMask = ~@as(i64, 0) ^ (~@as(i64, 0) << self.sequenceBits);
        self.maxDataCenterId = ~@as(i64, 0) ^ (~@as(i64, 0) << self.dataCenterIdBits);
        self.maxWorkerId = ~@as(i64, 0) ^ (~@as(i64, 0) << self.workerIdBits); // Fixed: was using dataCenterIdBits
        self.timestampLeftShift = self.sequenceBits + self.workerIdBits + self.dataCenterIdBits;

        // Validate configuration
        if (self.dataCenterId > @as(u32, @intCast(self.maxDataCenterId))) {
            return SnowflakeError.InvalidDataCenterId;
        }

        if (self.workerId > @as(u32, @intCast(self.maxWorkerId))) {
            return SnowflakeError.InvalidWorkerId;
        }

        return self;
    }

    /// Generate a new unique Snowflake ID
    /// Returns a 64-bit ID or an error if clock moved backwards
    pub fn generate(self: *Snowflake) !i64 {
        var timestamp = std.time.milliTimestamp();

        if (timestamp < self.lastTimestamp) {
            return SnowflakeError.ClockMovedBackwards;
        }

        if (self.lastTimestamp == timestamp) {
            // Same millisecond: increment sequence
            self.sequence = (self.sequence + 1) & self.sequenceMask;
            if (self.sequence == 0) {
                // Sequence exhausted, wait till next millisecond
                timestamp = try waitTillNextMilis(self.lastTimestamp);
            }
        } else {
            // Different millisecond: reset sequence
            self.sequence = 0;
        }

        self.lastTimestamp = timestamp;
        
        // Construct ID from components:
        // - timestamp in most significant bits
        // - followed by datacenter ID
        // - followed by worker ID
        // - sequence in least significant bits
        return ((timestamp - self.epoch) << self.timestampLeftShift) |
            (@as(i64, self.dataCenterId) << (self.sequenceBits + self.workerIdBits)) |
            (@as(i64, self.workerId) << self.sequenceBits) |
            self.sequence;
    }

    /// Decode a Snowflake ID back into its component parts
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

/// Helper function to wait until the next millisecond
fn waitTillNextMilis(last_timestamp: i64) !i64 {
    var timestamp = std.time.milliTimestamp();
    while (timestamp <= last_timestamp) {
        timestamp = std.time.milliTimestamp();
    }
    return timestamp;
}
