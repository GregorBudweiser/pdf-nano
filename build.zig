const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "pdf-nano",
        .root_source_file = .{ .path = "src/c_api.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.rdynamic = true;
    b.installArtifact(lib);

    if (target.cpu_arch) |arch| {
        if (!arch.isWasm()) {
            const exe = b.addExecutable(.{
                .name = "pdf-nano",
                .root_source_file = .{ .path = "src/main.zig" },
                .target = target,
                .optimize = optimize,
            });
            b.installArtifact(exe);
        }
    }

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/c_api.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
