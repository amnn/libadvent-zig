const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const lib = b.addModule("libadvent", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const tests = b.addTest(.{
        .root_module = lib,
    });

    // A run step that will run the test executable.
    const run_tests = b.addRunArtifact(tests);
    const step_test = b.step("test", "Run unit tests");
    step_test.dependOn(&run_tests.step);
}
