//! Generic XML attribute tokenizer — the low-level parsing primitives.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): a small, forgiving
//! scanner over the subset of XML the TMX loader needs — it reads an
//! element's attributes into key/value pairs and reports whether the tag
//! self-closed. Consumed by `tile_map.zig`.
//!
//! Attribute VALUES are entity-decoded (labelle-gfx#337): Tiled escapes
//! `& < > " '` on the way out, so a value stored verbatim is not the
//! string the document meant — `source="tiles&amp;more.png"` names the
//! file `tiles&more.png`, and the raw bytes open nothing. Decoding here
//! rather than at each consumer keeps the one rule in one place; see
//! `decodeEntities` for the malformed-input policy.

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

// ── XML entity decoding (labelle-gfx#337) ───────────────────

/// One predefined XML entity. `name` carries the terminating `;` so a
/// match is a single `startsWith` with no second bounds check.
const NamedEntity = struct { name: []const u8, byte: u8 };

/// The five entities XML predefines. There is no DTD in a `.tmx`/`.tsx`,
/// so this is the complete set a Tiled document can name.
const named_entities = [_]NamedEntity{
    .{ .name = "amp;", .byte = '&' },
    .{ .name = "lt;", .byte = '<' },
    .{ .name = "gt;", .byte = '>' },
    .{ .name = "quot;", .byte = '"' },
    .{ .name = "apos;", .byte = '\'' },
};

/// Decode XML character references in an attribute value, returning a
/// fresh allocation the caller owns.
///
/// Handles the five predefined entities (`&amp; &lt; &gt; &quot; &apos;`)
/// and numeric character references in both spellings (`&#65;`, `&#x41;`),
/// which are encoded to UTF-8. Numeric references are in scope because
/// Tiled is not the only writer of these files — an exporter that escapes
/// every non-ASCII byte is legal XML, and leaving `&#233;` in a path
/// reproduces exactly the bug this decodes away.
///
/// **Malformed input passes through verbatim.** `&notanentity;`, a bare
/// `&`, an unterminated `&amp`, and a numeric reference naming no
/// character (`&#xD800;`, `&#99999999;`) are copied byte-for-byte rather
/// than raising. This module is documented as a forgiving scanner, and
/// the loader around it degrades rather than fails on everything else it
/// does not understand (unknown elements are skipped, unsupported tileset
/// shapes warn). A stray `&` in a layer NAME is cosmetic; erroring would
/// turn it into a whole-map load failure, and an unescaped `&` is the
/// single most common way a hand-edited `.tmx` is not well-formed.
pub fn decodeEntities(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Fast path: no `&` means no reference, so the decoded value IS the
    // raw bytes — one dupe, byte-identical to the pre-#337 behaviour and
    // with no second pass. This is every attribute in a normal document.
    if (std.mem.indexOfScalar(u8, raw, '&') == null) return allocator.dupe(u8, raw);

    // Every reference is longer than the text it stands for — the
    // shortest, `&#N;`, is 4 bytes for at most 1 — so the raw length is a
    // safe, exact-enough upper bound and the appends below never grow.
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacityPrecise(allocator, raw.len);

    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '&') {
            if (decodeReference(raw[i..], &out)) |consumed| {
                i += consumed;
                continue;
            }
        }
        out.appendAssumeCapacity(raw[i]);
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

/// Decode the reference starting at `s[0] == '&'`, appending its
/// replacement text to `out` and returning the bytes consumed. Null when
/// `s` does not open a reference this understands — the caller then
/// copies the `&` through verbatim. Nothing is appended on a null return,
/// so a partial reference cannot leave half a character behind.
fn decodeReference(s: []const u8, out: *std.ArrayListUnmanaged(u8)) ?usize {
    const rest = s[1..];

    for (named_entities) |e| {
        if (std.mem.startsWith(u8, rest, e.name)) {
            out.appendAssumeCapacity(e.byte);
            return 1 + e.name.len;
        }
    }

    if (rest.len == 0 or rest[0] != '#') return null;

    var j: usize = 1;
    const base: u8 = if (j < rest.len and (rest[j] == 'x' or rest[j] == 'X')) blk: {
        j += 1;
        break :blk 16;
    } else 10;

    const digits_start = j;
    while (j < rest.len and rest[j] != ';') : (j += 1) {}
    if (j >= rest.len) return null; // unterminated: `&#41` with no `;`
    const digits = rest[digits_start..j];
    if (digits.len == 0) return null; // `&#;` / `&#x;`

    // `u21` holds every Unicode scalar and rejects anything past 0x1FFFFF
    // as an overflow; `utf8Encode` then rejects surrogates and anything
    // above U+10FFFF. Both land on the pass-through branch.
    const cp = std.fmt.parseUnsigned(u21, digits, base) catch return null;
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return null;
    out.appendSliceAssumeCapacity(buf[0..n]);
    return j + 2; // '&' + everything up to and including the ';'
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
            value = try decodeEntities(allocator, content[val_start..pos.*]);
            value_owned = true;
            pos.* += 1;
        }
        // `value` is either the `""` literal (no value present) or a fresh
        // allocation from `decodeEntities` — free it only when owned, so an
        // OOM at `append` below does not leak it (and never frees the
        // literal). Ownership is unchanged by #337: values were ALREADY
        // owned dupes, so decoding only changes the bytes in the
        // allocation, never who frees it. `freeAttributes` is untouched
        // and no caller of `parseAttributes` had to change.
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

// ── Entity decoding in attribute values (#337) ──

/// Parse `a="<raw>"` and return the decoded value, caller-owned.
fn attrValueForTest(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const content = try std.fmt.allocPrint(allocator, "a=\"{s}\">", .{raw});
    defer allocator.free(content);
    var pos: usize = 0;
    const parsed = try parseAttributes(allocator, content, &pos);
    defer freeAttributes(allocator, parsed.attrs);
    return allocator.dupe(u8, getAttr(parsed.attrs, "a").?);
}

fn expectDecodes(raw: []const u8, want: []const u8) !void {
    const got = try attrValueForTest(std.testing.allocator, raw);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings(want, got);
}

test "parseAttributes decodes each of the five predefined entities" {
    try expectDecodes("&amp;", "&");
    try expectDecodes("&lt;", "<");
    try expectDecodes("&gt;", ">");
    try expectDecodes("&quot;", "\"");
    try expectDecodes("&apos;", "'");
}

test "an entity mid-string decodes without disturbing its neighbours" {
    // The issue's headline case: a path Tiled escaped on the way out.
    try expectDecodes("tiles&amp;more.png", "tiles&more.png");
    try expectDecodes("a&lt;b&gt;c", "a<b>c");
    // Back to back, and at both ends.
    try expectDecodes("&amp;&amp;", "&&");
    try expectDecodes("&amp;lead", "&lead");
    try expectDecodes("trail&amp;", "trail&");
    // The classic double-escape: `&amp;amp;` is the TEXT `&amp;`, decoded
    // once and once only — a second pass would wrongly yield `&`.
    try expectDecodes("&amp;amp;", "&amp;");
}

test "malformed references pass through verbatim rather than erroring" {
    try expectDecodes("&notanentity;", "&notanentity;");
    try expectDecodes("a & b", "a & b");
    try expectDecodes("&", "&");
    try expectDecodes("&amp", "&amp"); // unterminated
    try expectDecodes("&#;", "&#;");
    try expectDecodes("&#x;", "&#x;");
    try expectDecodes("&#41", "&#41"); // no terminator
    try expectDecodes("&#xZZ;", "&#xZZ;"); // not hex digits
    try expectDecodes("&#xD800;", "&#xD800;"); // lone surrogate: no UTF-8
    try expectDecodes("&#99999999;", "&#99999999;"); // past U+10FFFF
    // A real entity still decodes when it shares the value with junk.
    try expectDecodes("&bogus; &amp; x", "&bogus; & x");
}

test "numeric character references decode in both spellings" {
    try expectDecodes("&#65;", "A");
    try expectDecodes("&#x41;", "A");
    try expectDecodes("&#X41;", "A");
    try expectDecodes("&#0065;", "A"); // leading zeros
    try expectDecodes("caf&#233;.png", "caf\u{e9}.png"); // 2-byte UTF-8
    try expectDecodes("&#x4E2D;", "\u{4E2D}"); // 3-byte
    try expectDecodes("&#x1F600;", "\u{1F600}"); // 4-byte, the capacity bound
}

test "a value with no entity takes the allocation-free decode path" {
    // The common case must cost exactly what the pre-#337 plain dupe cost:
    // ONE allocation, no scratch buffer and no second copy. A decoder that
    // always buffered would show two.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 64 });
    const alloc = failing.allocator();

    const got = try decodeEntities(alloc, "tilesets/plain.png");
    defer alloc.free(got);

    try std.testing.expectEqualStrings("tilesets/plain.png", got);
    try std.testing.expectEqual(@as(usize, 1), failing.allocations);
}

test "decoding does not disturb attribute keys or the self-close flag" {
    const content = "source=\"a&amp;b.png\" width=\"64\"/>";
    var pos: usize = 0;
    const parsed = try parseAttributes(std.testing.allocator, content, &pos);
    defer freeAttributes(std.testing.allocator, parsed.attrs);

    try std.testing.expect(parsed.self_closed);
    try std.testing.expectEqualStrings("a&b.png", getAttr(parsed.attrs, "source").?);
    try std.testing.expectEqualStrings("64", getAttr(parsed.attrs, "width").?);
}

test "an OOM while decoding a value leaks nothing" {
    // Allocation order for `a="x&amp;y"`: 0 key, 1 the decode buffer,
    // 2 attrs.append. Failing #2 exercises the value errdefer against a
    // DECODED (ArrayList-owned) allocation rather than a plain dupe.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    const alloc = failing.allocator();

    const content = "a=\"x&amp;y\">";
    var pos: usize = 0;
    try std.testing.expectError(error.OutOfMemory, parseAttributes(alloc, content, &pos));
    try std.testing.expect(failing.has_induced_failure);
}
