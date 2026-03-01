const std = @import("std");

pub const temporal = @import("temporal.zig");
pub const valueset = @import("valueset.zig");
pub const cql = @import("cql.zig");
pub const measure = @import("measure.zig");
pub const hedis = @import("hedis.zig");
pub const hooks = @import("hooks.zig");

// ============================================================================
// CDS/HEDIS Engine - Top-level API
// ============================================================================

/// The main CDS/HEDIS quality measure engine.
/// Wraps all subsystems and provides a unified interface.
pub const Engine = struct {
    allocator: std.mem.Allocator,
    registry: valueset.ValueSetRegistry,
    today: temporal.Date,

    pub fn init(allocator: std.mem.Allocator) !Engine {
        var registry = valueset.ValueSetRegistry.init(allocator);
        try valueset.registerHedisValueSets(&registry);
        return .{
            .allocator = allocator,
            .registry = registry,
            .today = temporal.Date{ .year = 2024, .month = 12, .day = 31 },
        };
    }

    pub fn deinit(self: *Engine) void {
        self.registry.deinit();
    }

    /// Set the current date for measure evaluation.
    pub fn setDate(self: *Engine, today: temporal.Date) void {
        self.today = today;
    }

    /// Evaluate a single measure for a set of patients.
    pub fn evaluateMeasure(
        self: *Engine,
        measure_id: []const u8,
        patients: []const PatientBundle,
    ) !?measure.MeasureResult {
        const definition = hedis.getMeasure(measure_id) orelse return null;
        const period = temporal.DateInterval.measurementYear(self.today.year);

        var contexts = std.ArrayList(measure.PatientContext).init(self.allocator);
        defer contexts.deinit();

        for (patients) |pb| {
            try contexts.append(.{
                .patient_json = pb.patient_json,
                .resources = pb.resources,
                .measurement_period = period,
                .registry = &self.registry,
            });
        }

        return measure.evaluateMeasure(
            self.allocator,
            definition,
            contexts.items,
            period,
        );
    }

    /// Evaluate all HEDIS measures for a set of patients.
    pub fn evaluateAllMeasures(
        self: *Engine,
        patients: []const PatientBundle,
    ) ![hedis.ALL_MEASURES.len]?measure.MeasureResult {
        var results: [hedis.ALL_MEASURES.len]?measure.MeasureResult = undefined;
        for (hedis.ALL_MEASURES, 0..) |m, i| {
            results[i] = try self.evaluateMeasure(m.id, patients);
        }
        return results;
    }

    /// Run gap analysis for a single patient.
    pub fn gapAnalysis(
        self: *Engine,
        patient_json: []const u8,
        resources: []const measure.ResourceEntry,
    ) !hooks.GapAnalysis {
        return hooks.runGapAnalysis(
            self.allocator,
            patient_json,
            resources,
            &self.registry,
            self.today,
        );
    }

    /// Handle a CDS Hook request.
    pub fn handleHook(
        self: *Engine,
        request: *const hooks.HookRequest,
    ) !hooks.HookResponse {
        return switch (request.hook) {
            .patient_view => hooks.handlePatientView(self.allocator, request, &self.registry),
            .order_sign => hooks.handleOrderSign(self.allocator, request, &self.registry),
            else => hooks.HookResponse.init(self.allocator), // Other hooks return empty
        };
    }

    pub const ReportError = error{MeasureNotFound} || std.mem.Allocator.Error;

    /// Generate a FHIR MeasureReport for a given measure result.
    pub fn generateReport(
        self: *Engine,
        result: *const measure.MeasureResult,
        measure_id: []const u8,
    ) ReportError![]u8 {
        const definition = hedis.getMeasure(measure_id) orelse return error.MeasureNotFound;
        return measure.generateMeasureReport(self.allocator, result, definition);
    }

    /// List all available measure IDs.
    pub fn listMeasures() [hedis.ALL_MEASURES.len][]const u8 {
        return hedis.listMeasureIds();
    }
};

/// A bundle of patient data ready for measure evaluation.
pub const PatientBundle = struct {
    patient_json: []const u8,
    resources: []const measure.ResourceEntry,
};

/// Convenience: parse a FHIR Bundle JSON and extract patient + resources.
/// This is a lightweight JSON extraction that avoids full parsing.
pub fn parseBundleEntries(
    allocator: std.mem.Allocator,
    bundle_json: []const u8,
) !BundleParsed {
    var patient_json: []const u8 = "{}";
    var resources = std.ArrayList(measure.ResourceEntry).init(allocator);

    // Find "entry" array and extract resources
    // Simple approach: find each "resourceType" and extract the enclosing object
    var pos: usize = 0;
    while (pos < bundle_json.len) {
        const rt_pos = std.mem.indexOf(u8, bundle_json[pos..], "\"resourceType\"") orelse break;
        const abs_pos = pos + rt_pos;

        // Extract resourceType value
        const rt_value = cql.extractJsonString(bundle_json[abs_pos..], "resourceType") orelse {
            pos = abs_pos + 14;
            continue;
        };

        // Find the enclosing object boundaries
        const obj_start = findObjectStart(bundle_json, abs_pos);
        const obj_end = findObjectEnd(bundle_json, abs_pos);

        if (obj_start != null and obj_end != null) {
            const resource_json = bundle_json[obj_start.?..obj_end.?];

            if (std.mem.eql(u8, rt_value, "Patient")) {
                patient_json = resource_json;
            }

            try resources.append(.{
                .resource_type = rt_value,
                .json = resource_json,
            });
        }

        pos = abs_pos + 14;
    }

    return .{
        .patient_json = patient_json,
        .resources = try resources.toOwnedSlice(),
    };
}

pub const BundleParsed = struct {
    patient_json: []const u8,
    resources: []const measure.ResourceEntry,
};

fn findObjectStart(json: []const u8, pos: usize) ?usize {
    var i: usize = pos;
    while (i > 0) : (i -= 1) {
        if (json[i] == '{') {
            // Check nesting depth
            var depth: i32 = 0;
            var j = i;
            while (j <= pos) : (j += 1) {
                if (json[j] == '{') depth += 1;
                if (json[j] == '}') depth -= 1;
            }
            if (depth > 0) return i;
        }
    }
    return null;
}

fn findObjectEnd(json: []const u8, pos: usize) ?usize {
    var depth: i32 = 0;
    var i = pos;
    // Go back to find our opening brace
    while (i > 0) : (i -= 1) {
        if (json[i] == '{') {
            var check_depth: i32 = 0;
            var j = i;
            while (j <= pos) : (j += 1) {
                if (json[j] == '{') check_depth += 1;
                if (json[j] == '}') check_depth -= 1;
            }
            if (check_depth > 0) break;
        }
    }

    // Now scan forward to find the matching close brace
    depth = 0;
    var j = i;
    var in_string = false;
    while (j < json.len) : (j += 1) {
        if (json[j] == '\\' and in_string) {
            j += 1;
            continue;
        }
        if (json[j] == '"') in_string = !in_string;
        if (!in_string) {
            if (json[j] == '{') depth += 1;
            if (json[j] == '}') {
                depth -= 1;
                if (depth == 0) return j + 1;
            }
        }
    }
    return null;
}
