const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zflake = b.addModule("zflake", .{
        .root_source_file = b.path(b.pathJoin(&.{"src", "zflake.zig"})),
    });

    const test_step = b.step("test", "Run unit tests");
    const zflake_unit_tests = b.addTest(.{
        .root_source_file = b.path(b.pathJoin(&.{"src", "test.zig"})),
        .target = target,
        .optimize = optimize
    });

    zflake_unit_tests.root_module.addImport("zflake", zflake);
    const run_zflake_tests = b.addRunArtifact(zflake_unit_tests);
    test_step.dependOn(&run_zflake_tests.step);
}
