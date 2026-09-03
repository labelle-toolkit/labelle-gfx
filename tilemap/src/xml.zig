//! Generic XML attribute tokenizer — the low-level parsing primitives.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): a small, forgiving
//! scanner over the subset of XML the TMX loader needs — it reads an
//! element's attributes into key/value pairs and reports whether the tag
//! self-closed. Consumed by `tile_map.zig`.

const std = @import("std");

// ── XML Parsing Helpers ─────────────────────────────────────

pub const Attribute = struct {
    key: []const u8,
    value: []const u8,
};

pub const ParsedAttributes = struct {
    attrs: []Attribute,
    /// True when the element was self-closed (`<tag ... />`) — the
    /// caller must not scan for a closing tag that will never come.
    self_closed: bool,
};

/// True at any byte that ends an XML element name. Tiled is not the only
/// writer of `.tmx`/`.tsx` files, and XML lets an element break across
/// lines — `<image\n    source="tiles.png"/>` — so EVERY whitespace byte
/// ends the name, not just SPACE. A SPACE-only scan yields the name
/// `"image\n"`, matches nothing, and silently drops the element
/// (labelle-gfx#340).
pub fn isElementNameEnd(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>' or c == '/';
}

pub fn parseAttributes(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !ParsedAttributes {
    var attrs: std.ArrayListUnmanaged(Attribute) = .empty;
    errdefer {
        for (attrs.items) |attr| {
            allocator.free(attr.key);
            allocator.free(attr.value);
        }
        attrs.deinit(allocator);
    }

    while (pos.* < content.len and content[pos.*] != '>' and content[pos.*] != '/') {
        while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t')) : (pos.* += 1) {}
        if (pos.* >= content.len or content[pos.*] == '>' or content[pos.*] == '/') break;

        const key_start = pos.*;
        while (pos.* < content.len and content[pos.*] != '=' and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
        if (key_start == pos.*) break;
        const key = try allocator.dupe(u8, content[key_start..pos.*]);
        errdefer allocator.free(key);

        while (pos.* < content.len and content[pos.*] == '=') : (pos.* += 1) {}

        var value: []const u8 = "";
        var value_owned = false;
        if (pos.* < content.len and content[pos.*] == '"') {
            pos.* += 1;
            const val_start = pos.*;
            while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
            value = try allocator.dupe(u8, content[val_start..pos.*]);
            value_owned = true;
            pos.* += 1;
        }
        // `value` is either the `""` literal (no value present) or a fresh
        // dupe — free it only when owned, so an OOM at `append` below does
        // not leak the duped value (and never frees the literal).
        errdefer if (value_owned) allocator.free(value);

        try attrs.append(allocator, .{ .key = key, .value = value });
    }

    var self_closed = false;
    while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {
        if (content[pos.*] == '/') self_closed = true;
    }
    pos.* += 1;

    return .{
        .attrs = try attrs.toOwnedSlice(allocator),
        .self_closed = self_closed,
    };
}

pub fn freeAttributes(allocator: std.mem.Allocator, attrs: []Attribute) void {
    for (attrs) |attr| {
        allocator.free(attr.key);
        allocator.free(attr.value);
    }
    allocator.free(attrs);
}

pub fn getAttr(attrs: []const Attribute, key: []const u8) ?[]const u8 {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.key, key)) return attr.value;
    }
    return null;
}

// ── Regression: OOM after a quoted value is duped must not leak (#300) ──

test "parseAttributes frees a duped value when the append OOMs" {
    // Allocation order inside the attribute loop for `a="b"`:
    //   0 → dupe(key)   1 → dupe(value)   2 → attrs.append grow
    // Failing #2 makes `append` OOM *after* the value was duped, exercising
    // the value errdefer. std.testing.allocator (the backing allocator)
    // flags any leak at teardown, so a missing free fails this test.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    const alloc = failing.allocator();

    const content = "a=\"b\">";
    var pos: usize = 0;
    try std.testing.expectError(error.OutOfMemory, parseAttributes(alloc, content, &pos));
    try std.testing.expect(failing.has_induced_failure);
}

// ── Regression: every whitespace byte ends an element name (#340) ──

test "isElementNameEnd accepts every XML whitespace, not just SPACE" {
    for ([_]u8{ ' ', '\t', '\n', '\r', '>', '/' }) |c| {
        try std.testing.expect(isElementNameEnd(c));
    }
    for ("imageMAP_0-:.") |c| {
        try std.testing.expect(!isElementNameEnd(c));
    }
}
