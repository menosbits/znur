const std = @import("std");
const zz = @import("zigzag");
const apps = @import("apps.zig");

const Message = @import("config.zig").Message;
const Config = @import("config.zig").Config;

pub const Model = struct {
    search_bar: zz.TextInput,
    result_list: zz.List(apps.Application),
    max_width: usize = 0,
    env: *std.process.Environ.Map,
    config: Config,
    modal: zz.Modal,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        // Search bar
        self.search_bar = zz.TextInput.init(ctx.persistent_allocator);
        self.search_bar.setPlaceholder(self.config.placeholder);
        self.search_bar.setPrompt(self.config.prompt);

        // Result list
        self.result_list = zz.List(apps.Application).init(ctx.persistent_allocator);
        self.result_list.show_item_count = true;
        self.result_list.wrap_around = false;
        self.result_list.cursor_symbol = self.config.marker;

        // Modal for error messages
        self.modal = zz.Modal.init();

        // Apps
        const Item = zz.List(apps.Application).Item;

        const finded_apps = apps.find(ctx.persistent_allocator, ctx.io, self.env) catch (&([_]apps.Application{}))[0..];
        defer ctx.persistent_allocator.free(finded_apps);

        for (0..finded_apps.len - 1) |i| {
            if (finded_apps[i].display) {
                self.result_list.addItem(Item.init(
                    finded_apps[i],
                    finded_apps[i].name,
                )) catch {};
                if (finded_apps[i].name.len > self.max_width)
                    self.max_width = finded_apps[i].name.len;
            }
        }

        self.search_bar.focus();

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (self.modal.isVisible()) {
                    self.modal.handleKey(k);
                    return .quit;
                }

                switch (k.key) {
                    .escape => return .quit,
                    .enter => {
                        self.result_list.handleKey(k);
                        const selected_app = self.result_list.selectedValue();
                        if (selected_app) |app| app.run(ctx.allocator, ctx.io, self.env, &self.config) catch {
                            self.modal = zz.Modal.err("Error", "Terminal not found!\nCheck your config.");
                            self.modal.show();
                        };
                        if (!self.modal.isVisible()) return .quit;
                    },
                    .up, .down, .page_up, .page_down, .home, .end => {
                        self.result_list.handleKey(k);
                    },
                    .char, .backspace, .delete, .left, .right, .paste => {
                        self.search_bar.handleKey(k);
                        const search = self.search_bar.getValue();
                        self.result_list.setFilter(search) catch {};
                    },
                    else => {},
                }
            },
        }

        return .none;
    }

    pub fn view(self: *Model, ctx: *const zz.Context) []const u8 {
        const max_width: u16 = @intCast(self.max_width);
        const w: u16 = @intCast(@min(ctx.width, std.math.maxInt(u16)));
        const h: u16 = @intCast(@min(ctx.height, std.math.maxInt(u16)));
        if (w < 70 or h < 15) {
            const content = std.fmt.allocPrint(
                ctx.allocator,
                "Window must have at least 70x15 px.",
                .{},
            ) catch "Error!";
            return zz.place.place(ctx.allocator, w, h, .center, .middle, content) catch "Error!";
        } else {
            // Modal
            if (self.modal.isVisible()) {
                return self.modal.viewWithBackdrop(ctx.allocator, ctx.width, ctx.height) catch "Error";
            }

            // zmenu Title
            var t_style = (zz.Style{})
                .width(max_width)
                .fg(zz.Color.white)
                .inline_style(true)
                .alignH(.center);

            const title = t_style.render(ctx.allocator, "zmenu") catch "zmenu";
            const centered_title = zz.layout.placeCenter(ctx.allocator, w, 1, title) catch title;

            // Search bar
            const search_bar = self.search_bar.view(ctx.allocator) catch "Error";
            const sb_box = (zz.Style{})
                .paddingLeft(2)
                .paddingRight(2)
                .width(max_width)
                .marginLeft((w - max_width) / 2 - 1)
                .marginRight((w - max_width) / 2 - 1);
            const sb_view = sb_box.render(ctx.allocator, search_bar) catch "Error";

            // Result list
            const result_list = self.result_list.view(ctx.allocator) catch "Error";
            const rl_box = (zz.Style{})
                .maxWidth(max_width)
                .marginLeft((w - max_width) / 2 - 1)
                .marginRight((w - max_width) / 2 - 1);
            const rl_view = rl_box.render(ctx.allocator, result_list) catch "Error";

            // Join everything
            const content = std.fmt.allocPrint(
                ctx.allocator,
                "{s}\n\n{s}\n{s}",
                .{ centered_title, sb_view, rl_view },
            ) catch "Error!";

            return zz.place.place(ctx.allocator, w, h, .center, .middle, content) catch "Error!";
        }
    }

    pub fn deinit(self: *Model) void {
        self.search_bar.deinit();
        self.result_list.deinit();
    }
};
