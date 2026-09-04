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
const builtin = @import("builtin");

/// Bytes the numeric-reference scanner has examined, so a test can assert
/// the scan's BOUND rather than its wall-clock time (labelle-gfx#346).
/// Test builds only — `builtin.is_test` compiles both the counter and
/// every increment out of a shipped build, so this is neither a cost nor
/// a shared-mutable-state hazard at runtime.
var scan_steps: if (builtin.is_test) usize else void = if (builtin.is_test) 0 else {};

// ── XML Parsing Helpers ─────────────────────────────────────

pub const Attribute = struct {
    key: []const u8,
    value: []const u8,
    /// The VERBATIM bytes between the quotes, BEFORE entity decoding.
    ///
    /// A borrowed sub-slice of the `content` handed to `parseAttributes`:
    /// never allocated, never freed, and valid only while that buffer is.
    /// Empty when the attribute carried no quoted value.
    ///
    /// Read `value` unless you specifically need the undecoded bytes. The
    /// one caller that does is the external-`.tsx` resolver, which keeps
    /// honouring a key registered under the pre-#337 raw spelling; see
    /// `TilesetSourceResolver.resolveFn`.
    raw_value: []const u8 = "",
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
/// character XML permits (`&#xD800;`, `&#99999999;`, `&#0;`, `&#xFFFF;`,
/// the uppercase `&#X41;`) are copied byte-for-byte rather than raising.
/// This module is documented as a forgiving scanner, and the loader
/// around it degrades rather than fails on everything else it does not
/// understand (unknown elements are skipped, unsupported tileset shapes
/// warn). A stray `&` in a layer NAME is cosmetic; erroring would turn it
/// into a whole-map load failure, and an unescaped `&` is the single most
/// common way a hand-edited `.tmx` is not well-formed.
///
/// Pass-through is the CONSERVATIVE branch, which is why the accept set
/// is exactly XML's and no wider: bytes left alone stay the bytes the
/// document had, while decoding something XML never defined silently
/// rewrites a path nobody asked to rewrite.
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
    // XML 1.0 spells the hexadecimal form with a LOWERCASE `x` only —
    // `CharRef ::= '&#' [0-9]+ ';' | '&#x' [0-9a-fA-F]+ ';'` — so `&#X41;`
    // is not a character reference at all. Decoding it would rewrite a
    // path that legitimately contains those bytes, which is the very bug
    // the pass-through policy exists to avoid, so it goes through
    // verbatim like any other malformed reference (labelle-gfx#346).
    const base: u8 = if (j < rest.len and rest[j] == 'x') blk: {
        j += 1;
        break :blk 16;
    } else 10;

    // Scan the DIGIT RUN, not the whole remaining value. Hunting forward
    // for a `;` made a hostile or corrupted attribute quadratic: a value
    // of many `&#` starts had every one of them walk the entire suffix
    // before returning null, after which the outer loop advanced a single
    // byte (labelle-gfx#346). A `&` is never a digit in either base, so a
    // run stops before it can reach the next start and every input byte is
    // examined a bounded number of times.
    const digits_start = j;
    while (j < rest.len) : (j += 1) {
        if (builtin.is_test) scan_steps += 1;
        if (!isDigitInBase(rest[j], base)) break;
    }
    // Unterminated (`&#41`), or a non-digit before the `;` (`&#xZZ;`).
    if (j >= rest.len or rest[j] != ';') return null;
    const digits = rest[digits_start..j];
    if (digits.len == 0) return null; // `&#;` / `&#x;`

    // `u21` holds every Unicode scalar and rejects anything past 0x1FFFFF
    // as an overflow; `isXmlChar` then rejects every code point outside
    // XML 1.0's `Char` production. All land on the pass-through branch.
    const cp = std.fmt.parseUnsigned(u21, digits, base) catch return null;
    if (!isXmlChar(cp)) return null;
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return null;
    out.appendSliceAssumeCapacity(buf[0..n]);
    return j + 2; // '&' + everything up to and including the ';'
}

fn isDigitInBase(c: u8, base: u8) bool {
    return if (base == 16) std.ascii.isHex(c) else std.ascii.isDigit(c);
}

/// XML 1.0 §2.2 `Char`:
///
///     Char ::= #x9 | #xA | #xD | [#x20-#xD7FF]
///            | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
///
/// A reference naming anything else — NUL, a C0 control other than tab /
/// LF / CR, a surrogate, U+FFFE, U+FFFF — is not well-formed XML, so
/// decoding it would inject a byte no conforming document asked for into
/// what is very often a filesystem path. `&#0;` in an `<image source>`
/// used to be a literal (broken but nameable) path; encoding it would
/// make it an unopenable one. Pass those through instead (labelle-gfx#346).
fn isXmlChar(cp: u21) bool {
    return cp == 0x9 or cp == 0xA or cp == 0xD or
        (cp >= 0x20 and cp <= 0xD7FF) or
        (cp >= 0xE000 and cp <= 0xFFFD) or
        (cp >= 0x10000 and cp <= 0x10FFFF);
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
        var raw_value: []const u8 = "";
        var value_owned = false;
        if (pos.* < content.len and content[pos.*] == '"') {
            pos.* += 1;
            const val_start = pos.*;
            while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
            // Borrowed, not duped: `raw_value` points into `content` and
            // is never freed (see `Attribute.raw_value`).
            raw_value = content[val_start..pos.*];
            value = try decodeEntities(allocator, raw_value);
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

        try attrs.append(allocator, .{ .key = key, .value = value, .raw_value = raw_value });
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

/// `attr.raw_value` is a borrowed sub-slice of the parsed document and is
/// deliberately NOT freed here. `attr.value` for a valueless attribute is
/// the `""` literal; `Allocator.free` returns immediately on a zero-length
/// slice without touching the pointer, so the unconditional free is safe
/// for it (a test below pins that).
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

/// `getAttr`, but the UNDECODED bytes — see `Attribute.raw_value` for why
/// this exists and why it borrows the document.
pub fn getAttrRaw(attrs: []const Attribute, key: []const u8) ?[]const u8 {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.key, key)) return attr.raw_value;
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
    try expectDecodes("&#4 1;", "&#4 1;"); // non-digit before the `;`
    // A real entity still decodes when it shares the value with junk.
    try expectDecodes("&bogus; &amp; x", "&bogus; & x");
}

test "numeric character references decode in both spellings" {
    try expectDecodes("&#65;", "A");
    try expectDecodes("&#x41;", "A");
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

// ── Review findings on labelle-gfx#346 ──

test "an uppercase &#X…; is not a character reference" {
    // XML 1.0 spells CharRef's hex form with a lowercase `x` only, so
    // `&#X41;` is ordinary text. Decoding it would corrupt a path that
    // happens to contain those bytes.
    try expectDecodes("&#X41;", "&#X41;");
    try expectDecodes("&#X1F600;", "&#X1F600;");
    // The lowercase form still decodes, unchanged.
    try expectDecodes("&#x41;", "A");
}

test "a reference outside XML's Char production passes through" {
    // Decoding these injects a NUL / control / noncharacter into what is
    // usually a filesystem path, turning a literal-but-nameable path into
    // an unopenable one — against the pass-through policy.
    try expectDecodes("&#0;", "&#0;");
    try expectDecodes("&#x0;", "&#x0;");
    try expectDecodes("&#x1;", "&#x1;");
    try expectDecodes("&#x1F;", "&#x1F;"); // C0 control
    try expectDecodes("&#8;", "&#8;"); // backspace
    try expectDecodes("&#xB;", "&#xB;"); // vertical tab
    try expectDecodes("&#xFFFE;", "&#xFFFE;");
    try expectDecodes("&#xFFFF;", "&#xFFFF;");
    try expectDecodes("&#xDFFF;", "&#xDFFF;"); // high surrogate end
    // In situ: the path keeps its literal bytes rather than gaining a NUL.
    try expectDecodes("map&#0;.png", "map&#0;.png");
}

test "the three permitted control characters still decode" {
    // `Char` admits exactly #x9, #xA and #xD below #x20 — a stricter
    // filter than "printable", and these are legal in an attribute.
    try expectDecodes("&#x9;", "\t");
    try expectDecodes("&#xA;", "\n");
    try expectDecodes("&#xD;", "\r");
    // …and the boundaries either side of the surrogate/noncharacter gaps.
    try expectDecodes("&#x20;", " ");
    try expectDecodes("&#xD7FF;", "\u{D7FF}");
    try expectDecodes("&#xE000;", "\u{E000}");
    try expectDecodes("&#xFFFD;", "\u{FFFD}");
    try expectDecodes("&#x10000;", "\u{10000}");
    try expectDecodes("&#x10FFFF;", "\u{10FFFF}");
}

test "many unterminated numeric starts do not scan quadratically" {
    // A corrupted or hostile `.tmx` can hold an attribute made of nothing
    // but `&#`. Hunting forward for a `;` made every one of those starts
    // walk the whole remaining value before returning null, after which
    // the outer loop advanced a single byte — O(n^2), enough to stall a
    // load. The digit-run scan makes it linear.
    //
    // Asserted on the deterministic quantity the fix changes (bytes the
    // numeric scanner examines), not on the wall clock: Zig 0.16 has no
    // `std.time.Timer` and timing asserts are flaky in CI — the same call
    // this repo's #208 culling benchmark makes.
    const n = 48_000;
    const raw = try std.testing.allocator.alloc(u8, n);
    defer std.testing.allocator.free(raw);
    var k: usize = 0;
    while (k < n) : (k += 2) {
        raw[k] = '&';
        raw[k + 1] = '#';
    }

    scan_steps = 0;
    const got = try decodeEntities(std.testing.allocator, raw);
    defer std.testing.allocator.free(got);

    // Nothing resolves, so the value is unchanged.
    try std.testing.expectEqualStrings(raw, got);
    // 24_000 starts, each examining exactly ONE byte — the `&` opening
    // the next start, which is not a digit in either base and ends the
    // run at once (the final start runs off the end and examines none).
    // The `;`-hunting scan examined ~n^2/4 = 5.8e8 bytes for this same
    // input: five orders of magnitude more, and quadratic in `n`.
    try std.testing.expectEqual(@as(usize, 23_999), scan_steps);
}

test "the numeric scan never crosses into the next reference" {
    // The general bound, on a value that DOES have digits: each start
    // examines only its own digit run, so total scan work is linear in
    // the value length however many starts it holds.
    const raw = "&#12&#12&#12&#12" ** 100; // 100 starts, 2 digits each
    scan_steps = 0;
    const got = try decodeEntities(std.testing.allocator, raw);
    defer std.testing.allocator.free(got);

    try std.testing.expectEqualStrings(raw, got);
    // 400 starts x (2 digits + the `&` that stops the run), less the one
    // byte the final start runs out of input before examining.
    try std.testing.expectEqual(@as(usize, 1_199), scan_steps);
}

// ── Attribute.raw_value ──

test "raw_value keeps the undecoded bytes and is not freed" {
    // `freeAttributes` must free key and value but never `raw_value`,
    // which borrows the document. std.testing.allocator panics on a free
    // of memory it does not own, so a stray free fails here.
    const content = "source=\"odd&amp;name.tsx\" plain=\"a.tsx\">";
    var pos: usize = 0;
    const parsed = try parseAttributes(std.testing.allocator, content, &pos);
    defer freeAttributes(std.testing.allocator, parsed.attrs);

    try std.testing.expectEqualStrings("odd&name.tsx", getAttr(parsed.attrs, "source").?);
    try std.testing.expectEqualStrings("odd&amp;name.tsx", getAttrRaw(parsed.attrs, "source").?);
    // Identity for an entity-free value: raw and decoded agree.
    try std.testing.expectEqualStrings("a.tsx", getAttr(parsed.attrs, "plain").?);
    try std.testing.expectEqualStrings("a.tsx", getAttrRaw(parsed.attrs, "plain").?);
    try std.testing.expect(getAttrRaw(parsed.attrs, "missing") == null);
}

test "an attribute with no quoted value survives parse and free" {
    // The value stays the `""` literal, which `freeAttributes` and the
    // errdefer chain both hand to `allocator.free`. That is safe —
    // `Allocator.free` returns on a zero-length slice before it can touch
    // the pointer — but the guarantee is worth pinning: the testing
    // allocator would flag any real free of unowned memory, and the OOM
    // path exercises the same value through the errdefer.
    {
        const content = "bare other=\"x\">";
        var pos: usize = 0;
        const parsed = try parseAttributes(std.testing.allocator, content, &pos);
        defer freeAttributes(std.testing.allocator, parsed.attrs);

        try std.testing.expectEqualStrings("", getAttr(parsed.attrs, "bare").?);
        try std.testing.expectEqualStrings("", getAttrRaw(parsed.attrs, "bare").?);
        try std.testing.expectEqualStrings("x", getAttr(parsed.attrs, "other").?);
    }
    {
        // Allocation order for `bare other="x"`: 0 dupe("bare"),
        // 1 attrs.append grow. Failing #1 runs the function-level errdefer
        // over an already-appended… nothing, and the per-value errdefer
        // over the unowned `""`.
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
        const alloc = failing.allocator();
        const content = "bare other=\"x\">";
        var pos: usize = 0;
        try std.testing.expectError(error.OutOfMemory, parseAttributes(alloc, content, &pos));
        try std.testing.expect(failing.has_induced_failure);
    }
}
