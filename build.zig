const std = @import("std");
const projectName = "ZIG-TEST";
const builtin = @import("builtin");

const emccOutputDir = "zig-out" ++ std.fs.path.sep_str ++ "htmlout" ++ std.fs.path.sep_str;
const emccOutputFile = "index.html";
pub fn emscriptenRunStep(b: *std.Build) !*std.Build.Step.Run {
    // If compiling on windows , use emrun.bat.
    const emrunExe = switch (builtin.os.tag) {
        .windows => "emrun.bat",
        else => "emrun",
    };
    var emrun_run_arg = try b.allocator.alloc(u8, b.sysroot.?.len + emrunExe.len + 1);
    defer b.allocator.free(emrun_run_arg);

    if (b.sysroot == null) {
        emrun_run_arg = try std.fmt.bufPrint(emrun_run_arg, "{s}", .{emrunExe});
    } else {
        emrun_run_arg = try std.fmt.bufPrint(emrun_run_arg, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ b.sysroot.?, emrunExe });
    }

    const run_cmd = b.addSystemCommand(&[_][]const u8{ emrun_run_arg, emccOutputDir ++ emccOutputFile });
    return run_cmd;
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
            .bulk_memory,
        }),
        .os_tag = .emscripten,
    });

    const raylib_dep = b.dependency("raylib", .{
        .target = wasm_target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.artifact("raylib");
    b.installArtifact(raylib);
    //web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        const exe_lib = b.addStaticLibrary(.{
            .name = projectName,
            .root_source_file = b.path("src/main.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        exe_lib.rdynamic = true;
        // exe_lib.shared_memory = true;
        // TODO currently deactivated because it seems as if it doesn't work with local hosting debug workflow
        exe_lib.shared_memory = false;
        exe_lib.root_module.single_threaded = false;

        exe_lib.linkLibrary(raylib);
        exe_lib.addIncludePath(raylib_dep.path("src"));

        const sysroot_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" }) catch {
            return;
        };
        exe_lib.addIncludePath(.{ .cwd_relative = sysroot_include });

        // addAssets(b, exe_lib);
        // Create the output directory because emcc can't do it.
        const mkdir_command = switch (builtin.os.tag) {
            .windows => b.addSystemCommand(&.{ "cmd.exe", "/c", "if", "not", "exist", emccOutputDir, "mkdir", emccOutputDir }),
            else => b.addSystemCommand(&.{ "mkdir", "-p", emccOutputDir }),
        };

        const emcc_exe = switch (builtin.os.tag) { // TODO bundle emcc as a build dependency
            .windows => "emcc.bat",
            else => "emcc",
        };

        const emcc_exe_path = b.pathJoin(&.{ b.sysroot.?, emcc_exe });
        const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});
        emcc_command.step.dependOn(&mkdir_command.step);
        emcc_command.addArgs(&[_][]const u8{
            "-o",
            emccOutputDir ++ emccOutputFile,
            "-sFULL-ES3=1",
            "-sUSE_GLFW=3",
            // Debug options
            "-sASSERTIONS=1", // note(jae): ASSERTIONS=2 crashes due to not rounding down mouse position for SDL2, https://github.com/emscripten-core/emscripten/issues/19655
            "-sSTACK_OVERFLOW_CHECK=1",
            "-sASYNCIFY",
            "-sASYNCIFY_STACK_SIZE=5120000", // I increased this randomly to stop problems, not sure how necessary this change was.
            "-O0", // "-O3", //-Og = debug
            "--shell-file",
            b.path("src/minshell.html").getPath(b),
        });

        const link_items: []const *std.Build.Step.Compile = &.{
            raylib,
            exe_lib,
        };
        for (link_items) |item| {
            emcc_command.addFileArg(item.getEmittedBin());
            emcc_command.step.dependOn(&item.step);
        }

        const install = emcc_command;
        const run_step = emscriptenRunStep(b) catch |err| {
            // do some stuff, maybe log an error
            std.debug.print("EmscriptenRunStep error: {}\n", .{err});
            return;
        };
        run_step.step.dependOn(&install.step);
        run_step.addArg("--no_browser");
        const run_option = b.step("run", "Run Arena");

        run_option.dependOn(&run_step.step);
        return;
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = projectName,
        .root_module = exe_mod,
    });
    exe.linkLibrary(raylib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
