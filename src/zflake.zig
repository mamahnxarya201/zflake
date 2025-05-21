const std = @import("std");
const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;

pub const SnowflakeError = error{ ClockMovedBackwards, InvalidDataCenterId, InvalidWorkerId, OutOfMemory };

/// ID components returned by decode
pub const IdComponents = struct {
    timestamp: i64,
    dataCenterId: u32,
    workerId: u32,
    sequence: u32,
    
    pub fn eql(self: IdComponents, other: IdComponents) bool {
        return self.timestamp == other.timestamp and
               self.dataCenterId == other.dataCenterId and
               self.workerId == other.workerId and
               self.sequence == other.sequence;
    }
};

/// Cache map for memoizing decoded IDs
const DecodeCacheMap = std.AutoHashMap(i64, IdComponents);

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
    mutex: Mutex = .{},  // Mutex for thread-safe operations
    cache: ?*DecodeCacheMap = null, // Optional memoization cache
    allocator: ?Allocator = null,   // Allocator for cache memory management
    
    /// Generate a new unique Snowflake ID with thread safety
    pub fn generate(self: *Generator) !i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
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
    /// Uses memoization if cache is enabled
    pub fn decode(self: Generator, id: i64) IdComponents {
        // Try to get from cache if available
        if (self.cache) |cache| {
            if (cache.get(id)) |components| {
                return components; // No dereference needed, it's a value not a pointer
            }
        }
        
        // Calculate components
        const components = IdComponents{
            .timestamp = (id >> self.state.timestampLeftShift) + self.state.epoch,
            .dataCenterId = @as(u32, @intCast((id >> (self.state.workerIdBits + self.state.sequenceBits)) & self.state.maxDataCenterId)),
            .workerId = @as(u32, @intCast((id >> self.state.sequenceBits) & self.state.maxWorkerId)),
            .sequence = @as(u32, @intCast(id & self.state.sequenceMask)),
        };
        
        // Store in cache if available
        if (self.cache != null) {
            const cache = self.cache.?;
            
            // Attempt to add to cache, ignore errors (e.g. if already exists)
            _ = cache.put(id, components) catch {};
        }
        
        return components;
    }
    
    /// Initialize memoization cache for frequently-used IDs
    pub fn initMemoization(self: *Generator, allocator: Allocator) !void {
        if (self.cache != null) return;
        
        const cache = try allocator.create(DecodeCacheMap);
        cache.* = DecodeCacheMap.init(allocator);
        self.cache = cache;
        self.allocator = allocator;
    }
    
    /// Deinitialize and free resources
    pub fn deinit(self: *Generator) void {
        if (self.cache != null and self.allocator != null) {
            const cache = self.cache.?;
            const alloc = self.allocator.?;
            
            cache.deinit(); // HashMap.deinit doesn't take an allocator parameter
            alloc.destroy(cache);
            self.cache = null;
            self.allocator = null;
        }
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
