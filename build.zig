const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // include build.zig.zon as module to get version string etc..
    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

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
        exe.root_module.addImport("build_zig_zon", build_zig_zon);
        b.installArtifact(exe);
    } else {
        // pdf-nano library (c api/library for other languages)
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "pdf-nano",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/c_api.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        lib.root_module.addImport("build_zig_zon", build_zig_zon);
        b.installArtifact(lib);

        // root module for zig users
        const root_module = b.addModule("pdf_nano", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        root_module.addImport("build_zig_zon", build_zig_zon);

        // standalone zig program (uses zig source code directly rather than linking libpdf-nano.so)
        const exe = b.addExecutable(.{
            .name = "pdf-nano",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.root_module.addImport("pdf_nano", root_module);
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
