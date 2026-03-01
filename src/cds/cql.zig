const std = @import("std");
const temporal = @import("temporal.zig");
const valueset = @import("valueset.zig");

/// CQL-lite expression engine for evaluating clinical quality logic over FHIR resources.
///
/// This implements the subset of CQL (Clinical Quality Language) needed for quality
/// measures and CDS, operating on parsed JSON FHIR resources represented as a
/// simple recursive value type.
///
/// It does NOT implement full CQL/ELM compilation - instead it provides a direct
/// Zig API that mirrors CQL semantics for use in measure definitions.

/// A simplified representation of a FHIR resource field value.
/// Used by the CQL engine to process FHIR data without depending on
/// the FHIRPath evaluator's internal types.
pub const CqlValue = union(enum) {
    null_val: void,
    boolean: bool,
    integer: i64,
    decimal: f64,
    string: []const u8,
    date: temporal.Date,
    datetime: temporal.Date, // simplified: datetime treated as date for measure purposes
    quantity: Quantity,
    resource: Resource,
    list: []const CqlValue,

    pub fn isNull(self: CqlValue) bool {
        return switch (self) {
            .null_val => true,
            else => false,
        };
    }

    pub fn asBool(self: CqlValue) ?bool {
        return switch (self) {
            .boolean => |b| b,
            else => null,
        };
    }

    pub fn asString(self: CqlValue) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn asDate(self: CqlValue) ?temporal.Date {
        return switch (self) {
            .date, .datetime => |d| d,
            .string => |s| temporal.Date.parse(s) catch null,
            else => null,
        };
    }

    pub fn asDecimal(self: CqlValue) ?f64 {
        return switch (self) {
            .decimal => |d| d,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        };
    }

    pub fn asList(self: CqlValue) []const CqlValue {
        return switch (self) {
            .list => |l| l,
            .null_val => &[_]CqlValue{},
            else => @as(*const [1]CqlValue, @ptrCast(&self)),
        };
    }
};

pub const Quantity = struct {
    value: f64,
    unit: []const u8,
};

/// A parsed FHIR resource represented as key-value pairs.
pub const Resource = struct {
    resource_type: []const u8,
    fields: []const Field,

    pub fn get(self: Resource, name: []const u8) CqlValue {
        for (self.fields) |f| {
            if (std.mem.eql(u8, f.name, name)) return f.value;
        }
        return .{ .null_val = {} };
    }
};

pub const Field = struct {
    name: []const u8,
    value: CqlValue,
};

/// Coding type for code lookups.
pub const Coding = struct {
    system: []const u8,
    code: []const u8,
    display: []const u8 = "",
};

// ============================================================================
// FHIR JSON Extraction Helpers (allocation-free)
// ============================================================================

/// Build a quoted field needle like `"fieldName"` into a stack buffer.
/// Returns the slice of the buffer used, or null if the field name is too long.
fn buildNeedle(buf: *[256]u8, field_name: []const u8) ?[]const u8 {
    if (field_name.len + 2 > buf.len) return null;
    buf[0] = '"';
    @memcpy(buf[1 .. 1 + field_name.len], field_name);
    buf[1 + field_name.len] = '"';
    return buf[0 .. field_name.len + 2];
}

/// Extract a string field from a raw JSON string using simple parsing.
/// This is a lightweight alternative to full JSON parsing for extracting
/// individual fields from FHIR resources. Zero allocations.
pub fn extractJsonString(json: []const u8, field_name: []const u8) ?[]const u8 {
    var buf: [256]u8 = undefined;
    const needle = buildNeedle(&buf, field_name) orelse return null;

    const pos = std.mem.indexOf(u8, json, needle) orelse return null;
    var i = pos + needle.len;

    // Skip whitespace and colon
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r')) : (i += 1) {}

    if (i >= json.len or json[i] != '"') return null;
    i += 1; // skip opening quote

    const start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\') i += 1; // skip escaped char
    }
    if (i >= json.len) return null;
    return json[start..i];
}

/// Extract codings from a FHIR CodeableConcept JSON object.
/// Returns true if any coding matches the given value set.
pub fn codeableConceptInValueSet(json: []const u8, vs: *const valueset.ValueSet) bool {
    // Look for "system" and "code" pairs within coding arrays
    var search_pos: usize = 0;
    while (search_pos < json.len) {
        const code_pos = std.mem.indexOf(u8, json[search_pos..], "\"code\"") orelse break;
        const abs_code_pos = search_pos + code_pos;

        if (extractJsonStringAt(json, abs_code_pos + 6)) |code| {
            // Search backwards for matching system
            const context_start = if (abs_code_pos > 200) abs_code_pos - 200 else 0;
            const context = json[context_start..abs_code_pos];
            if (lastJsonStringValue(context, "system")) |system| {
                if (vs.contains(system, code)) return true;
            }
            // Also try just the code without system
            if (vs.containsCode(code)) {
                // Only if we're in a coding context
                if (std.mem.indexOf(u8, json[context_start..abs_code_pos], "\"coding\"") != null) {
                    return true;
                }
            }
        }
        search_pos = abs_code_pos + 6;
    }
    return false;
}

fn extractJsonStringAt(json: []const u8, start: usize) ?[]const u8 {
    var i = start;
    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r')) : (i += 1) {}
    if (i >= json.len or json[i] != '"') return null;
    i += 1;
    const s = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\') i += 1;
    }
    if (i >= json.len) return null;
    return json[s..i];
}

fn lastJsonStringValue(context: []const u8, field: []const u8) ?[]const u8 {
    var buf: [256]u8 = undefined;
    const needle = buildNeedle(&buf, field) orelse return null;

    // Find the last occurrence
    var last_pos: ?usize = null;
    var search: usize = 0;
    while (search < context.len) {
        const pos = std.mem.indexOf(u8, context[search..], needle) orelse break;
        last_pos = search + pos;
        search = search + pos + needle.len;
    }
    if (last_pos) |pos| {
        return extractJsonStringAt(context, pos + needle.len);
    }
    return null;
}

/// Extract a numeric value from a JSON field.
pub fn extractJsonNumber(json: []const u8, field_name: []const u8) ?f64 {
    var buf: [256]u8 = undefined;
    const needle = buildNeedle(&buf, field_name) orelse return null;

    const pos = std.mem.indexOf(u8, json, needle) orelse return null;
    var i = pos + needle.len;

    while (i < json.len and (json[i] == ' ' or json[i] == ':' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r')) : (i += 1) {}

    if (i >= json.len) return null;

    const start = i;
    while (i < json.len and (json[i] == '-' or json[i] == '+' or json[i] == '.' or (json[i] >= '0' and json[i] <= '9') or json[i] == 'e' or json[i] == 'E')) : (i += 1) {}

    if (i == start) return null;
    return std.fmt.parseFloat(f64, json[start..i]) catch null;
}

/// Extract a date from a JSON field.
pub fn extractJsonDate(json: []const u8, field_name: []const u8) ?temporal.Date {
    const s = extractJsonString(json, field_name) orelse return null;
    // FHIR dates might have time components; truncate at 'T' for date-only parsing
    const date_part = if (std.mem.indexOf(u8, s, "T")) |t_pos| s[0..t_pos] else s;
    return temporal.Date.parse(date_part) catch null;
}

// ============================================================================
// CQL Aggregate Operations
// ============================================================================

/// Check if a collection contains any item matching a predicate.
pub fn exists(comptime T: type, items: []const T, predicate: *const fn (T) bool) bool {
    for (items) |item_val| {
        if (predicate(item_val)) return true;
    }
    return false;
}

/// Filter a collection by a predicate. Caller owns returned slice.
pub fn filterWhere(allocator: std.mem.Allocator, comptime T: type, items: []const T, predicate: *const fn (T) bool) ![]T {
    var result = std.ArrayList(T).init(allocator);
    for (items) |item_val| {
        if (predicate(item_val)) try result.append(item_val);
    }
    return result.toOwnedSlice();
}

/// Count items matching a predicate.
pub fn countWhere(comptime T: type, items: []const T, predicate: *const fn (T) bool) usize {
    var c: usize = 0;
    for (items) |item_val| {
        if (predicate(item_val)) c += 1;
    }
    return c;
}

/// Get the minimum value from a collection using a key function.
pub fn minBy(comptime T: type, items: []const T, key: *const fn (T) ?f64) ?f64 {
    var min_val: ?f64 = null;
    for (items) |item_val| {
        if (key(item_val)) |v| {
            if (min_val == null or v < min_val.?) min_val = v;
        }
    }
    return min_val;
}

/// Get the maximum value from a collection using a key function.
pub fn maxBy(comptime T: type, items: []const T, key: *const fn (T) ?f64) ?f64 {
    var max_val: ?f64 = null;
    for (items) |item_val| {
        if (key(item_val)) |v| {
            if (max_val == null or v > max_val.?) max_val = v;
        }
    }
    return max_val;
}

/// Get the most recent item by date.
pub fn mostRecent(comptime T: type, items: []const T, date_fn: *const fn (T) ?temporal.Date) ?T {
    var best: ?T = null;
    var best_date: ?temporal.Date = null;
    for (items) |item_val| {
        if (date_fn(item_val)) |d| {
            if (best_date == null or d.after(best_date.?)) {
                best = item_val;
                best_date = d;
            }
        }
    }
    return best;
}
