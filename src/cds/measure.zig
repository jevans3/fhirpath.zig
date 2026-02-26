const std = @import("std");
const temporal = @import("temporal.zig");
const valueset = @import("valueset.zig");
const cql = @import("cql.zig");

// ============================================================================
// Quality Measure Framework
// ============================================================================

/// Measure scoring methodology per CQL/FHIR quality reporting.
pub const MeasureScoring = enum {
    /// Numerator / Denominator (most HEDIS measures)
    proportion,
    /// Continuous numeric result (e.g., average HbA1c)
    continuous_variable,
    /// Numerator / Denominator with independent populations
    ratio,
    /// Binary: patient is or isn't in the cohort
    cohort,
};

/// The type of population within a measure.
pub const PopulationType = enum {
    initial_population,
    denominator,
    denominator_exclusion,
    denominator_exception,
    numerator,
    numerator_exclusion,
    measure_population,
    measure_population_exclusion,
    measure_observation,
};

/// Gender criteria for population filtering.
pub const Gender = enum {
    any,
    male,
    female,
};

/// Result of evaluating a single patient against a measure.
pub const PatientResult = struct {
    patient_id: []const u8,
    in_initial_population: bool = false,
    in_denominator: bool = false,
    in_denominator_exclusion: bool = false,
    in_denominator_exception: bool = false,
    in_numerator: bool = false,
    in_numerator_exclusion: bool = false,
    /// For continuous variable measures
    observation_value: ?f64 = null,
    /// Which stratifiers this patient belongs to
    strata: [MAX_STRATA]bool = [_]bool{false} ** MAX_STRATA,
};

const MAX_STRATA = 8;

/// Aggregate results for a measure across all patients.
pub const MeasureResult = struct {
    measure_id: []const u8,
    measurement_period: temporal.DateInterval,
    initial_population_count: u32 = 0,
    denominator_count: u32 = 0,
    denominator_exclusion_count: u32 = 0,
    denominator_exception_count: u32 = 0,
    numerator_count: u32 = 0,
    numerator_exclusion_count: u32 = 0,
    /// For proportion measures: numerator / (denominator - exclusions - exceptions)
    score: ?f64 = null,
    /// Individual patient results
    patient_results: std.ArrayList(PatientResult),
    /// Stratified results
    strata_results: [MAX_STRATA]StrataResult = [_]StrataResult{StrataResult{}} ** MAX_STRATA,
    strata_count: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, measure_id: []const u8, period: temporal.DateInterval) MeasureResult {
        return .{
            .measure_id = measure_id,
            .measurement_period = period,
            .patient_results = std.ArrayList(PatientResult).init(allocator),
        };
    }

    pub fn deinit(self: *MeasureResult) void {
        self.patient_results.deinit();
    }

    /// Add a patient result and update aggregate counts.
    pub fn addPatientResult(self: *MeasureResult, result: PatientResult) !void {
        try self.patient_results.append(result);
        if (result.in_initial_population) self.initial_population_count += 1;
        if (result.in_denominator) self.denominator_count += 1;
        if (result.in_denominator_exclusion) self.denominator_exclusion_count += 1;
        if (result.in_denominator_exception) self.denominator_exception_count += 1;
        if (result.in_numerator) self.numerator_count += 1;
        if (result.in_numerator_exclusion) self.numerator_exclusion_count += 1;

        // Update strata
        for (0..self.strata_count) |i| {
            if (result.strata[i]) {
                if (result.in_initial_population) self.strata_results[i].initial_population_count += 1;
                if (result.in_denominator) self.strata_results[i].denominator_count += 1;
                if (result.in_denominator_exclusion) self.strata_results[i].denominator_exclusion_count += 1;
                if (result.in_numerator) self.strata_results[i].numerator_count += 1;
            }
        }
    }

    /// Calculate the final measure score.
    pub fn calculateScore(self: *MeasureResult, scoring: MeasureScoring) void {
        switch (scoring) {
            .proportion => {
                const effective_denom = self.denominator_count -| self.denominator_exclusion_count -| self.denominator_exception_count;
                if (effective_denom > 0) {
                    self.score = @as(f64, @floatFromInt(self.numerator_count)) / @as(f64, @floatFromInt(effective_denom));
                }
                // Calculate strata scores
                for (0..self.strata_count) |i| {
                    self.strata_results[i].calculateProportionScore();
                }
            },
            .continuous_variable => {
                // Average of observation values
                var sum: f64 = 0;
                var n: u32 = 0;
                for (self.patient_results.items) |pr| {
                    if (pr.observation_value) |v| {
                        sum += v;
                        n += 1;
                    }
                }
                if (n > 0) self.score = sum / @as(f64, @floatFromInt(n));
            },
            .ratio => {
                if (self.denominator_count > 0) {
                    self.score = @as(f64, @floatFromInt(self.numerator_count)) / @as(f64, @floatFromInt(self.denominator_count));
                }
            },
            .cohort => {
                self.score = @as(f64, @floatFromInt(self.initial_population_count));
            },
        }
    }
};

pub const StrataResult = struct {
    initial_population_count: u32 = 0,
    denominator_count: u32 = 0,
    denominator_exclusion_count: u32 = 0,
    numerator_count: u32 = 0,
    score: ?f64 = null,

    pub fn calculateProportionScore(self: *StrataResult) void {
        const effective_denom = self.denominator_count -| self.denominator_exclusion_count;
        if (effective_denom > 0) {
            self.score = @as(f64, @floatFromInt(self.numerator_count)) / @as(f64, @floatFromInt(effective_denom));
        }
    }
};

/// Patient context for measure evaluation.
pub const PatientContext = struct {
    patient_json: []const u8,
    resources: []const ResourceEntry,
    measurement_period: temporal.DateInterval,
    registry: *const valueset.ValueSetRegistry,

    /// Helper: extract birthDate from patient JSON.
    pub fn birthDate(self: *const PatientContext) ?temporal.Date {
        return cql.extractJsonDate(self.patient_json, "birthDate");
    }

    /// Helper: extract gender from patient JSON.
    pub fn gender(self: *const PatientContext) ?[]const u8 {
        return cql.extractJsonString(self.patient_json, "gender");
    }

    /// Helper: calculate age at end of measurement period.
    pub fn ageAtEnd(self: *const PatientContext) ?i32 {
        const bd = self.birthDate() orelse return null;
        return bd.ageInYears(self.measurement_period.end);
    }

    /// Helper: calculate age at start of measurement period.
    pub fn ageAtStart(self: *const PatientContext) ?i32 {
        const bd = self.birthDate() orelse return null;
        return bd.ageInYears(self.measurement_period.start);
    }

    /// Check if patient's gender matches.
    pub fn genderIs(self: *const PatientContext, g: Gender) bool {
        if (g == .any) return true;
        const gen = self.gender() orelse return false;
        return switch (g) {
            .male => std.mem.eql(u8, gen, "male"),
            .female => std.mem.eql(u8, gen, "female"),
            .any => true,
        };
    }

    /// Find resources of a given type.
    pub fn resourcesOfType(self: *const PatientContext, resource_type: []const u8) []const ResourceEntry {
        // This returns the full slice; callers filter by type using the json.
        // In a production system this would be indexed.
        _ = resource_type;
        return self.resources;
    }

    /// Check if any resource matches a resource type and has a code in the value set.
    pub fn hasResourceWithCode(
        self: *const PatientContext,
        resource_type: []const u8,
        code_field: []const u8,
        vs: *const valueset.ValueSet,
    ) bool {
        for (self.resources) |entry| {
            if (!std.mem.eql(u8, entry.resource_type, resource_type)) continue;
            // Check code field
            if (resourceCodeInValueSet(entry.json, code_field, vs)) return true;
        }
        return false;
    }

    /// Check if any resource has a code in value set AND falls within date range.
    pub fn hasResourceWithCodeInPeriod(
        self: *const PatientContext,
        resource_type: []const u8,
        code_field: []const u8,
        vs: *const valueset.ValueSet,
        date_field: []const u8,
        period: temporal.DateInterval,
    ) bool {
        for (self.resources) |entry| {
            if (!std.mem.eql(u8, entry.resource_type, resource_type)) continue;
            if (!resourceCodeInValueSet(entry.json, code_field, vs)) continue;
            // Check date
            const d = cql.extractJsonDate(entry.json, date_field) orelse continue;
            if (period.containsDate(d)) return true;
        }
        return false;
    }

    /// Get the most recent observation value for a code in a value set.
    pub fn mostRecentObservationValue(
        self: *const PatientContext,
        vs: *const valueset.ValueSet,
        period: temporal.DateInterval,
    ) ?f64 {
        var best_date: ?temporal.Date = null;
        var best_value: ?f64 = null;

        for (self.resources) |entry| {
            if (!std.mem.eql(u8, entry.resource_type, "Observation")) continue;
            if (!resourceCodeInValueSet(entry.json, "code", vs)) continue;

            const d = extractObservationDate(entry.json) orelse continue;
            if (!period.containsDate(d)) continue;

            if (best_date == null or d.after(best_date.?)) {
                best_date = d;
                best_value = extractObservationNumericValue(entry.json);
            }
        }
        return best_value;
    }

    /// Count the number of resources matching criteria.
    pub fn countResourcesWithCode(
        self: *const PatientContext,
        resource_type: []const u8,
        code_field: []const u8,
        vs: *const valueset.ValueSet,
        date_field: []const u8,
        period: temporal.DateInterval,
    ) u32 {
        var n: u32 = 0;
        for (self.resources) |entry| {
            if (!std.mem.eql(u8, entry.resource_type, resource_type)) continue;
            if (!resourceCodeInValueSet(entry.json, code_field, vs)) continue;
            const d = cql.extractJsonDate(entry.json, date_field) orelse continue;
            if (period.containsDate(d)) n += 1;
        }
        return n;
    }
};

/// A FHIR resource entry with its type pre-extracted for efficient filtering.
pub const ResourceEntry = struct {
    resource_type: []const u8,
    json: []const u8,
};

/// Check if a resource's code field contains a code in the value set.
fn resourceCodeInValueSet(json: []const u8, code_field: []const u8, vs: *const valueset.ValueSet) bool {
    // For simple code fields, try direct extraction
    if (std.mem.eql(u8, code_field, "code") or
        std.mem.eql(u8, code_field, "vaccineCode") or
        std.mem.eql(u8, code_field, "medicationCodeableConcept"))
    {
        return cql.codeableConceptInValueSet(json, vs);
    }
    // Generic: look for the code field and check codings within it
    return cql.codeableConceptInValueSet(json, vs);
}

/// Extract a date from an Observation resource (handles effectiveDateTime, issued).
fn extractObservationDate(json: []const u8) ?temporal.Date {
    if (cql.extractJsonDate(json, "effectiveDateTime")) |d| return d;
    if (cql.extractJsonDate(json, "issued")) |d| return d;
    return null;
}

/// Extract a numeric value from an Observation (handles valueQuantity.value, valueInteger).
fn extractObservationNumericValue(json: []const u8) ?f64 {
    if (cql.extractJsonNumber(json, "value")) |v| return v;
    if (cql.extractJsonNumber(json, "valueInteger")) |v| return v;
    return null;
}

// ============================================================================
// Measure Definition Interface
// ============================================================================

/// A measure definition that can be evaluated against patient data.
pub const MeasureDefinition = struct {
    id: []const u8,
    title: []const u8,
    description: []const u8 = "",
    scoring: MeasureScoring = .proportion,
    /// Evaluate this measure for a single patient.
    evaluate_fn: *const fn (ctx: *const PatientContext) PatientResult,
    /// Optional: number of stratifiers this measure defines.
    strata_count: u8 = 0,
    /// Measure metadata
    version: []const u8 = "2024",
    clinical_recommendation: []const u8 = "",
};

/// Evaluate a measure definition across a set of patients.
pub fn evaluateMeasure(
    allocator: std.mem.Allocator,
    definition: *const MeasureDefinition,
    patients: []const PatientContext,
    period: temporal.DateInterval,
) !MeasureResult {
    var result = MeasureResult.init(allocator, definition.id, period);
    result.strata_count = definition.strata_count;

    for (patients) |*patient| {
        const pr = definition.evaluate_fn(patient);
        try result.addPatientResult(pr);
    }

    result.calculateScore(definition.scoring);
    return result;
}

// ============================================================================
// MeasureReport FHIR Resource Generation
// ============================================================================

/// Generate a FHIR MeasureReport JSON string from measure results.
pub fn generateMeasureReport(
    allocator: std.mem.Allocator,
    result: *const MeasureResult,
    definition: *const MeasureDefinition,
) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();

    try w.writeAll("{\n");
    try w.writeAll("  \"resourceType\": \"MeasureReport\",\n");
    try w.print("  \"status\": \"complete\",\n", .{});
    try w.print("  \"type\": \"summary\",\n", .{});
    const measure_ref = try std.fmt.allocPrint(allocator, "Measure/{s}", .{definition.id});
    defer allocator.free(measure_ref);
    try w.writeAll("  \"measure\": ");
    try std.json.stringify(measure_ref, .{}, w);
    try w.writeAll(",\n");

    // Period
    var start_buf: [16]u8 = undefined;
    var end_buf: [16]u8 = undefined;
    const start_str = result.measurement_period.start.formatDate(&start_buf) catch "unknown";
    const end_str = result.measurement_period.end.formatDate(&end_buf) catch "unknown";
    try w.print("  \"period\": {{\n    \"start\": \"{s}\",\n    \"end\": \"{s}\"\n  }},\n", .{ start_str, end_str });

    // Date generated (use measurement period end)
    try w.print("  \"date\": \"{s}\",\n", .{end_str});

    // Groups
    try w.writeAll("  \"group\": [{\n");
    try w.writeAll("    \"code\": {\"text\": ");
    try std.json.stringify(definition.title, .{}, w);
    try w.writeAll("},\n");

    // Populations
    try w.writeAll("    \"population\": [\n");
    try writePopulation(w, "initial-population", result.initial_population_count);
    try w.writeAll(",\n");
    try writePopulation(w, "denominator", result.denominator_count);
    try w.writeAll(",\n");
    try writePopulation(w, "denominator-exclusion", result.denominator_exclusion_count);
    try w.writeAll(",\n");
    try writePopulation(w, "denominator-exception", result.denominator_exception_count);
    try w.writeAll(",\n");
    try writePopulation(w, "numerator", result.numerator_count);
    try w.writeAll("\n    ]");

    // Score
    if (result.score) |score| {
        try w.print(",\n    \"measureScore\": {{\"value\": {d:.4}}}", .{score});
    }

    // Stratifiers
    if (result.strata_count > 0) {
        try w.writeAll(",\n    \"stratifier\": [\n");
        for (0..result.strata_count) |i| {
            if (i > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.print("        \"code\": [{{\"text\": \"stratum-{d}\"}}],\n", .{i + 1});
            try w.writeAll("        \"stratum\": [{\n");
            try w.writeAll("          \"population\": [\n");
            try w.writeAll("            ");
            try writePopulationCompact(w, "initial-population", result.strata_results[i].initial_population_count);
            try w.writeAll(",\n            ");
            try writePopulationCompact(w, "denominator", result.strata_results[i].denominator_count);
            try w.writeAll(",\n            ");
            try writePopulationCompact(w, "numerator", result.strata_results[i].numerator_count);
            try w.writeAll("\n          ]");
            if (result.strata_results[i].score) |s| {
                try w.print(",\n          \"measureScore\": {{\"value\": {d:.4}}}", .{s});
            }
            try w.writeAll("\n        }]\n      }");
        }
        try w.writeAll("\n    ]");
    }

    try w.writeAll("\n  }]\n");
    try w.writeAll("}\n");

    return buf.toOwnedSlice();
}

fn writePopulation(w: anytype, code: []const u8, n: u32) !void {
    try w.print("      {{\"code\": {{\"coding\": [{{\"system\": \"http://terminology.hl7.org/CodeSystem/measure-population\", \"code\": \"{s}\"}}]}}, \"count\": {d}}}", .{ code, n });
}

fn writePopulationCompact(w: anytype, code: []const u8, n: u32) !void {
    try w.print("{{\"code\": {{\"coding\": [{{\"code\": \"{s}\"}}]}}, \"count\": {d}}}", .{ code, n });
}
