const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // wasm needs to be compiled as executable with "-fnoentry"
    if (target.result.cpu.arch.isWasm()) {
        // pdf-nano "library" (i.e. wasm exe)
        const exe = b.addExecutable(.{
            .name = "pdf-nano",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/c_api.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.entry = .disabled;
        exe.rdynamic = true;
        b.installArtifact(exe);
    } else {
        // pdf-nano library
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "pdf-nano",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/c_api.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(lib);

        // example program
        const exe = b.addExecutable(.{
            .name = "pdf-nano",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(exe);
    }

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
