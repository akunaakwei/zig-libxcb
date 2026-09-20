const std = @import("std");
const AutoConfigHeaderStep = @import("autoconfigheader").AutoConfigHeaderStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Linkage type for the library") orelse .static;
    const pic = b.option(bool, "pic", "Enable PIC") orelse (if (linkage == .dynamic) true else null);
    const queue_size = b.option(u32, "queue-size", "Set the XCB buffer queue size (default is 16384)") orelse 16384;

    const xcb_dep = b.dependency("xcb", .{});
    const xau_dep = b.dependency("xau", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .pic = pic,
    });
    const xau = xau_dep.artifact("xau");
    const xorgproto_dep = b.dependency("xorgproto", .{
        .target = target,
        .optimize = optimize,
    });
    const xorgproto = xorgproto_dep.artifact("xorgproto");

    const config_h = AutoConfigHeaderStep.create(b, target, .{
        .style = .blank,
        .include_path = "config.h",
    });
    config_h.config_header.addValues(.{
        .XCB_QUEUE_BUFFER_SIZE = queue_size,
        .HAVE_ABSTRACT_SOCKETS = if (target.result.os.tag == .linux) true else null,
    });
    config_h.addHaveFunction("HAVE_SENDMSG", "((struct msghdr *)0)->msg_control", &.{"sys/socket.h"});
    config_h.addHaveFunction("HAVE_SOCKADDR_SUN_LEN", "((struct sockaddr_un *)0)->sun_len", &.{ "sys/types.h", "sys/un.h" });
    config_h.addHaveHeader("HAVE_TSOL_LABEL_H", "tsol/label.h");
    config_h.addHaveFunction("HAVE_IS_SYSTEM_LABELED", "&is_system_labeled", &.{"tsol/label.h"});
    // TODO: check for IOV_MAX, and fall back to UIO_MAXIOV on BSDish systems
    config_h.addHaveFunction("HAVE_GETADDRINFO", "&getaddrinfo", &.{ "sys/types.h", "sys/socket.h", "netdb.h" });

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    mod.linkLibrary(xau);
    mod.linkLibrary(xorgproto);
    // TODO: libXdmcp integration

    mod.addIncludePath(b.path("src"));
    mod.addIncludePath(xcb_dep.path("src"));

    mod.addCMacro("HAVE_CONFIG_H", "1");
    mod.addConfigHeader(config_h.config_header);

    if (target.result.abi.isGnu()) {
        mod.addCMacro("_GNU_SOURCE", "1");
    }

    mod.addCSourceFiles(.{
        .root = xcb_dep.path("src"),
        .files = &sources,
    });
    mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &sources_generated,
    });

    const lib = b.addLibrary(.{
        .name = "xcb",
        .root_module = mod,
        .linkage = linkage,
    });
    lib.installHeadersDirectory(xcb_dep.path("src"), "xcb", .{});
    lib.installHeadersDirectory(xcb_dep.path("src"), ".", .{});
    lib.installHeadersDirectory(b.path("src"), ".", .{});
    b.installArtifact(lib);

    const gen = b.step("gen", "generate source code");
    const xcbproto_dep = b.dependency("xcbproto", .{});
    inline for (proto_sources) |proto_source| {
        const c_client_run = b.addSystemCommand(&.{"python3"});
        c_client_run.setCwd(b.path("src"));
        c_client_run.addFileArg(xcb_dep.path("src/c_client.py"));
        c_client_run.addArg("-p");
        c_client_run.addDirectoryArg(xcbproto_dep.path("."));
        c_client_run.addArg("-c");
        c_client_run.addArg("xcb");
        c_client_run.addArg("-l");
        c_client_run.addArg("");
        c_client_run.addArg("-s");
        c_client_run.addArg("man");
        c_client_run.addFileArg(xcbproto_dep.path(b.pathJoin(&.{ "src", proto_source })));
        gen.dependOn(&c_client_run.step);
    }
}

const sources = .{
    "xcb_conn.c",
    "xcb_out.c",
    "xcb_in.c",
    "xcb_ext.c",
    "xcb_xid.c",
    "xcb_list.c",
    "xcb_util.c",
    "xcb_auth.c",
};

const proto_sources = .{
    "bigreq.xml",
    "composite.xml",
    "damage.xml",
    "dbe.xml",
    "dpms.xml",
    "dri2.xml",
    "dri3.xml",
    "ge.xml",
    "glx.xml",
    "present.xml",
    "randr.xml",
    "record.xml",
    "render.xml",
    "res.xml",
    "screensaver.xml",
    "shape.xml",
    "shm.xml",
    "sync.xml",
    "xc_misc.xml",
    "xevie.xml",
    "xf86dri.xml",
    "xf86vidmode.xml",
    "xfixes.xml",
    "xinerama.xml",
    "xinput.xml",
    "xkb.xml",
    "xprint.xml",
    "xproto.xml",
    "xselinux.xml",
    "xtest.xml",
    "xv.xml",
    "xvmc.xml",
};

const sources_generated = .{
    "bigreq.c",
    "composite.c",
    "damage.c",
    "dbe.c",
    "dpms.c",
    "dri2.c",
    "dri3.c",
    "ge.c",
    "glx.c",
    "present.c",
    "randr.c",
    "record.c",
    "render.c",
    "res.c",
    "screensaver.c",
    "shape.c",
    "shm.c",
    "sync.c",
    "xc_misc.c",
    "xevie.c",
    "xf86dri.c",
    "xf86vidmode.c",
    "xfixes.c",
    "xinerama.c",
    "xinput.c",
    "xkb.c",
    "xprint.c",
    "xproto.c",
    "xselinux.c",
    "xtest.c",
    "xv.c",
    "xvmc.c",
};
