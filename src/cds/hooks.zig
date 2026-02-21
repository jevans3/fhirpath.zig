const std = @import("std");
const temporal = @import("temporal.zig");
const valueset = @import("valueset.zig");
const measure = @import("measure.zig");
const hedis = @import("hedis.zig");
const cql = @import("cql.zig");

// ============================================================================
// CDS Hooks Specification Implementation
// ============================================================================

/// CDS Hook types per the CDS Hooks specification.
pub const HookType = enum {
    /// Fired when a patient chart is opened.
    patient_view,
    /// Fired when a medication/procedure/etc is being ordered.
    order_select,
    /// Fired when an order is being signed/finalized.
    order_sign,
    /// Fired when an encounter begins.
    encounter_start,
    /// Fired when an encounter is discharged.
    encounter_discharge,

    pub fn name(self: HookType) []const u8 {
        return switch (self) {
            .patient_view => "patient-view",
            .order_select => "order-select",
            .order_sign => "order-sign",
            .encounter_start => "encounter-start",
            .encounter_discharge => "encounter-discharge",
        };
    }
};

/// Card indicator types.
pub const CardIndicator = enum {
    info,
    warning,
    critical,

    pub fn name(self: CardIndicator) []const u8 {
        return switch (self) {
            .info => "info",
            .warning => "warning",
            .critical => "critical",
        };
    }
};

/// A CDS Card returned in a hook response.
pub const Card = struct {
    uuid: []const u8 = "",
    summary: []const u8,
    detail: []const u8 = "",
    indicator: CardIndicator = .info,
    source_label: []const u8 = "HEDIS Quality Engine",
    source_url: []const u8 = "",
    suggestions: []const Suggestion = &[_]Suggestion{},
    links: []const Link = &[_]Link{},
};

/// An action suggestion within a card.
pub const Suggestion = struct {
    label: []const u8,
    uuid: []const u8 = "",
    is_recommended: bool = false,
    actions: []const Action = &[_]Action{},
};

/// An individual action within a suggestion.
pub const Action = struct {
    action_type: ActionType,
    description: []const u8,
    resource_json: []const u8 = "",
};

pub const ActionType = enum {
    create,
    update,
    delete,

    pub fn name(self: ActionType) []const u8 {
        return switch (self) {
            .create => "create",
            .update => "update",
            .delete => "delete",
        };
    }
};

/// A link to external resources.
pub const Link = struct {
    label: []const u8,
    url: []const u8,
    link_type: []const u8 = "absolute",
};

/// CDS Hook request context.
pub const HookRequest = struct {
    hook: HookType,
    hook_instance: []const u8 = "",
    patient_id: []const u8,
    patient_json: []const u8,
    resources: []const measure.ResourceEntry = &[_]measure.ResourceEntry{},
    encounter_json: []const u8 = "",
    /// Draft orders for order-select/order-sign hooks.
    draft_orders: []const []const u8 = &[_][]const u8{},
    /// Current date for measure evaluation.
    today: temporal.Date = temporal.Date{ .year = 2024, .month = 1, .day = 1 },
};

/// CDS Hook response.
pub const HookResponse = struct {
    cards: std.ArrayList(Card),

    pub fn init(allocator: std.mem.Allocator) HookResponse {
        return .{ .cards = std.ArrayList(Card).init(allocator) };
    }

    pub fn deinit(self: *HookResponse) void {
        self.cards.deinit();
    }

    /// Serialize the response to JSON.
    pub fn toJson(self: *const HookResponse, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const w = buf.writer();

        try w.writeAll("{\"cards\": [\n");
        for (self.cards.items, 0..) |card, i| {
            if (i > 0) try w.writeAll(",\n");
            try writeCard(w, card);
        }
        try w.writeAll("\n]}\n");

        return buf.toOwnedSlice();
    }
};

fn writeCard(w: anytype, card: Card) !void {
    try w.writeAll("  {\n");
    try w.print("    \"summary\": \"{s}\",\n", .{card.summary});
    if (card.detail.len > 0) {
        try w.print("    \"detail\": \"{s}\",\n", .{card.detail});
    }
    try w.print("    \"indicator\": \"{s}\",\n", .{card.indicator.name()});
    try w.print("    \"source\": {{\"label\": \"{s}\"", .{card.source_label});
    if (card.source_url.len > 0) {
        try w.print(", \"url\": \"{s}\"", .{card.source_url});
    }
    try w.writeAll("}");

    // Suggestions
    if (card.suggestions.len > 0) {
        try w.writeAll(",\n    \"suggestions\": [\n");
        for (card.suggestions, 0..) |sug, j| {
            if (j > 0) try w.writeAll(",\n");
            try w.writeAll("      {\n");
            try w.print("        \"label\": \"{s}\"", .{sug.label});
            if (sug.is_recommended) {
                try w.writeAll(",\n        \"isRecommended\": true");
            }
            if (sug.actions.len > 0) {
                try w.writeAll(",\n        \"actions\": [\n");
                for (sug.actions, 0..) |act, k| {
                    if (k > 0) try w.writeAll(",\n");
                    try w.print("          {{\"type\": \"{s}\", \"description\": \"{s}\"", .{ act.action_type.name(), act.description });
                    if (act.resource_json.len > 0) {
                        try w.print(", \"resource\": {s}", .{act.resource_json});
                    }
                    try w.writeAll("}");
                }
                try w.writeAll("\n        ]");
            }
            try w.writeAll("\n      }");
        }
        try w.writeAll("\n    ]");
    }

    // Links
    if (card.links.len > 0) {
        try w.writeAll(",\n    \"links\": [\n");
        for (card.links, 0..) |link, j| {
            if (j > 0) try w.writeAll(",\n");
            try w.print("      {{\"label\": \"{s}\", \"url\": \"{s}\", \"type\": \"{s}\"}}", .{ link.label, link.url, link.link_type });
        }
        try w.writeAll("\n    ]");
    }

    try w.writeAll("\n  }");
}

// ============================================================================
// CDS Hook Handlers - Quality Measure Gap Detection
// ============================================================================

/// Process a patient-view hook: check for quality measure gaps.
pub fn handlePatientView(
    allocator: std.mem.Allocator,
    request: *const HookRequest,
    registry: *const valueset.ValueSetRegistry,
) !HookResponse {
    var response = HookResponse.init(allocator);

    const measurement_period = temporal.DateInterval.measurementYear(request.today.year);

    const ctx = measure.PatientContext{
        .patient_json = request.patient_json,
        .resources = request.resources,
        .measurement_period = measurement_period,
        .registry = registry,
    };

    // Evaluate each applicable measure and generate cards for gaps
    for (hedis.ALL_MEASURES) |measure_def| {
        const result = measure_def.evaluate_fn(&ctx);

        // Only generate cards for patients in the denominator who are NOT in the numerator
        if (result.in_denominator and !result.in_denominator_exclusion and !result.in_numerator) {
            const card = buildGapCard(measure_def, &result);
            try response.cards.append(card);
        }
    }

    return response;
}

/// Build a CDS card for a quality measure gap.
fn buildGapCard(
    definition: *const measure.MeasureDefinition,
    result: *const measure.PatientResult,
) Card {
    _ = result;

    return Card{
        .summary = definition.title,
        .detail = definition.clinical_recommendation,
        .indicator = .warning,
        .source_label = "HEDIS Quality Measure Engine",
        .suggestions = &[_]Suggestion{
            .{
                .label = "Order recommended screening",
                .is_recommended = true,
            },
        },
    };
}

/// Process an order-sign hook: check if an order addresses a quality gap.
pub fn handleOrderSign(
    allocator: std.mem.Allocator,
    request: *const HookRequest,
    registry: *const valueset.ValueSetRegistry,
) !HookResponse {
    var response = HookResponse.init(allocator);

    const measurement_period = temporal.DateInterval.measurementYear(request.today.year);

    const ctx = measure.PatientContext{
        .patient_json = request.patient_json,
        .resources = request.resources,
        .measurement_period = measurement_period,
        .registry = registry,
    };

    // Check if any draft order would close a quality gap
    for (request.draft_orders) |draft_order| {
        for (hedis.ALL_MEASURES) |measure_def| {
            const result = measure_def.evaluate_fn(&ctx);
            if (result.in_denominator and !result.in_denominator_exclusion and !result.in_numerator) {
                if (orderAddressesGap(draft_order, measure_def)) {
                    try response.cards.append(Card{
                        .summary = "This order helps close a quality gap",
                        .detail = measure_def.description,
                        .indicator = .info,
                        .source_label = "HEDIS Quality Measure Engine",
                    });
                }
            }
        }
    }

    return response;
}

/// Check if a draft order's codes relate to a measure's numerator criteria.
fn orderAddressesGap(order_json: []const u8, definition: *const measure.MeasureDefinition) bool {
    // Check if the order's code matches any value set associated with the measure
    if (std.mem.eql(u8, definition.id, "BCS")) {
        return cql.codeableConceptInValueSet(order_json, &valueset.VS_MAMMOGRAPHY);
    }
    if (std.mem.eql(u8, definition.id, "CCS")) {
        return cql.codeableConceptInValueSet(order_json, &valueset.VS_CERVICAL_CYTOLOGY) or
            cql.codeableConceptInValueSet(order_json, &valueset.VS_HPV_TEST);
    }
    if (std.mem.eql(u8, definition.id, "CDC-HbA1c-Testing") or
        std.mem.eql(u8, definition.id, "CDC-HbA1c-PoorControl"))
    {
        return cql.codeableConceptInValueSet(order_json, &valueset.VS_HBA1C_LAB_TEST);
    }
    if (std.mem.eql(u8, definition.id, "COL")) {
        return cql.codeableConceptInValueSet(order_json, &valueset.VS_COLONOSCOPY) or
            cql.codeableConceptInValueSet(order_json, &valueset.VS_FOBT) or
            cql.codeableConceptInValueSet(order_json, &valueset.VS_FIT_DNA);
    }
    return false;
}

/// Evaluate all measures and return a comprehensive gap analysis.
pub fn runGapAnalysis(
    allocator: std.mem.Allocator,
    patient_json: []const u8,
    resources: []const measure.ResourceEntry,
    registry: *const valueset.ValueSetRegistry,
    today: temporal.Date,
) !GapAnalysis {
    const measurement_period = temporal.DateInterval.measurementYear(today.year);

    const ctx = measure.PatientContext{
        .patient_json = patient_json,
        .resources = resources,
        .measurement_period = measurement_period,
        .registry = registry,
    };

    var gaps = std.ArrayList(MeasureGap).init(allocator);
    var closed = std.ArrayList(MeasureClosed).init(allocator);

    for (hedis.ALL_MEASURES) |measure_def| {
        const result = measure_def.evaluate_fn(&ctx);
        if (result.in_denominator and !result.in_denominator_exclusion) {
            if (result.in_numerator) {
                try closed.append(.{
                    .measure_id = measure_def.id,
                    .measure_title = measure_def.title,
                });
            } else {
                try gaps.append(.{
                    .measure_id = measure_def.id,
                    .measure_title = measure_def.title,
                    .recommendation = measure_def.clinical_recommendation,
                });
            }
        }
    }

    return .{
        .patient_id = cql.extractJsonString(patient_json, "id") orelse "unknown",
        .measurement_year = today.year,
        .gaps = gaps,
        .closed = closed,
    };
}

pub const MeasureGap = struct {
    measure_id: []const u8,
    measure_title: []const u8,
    recommendation: []const u8,
};

pub const MeasureClosed = struct {
    measure_id: []const u8,
    measure_title: []const u8,
};

pub const GapAnalysis = struct {
    patient_id: []const u8,
    measurement_year: i32,
    gaps: std.ArrayList(MeasureGap),
    closed: std.ArrayList(MeasureClosed),

    pub fn deinit(self: *GapAnalysis) void {
        self.gaps.deinit();
        self.closed.deinit();
    }

    /// Serialize to JSON.
    pub fn toJson(self: *const GapAnalysis, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const w = buf.writer();

        try w.writeAll("{\n");
        try w.print("  \"patientId\": \"{s}\",\n", .{self.patient_id});
        try w.print("  \"measurementYear\": {d},\n", .{self.measurement_year});

        try w.writeAll("  \"openGaps\": [\n");
        for (self.gaps.items, 0..) |gap, i| {
            if (i > 0) try w.writeAll(",\n");
            try w.print("    {{\"measureId\": \"{s}\", \"title\": \"{s}\", \"recommendation\": \"{s}\"}}", .{
                gap.measure_id,
                gap.measure_title,
                gap.recommendation,
            });
        }
        try w.writeAll("\n  ],\n");

        try w.writeAll("  \"closedGaps\": [\n");
        for (self.closed.items, 0..) |cl, i| {
            if (i > 0) try w.writeAll(",\n");
            try w.print("    {{\"measureId\": \"{s}\", \"title\": \"{s}\"}}", .{ cl.measure_id, cl.measure_title });
        }
        try w.writeAll("\n  ]\n");

        try w.writeAll("}\n");

        return buf.toOwnedSlice();
    }
};
