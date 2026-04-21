const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const has_local_ziggy = blk: {
        std.fs.cwd().access("../ziggy/src/ziggy.zig", .{}) catch break :blk false;
        break :blk true;
    };

    const mod = b.createModule(.{
        .root_source_file = b.path("src/fmus.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "fmus",
        .linkage = .static,
        .root_module = mod,
    });
    b.installArtifact(lib);

    const core_demo = b.addExecutable(.{
        .name = "fmus-core-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/core_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    core_demo.root_module.addImport("fmus", mod);
    b.installArtifact(core_demo);

    const workflow_demo = b.addExecutable(.{
        .name = "fmus-workflow-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/workflow_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    workflow_demo.root_module.addImport("fmus", mod);
    b.installArtifact(workflow_demo);

    const terminal_demo = b.addExecutable(.{
        .name = "fmus-terminal-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    terminal_demo.root_module.addImport("fmus", mod);
    if (target.result.os.tag == .windows) {
        terminal_demo.subsystem = .Windows;
    }
    b.installArtifact(terminal_demo);
    b.installFile("assets/fmus-terminal-demo.ico", "bin/fmus-terminal-demo.ico");

    const terminal_automation_demo = b.addExecutable(.{
        .name = "fmus-terminal-automation-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_automation_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    terminal_automation_demo.root_module.addImport("fmus", mod);
    if (target.result.os.tag == .windows) {
        terminal_automation_demo.subsystem = .Windows;
    }
    b.installArtifact(terminal_automation_demo);
    b.installFile("assets/fmus-terminal-demo.ico", "bin/fmus-terminal-demo.ico");

    const terminal_automation_repl = b.addExecutable(.{
        .name = "fmus-terminal-automation-repl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_automation_repl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    terminal_automation_repl.root_module.addImport("fmus", mod);
    b.installArtifact(terminal_automation_repl);

    const terminal_visible_automation_demo = b.addExecutable(.{
        .name = "fmus-terminal-visible-automation-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_visible_automation_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    terminal_visible_automation_demo.root_module.addImport("fmus", mod);
    if (target.result.os.tag == .windows) {
        terminal_visible_automation_demo.subsystem = .Windows;
    }
    b.installArtifact(terminal_visible_automation_demo);
    b.installFile("assets/fmus-terminal-demo.ico", "bin/fmus-terminal-demo.ico");

    const terminal_visible_automation_repl = b.addExecutable(.{
        .name = "fmus-terminal-visible-automation-repl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_visible_automation_repl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    terminal_visible_automation_repl.root_module.addImport("fmus", mod);
    b.installArtifact(terminal_visible_automation_repl);

    const agent_demo = b.addExecutable(.{
        .name = "fmus-agent-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/agent_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    agent_demo.root_module.addImport("fmus", mod);
    b.installArtifact(agent_demo);

    const ws_echo_server_demo = b.addExecutable(.{
        .name = "fmus-ws-echo-server-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ws_echo_server_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ws_echo_server_demo.root_module.addImport("fmus", mod);
    b.installArtifact(ws_echo_server_demo);

    const ws_echo_client_demo = b.addExecutable(.{
        .name = "fmus-ws-echo-client-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ws_echo_client_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ws_echo_client_demo.root_module.addImport("fmus", mod);
    b.installArtifact(ws_echo_client_demo);

    const automation_ws_server_demo = b.addExecutable(.{
        .name = "fmus-terminal-automation-ws-server-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_automation_ws_server_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    automation_ws_server_demo.root_module.addImport("fmus", mod);
    b.installArtifact(automation_ws_server_demo);

    const automation_ws_client_demo = b.addExecutable(.{
        .name = "fmus-terminal-automation-ws-client-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/terminal_automation_ws_client_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    automation_ws_client_demo.root_module.addImport("fmus", mod);
    b.installArtifact(automation_ws_client_demo);

    const zigsaw_demo = b.addExecutable(.{
        .name = "fmus-zigsaw-foundation-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/zigsaw_foundation_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zigsaw_demo.root_module.addImport("fmus", mod);
    b.installArtifact(zigsaw_demo);

    const zigsaw_runtime_demo = b.addExecutable(.{
        .name = "fmus-zigsaw-runtime-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/zigsaw_runtime_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zigsaw_runtime_demo.root_module.addImport("fmus", mod);
    b.installArtifact(zigsaw_runtime_demo);

    const zigsaw_platform_demo = b.addExecutable(.{
        .name = "fmus-zigsaw-platform-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/zigsaw_platform_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zigsaw_platform_demo.root_module.addImport("fmus", mod);
    b.installArtifact(zigsaw_platform_demo);

    var supabase_ziggy_demo: ?*std.Build.Step.Compile = null;
    var supabase_ziggy_interactive_demo: ?*std.Build.Step.Compile = null;
    if (has_local_ziggy) {
        const ziggy_mod = b.createModule(.{
            .root_source_file = b.path("../ziggy/src/ziggy.zig"),
            .target = target,
            .optimize = optimize,
        });
        const demo = b.addExecutable(.{
            .name = "fmus-supabase-ziggy-demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/supabase_ziggy_demo.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        demo.root_module.addImport("fmus", mod);
        demo.root_module.addImport("ziggy", ziggy_mod);
        b.installArtifact(demo);
        supabase_ziggy_demo = demo;

        const interactive_demo = b.addExecutable(.{
            .name = "fmus-supabase-ziggy-interactive-demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/supabase_ziggy_interactive_demo.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        interactive_demo.root_module.addImport("fmus", mod);
        interactive_demo.root_module.addImport("ziggy", ziggy_mod);
        b.installArtifact(interactive_demo);
        supabase_ziggy_interactive_demo = interactive_demo;
    }

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run fmus-zig tests");
    test_step.dependOn(&run_tests.step);

    const run_core_demo = b.addRunArtifact(core_demo);
    const core_demo_step = b.step("example-core", "Run the fmus core demo");
    core_demo_step.dependOn(&run_core_demo.step);

    const run_workflow_demo = b.addRunArtifact(workflow_demo);
    const workflow_demo_step = b.step("example-workflow", "Run the fmus workflow demo");
    workflow_demo_step.dependOn(&run_workflow_demo.step);

    const terminal_demo_step = b.step("example-terminal", "Build the fmus terminal demo");
    terminal_demo_step.dependOn(&terminal_demo.step);

    const run_terminal_demo = b.addRunArtifact(terminal_demo);
    const terminal_demo_run_step = b.step("run-terminal-demo", "Run the fmus terminal demo");
    terminal_demo_run_step.dependOn(&run_terminal_demo.step);

    const terminal_automation_demo_step = b.step("example-terminal-automation", "Build the terminal automation window demo");
    terminal_automation_demo_step.dependOn(&terminal_automation_demo.step);

    const run_terminal_automation_demo = b.addRunArtifact(terminal_automation_demo);
    const terminal_automation_demo_run_step = b.step("run-terminal-automation-demo", "Run the terminal automation window demo");
    terminal_automation_demo_run_step.dependOn(&run_terminal_automation_demo.step);

    const run_terminal_automation_repl = b.addRunArtifact(terminal_automation_repl);
    const terminal_automation_repl_step = b.step("example-terminal-automation-repl", "Run the terminal automation REPL client");
    terminal_automation_repl_step.dependOn(&run_terminal_automation_repl.step);

    const terminal_visible_automation_demo_step = b.step("example-terminal-visible-automation", "Build the visible terminal automation demo");
    terminal_visible_automation_demo_step.dependOn(&terminal_visible_automation_demo.step);

    const run_terminal_visible_automation_demo = b.addRunArtifact(terminal_visible_automation_demo);
    const terminal_visible_automation_demo_run_step = b.step("run-terminal-visible-automation-demo", "Run the visible terminal automation demo");
    terminal_visible_automation_demo_run_step.dependOn(&run_terminal_visible_automation_demo.step);

    const run_terminal_visible_automation_repl = b.addRunArtifact(terminal_visible_automation_repl);
    const terminal_visible_automation_repl_step = b.step("example-terminal-visible-automation-repl", "Run the visible terminal automation REPL");
    terminal_visible_automation_repl_step.dependOn(&run_terminal_visible_automation_repl.step);

    const run_agent_demo = b.addRunArtifact(agent_demo);
    const agent_demo_step = b.step("example-agent", "Run the fmus agent demo");
    agent_demo_step.dependOn(&run_agent_demo.step);

    const run_ws_echo_server_demo = b.addRunArtifact(ws_echo_server_demo);
    const ws_echo_server_demo_step = b.step("example-ws-server", "Run the websocket echo server demo");
    ws_echo_server_demo_step.dependOn(&run_ws_echo_server_demo.step);

    const run_ws_echo_client_demo = b.addRunArtifact(ws_echo_client_demo);
    const ws_echo_client_demo_step = b.step("example-ws-client", "Run the websocket echo client demo");
    ws_echo_client_demo_step.dependOn(&run_ws_echo_client_demo.step);

    const run_automation_ws_server_demo = b.addRunArtifact(automation_ws_server_demo);
    const automation_ws_server_demo_step = b.step("example-terminal-automation-ws-server", "Run the terminal automation websocket server demo");
    automation_ws_server_demo_step.dependOn(&run_automation_ws_server_demo.step);

    const run_automation_ws_client_demo = b.addRunArtifact(automation_ws_client_demo);
    const automation_ws_client_demo_step = b.step("example-terminal-automation-ws-client", "Run the terminal automation websocket client demo");
    automation_ws_client_demo_step.dependOn(&run_automation_ws_client_demo.step);

    const run_zigsaw_demo = b.addRunArtifact(zigsaw_demo);
    const zigsaw_demo_step = b.step("example-zigsaw", "Run the zigsaw foundation demo");
    zigsaw_demo_step.dependOn(&run_zigsaw_demo.step);

    const run_zigsaw_runtime_demo = b.addRunArtifact(zigsaw_runtime_demo);
    const zigsaw_runtime_demo_step = b.step("example-zigsaw-runtime", "Run the zigsaw runtime demo");
    zigsaw_runtime_demo_step.dependOn(&run_zigsaw_runtime_demo.step);

    const run_zigsaw_platform_demo = b.addRunArtifact(zigsaw_platform_demo);
    const zigsaw_platform_demo_step = b.step("example-zigsaw-platform", "Run the zigsaw platform demo");
    zigsaw_platform_demo_step.dependOn(&run_zigsaw_platform_demo.step);

    if (supabase_ziggy_demo) |demo| {
        const build_step = b.step("example-supabase-ziggy", "Build the Supabase ziggy search demo");
        build_step.dependOn(&demo.step);

        const run_demo = b.addRunArtifact(demo);
        const run_step = b.step("run-supabase-ziggy-demo", "Run the Supabase ziggy search demo");
        run_step.dependOn(&run_demo.step);
    }

    if (supabase_ziggy_interactive_demo) |demo| {
        const build_step = b.step("example-supabase-ziggy-interactive", "Build the interactive Supabase ziggy search demo");
        build_step.dependOn(&demo.step);

        const run_demo = b.addRunArtifact(demo);
        const run_step = b.step("run-supabase-ziggy-interactive-demo", "Run the interactive Supabase ziggy search demo");
        run_step.dependOn(&run_demo.step);
    }
}
