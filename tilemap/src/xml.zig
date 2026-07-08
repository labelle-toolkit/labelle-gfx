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
        if (pos.* < content.len and content[pos.*] == '"') {
            pos.* += 1;
            const val_start = pos.*;
            while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
            value = try allocator.dupe(u8, content[val_start..pos.*]);
            pos.* += 1;
        }

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
