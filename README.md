# ZFlake

A lightweight, thread-safe Snowflake ID generator for Zig.

## What is a Snowflake ID?

Snowflake IDs are 64-bit unique identifiers originally designed by Twitter. They combine:
- Timestamp (milliseconds since a custom epoch)
- Machine ID (data center and worker identifiers)
- Sequence number (for multiple IDs within the same millisecond)

They provide time-sortable, globally unique identifiers without coordination between nodes.

## Features

- **Thread-safe**: Each generator maintains its own state
- **Configurable bit allocation**: Customize bits for timestamp, machine IDs, and sequence
- **Zero dependencies**: Only uses the Zig standard library
- **Simple API**: Clean, intuitive interface with minimal boilerplate
- **Comprehensive error handling**: Proper error return values for edge cases
- **Well-tested**: Complete test suite covering edge cases and normal operation

## Usage

### Basic Example

```zig
const std = @import("std");
const zf = @import("zflake");

pub fn main() !void {
    // Create a generator with default bit allocation (5 bits for DC, 5 for worker, 12 for sequence)
    var generator = try zf.init(
        std.time.milliTimestamp(),  // Use current time as epoch
        1,                          // Data center ID
        2                           // Worker ID
    );
    
    // Generate a snowflake ID
    const id = try generator.generate();
    std.debug.print("Generated ID: {d}\n", .{id});
    
    // Decode an ID to get its components
    const decoded = generator.decode(id);
    std.debug.print("Timestamp: {d}\n", .{decoded.timestamp});
    std.debug.print("Data Center ID: {d}\n", .{decoded.dataCenterId});
    std.debug.print("Worker ID: {d}\n", .{decoded.workerId});
    std.debug.print("Sequence: {d}\n", .{decoded.sequence});
}
```

### Custom Bit Allocation

You can customize how bits are allocated for different components:

```zig
// 4 bits for data center (max 15),
// 3 bits for worker (max 7),
// 15 bits for sequence (max 32767)
var generator = try zf.initWithBits(
    std.time.milliTimestamp(),  // epoch
    5,                          // data center ID
    3,                          // worker ID
    4,                          // data center ID bits
    3,                          // worker ID bits
    15                          // sequence bits
);
```

### Error Handling

The library returns proper errors in case of issues:

```zig
const id = generator.generate() catch |err| {
    switch (err) {
        error.ClockMovedBackwards => {
            // Handle clock drift (e.g. retry, log, etc.)
            std.debug.print("System clock moved backwards!\n", .{});
            return;
        },
        else => return err,
    }
};
```

## Installation

Add to your `build.zig.zon` dependencies:

```zig
.dependencies = .{
    .zflake = .{
        .url = "https://github.com/your-username/zflake/archive/refs/tags/v1.0.0.tar.gz",
        // Replace with the actual hash
        .hash = "12345",
    },
},
```

And in your `build.zig`:

```zig
const zflake = b.dependency("zflake", .{
    .target = target,
    .optimize = optimize,
});

exe.addModule("zflake", zflake.module("zflake"));
```

## License

MIT License