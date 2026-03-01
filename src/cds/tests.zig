const std = @import("std");
const testing = std.testing;

const temporal = @import("temporal.zig");
const valueset = @import("valueset.zig");
const cql = @import("cql.zig");
const measure = @import("measure.zig");
const hedis = @import("hedis.zig");
const hooks = @import("hooks.zig");
const engine = @import("engine.zig");

// ============================================================================
// Test Data: FHIR Resources
// ============================================================================

const PATIENT_FEMALE_55 =
    \\{"resourceType": "Patient", "id": "pt-1", "gender": "female", "birthDate": "1969-03-15"}
;

const PATIENT_FEMALE_35 =
    \\{"resourceType": "Patient", "id": "pt-2", "gender": "female", "birthDate": "1989-06-20"}
;

const PATIENT_MALE_60 =
    \\{"resourceType": "Patient", "id": "pt-3", "gender": "male", "birthDate": "1964-01-10"}
;

const PATIENT_FEMALE_25 =
    \\{"resourceType": "Patient", "id": "pt-4", "gender": "female", "birthDate": "1999-08-05"}
;

const PATIENT_CHILD_1 =
    \\{"resourceType": "Patient", "id": "pt-5", "gender": "male", "birthDate": "2022-06-15"}
;

const PATIENT_DIABETIC_45 =
    \\{"resourceType": "Patient", "id": "pt-6", "gender": "male", "birthDate": "1979-04-22"}
;

const PATIENT_TEEN_15 =
    \\{"resourceType": "Patient", "id": "pt-7", "gender": "female", "birthDate": "2009-02-14"}
;

// -- Conditions --

const CONDITION_HYPERTENSION =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://snomed.info/sct", "code": "59621000", "display": "Essential hypertension"}]}, "clinicalStatus": {"coding": [{"code": "active"}]}}
;

const CONDITION_DIABETES =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://hl7.org/fhir/sid/icd-10-cm", "code": "E11.9", "display": "Type 2 diabetes mellitus"}]}, "clinicalStatus": {"coding": [{"code": "active"}]}}
;

const CONDITION_BILATERAL_MASTECTOMY =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://snomed.info/sct", "code": "428529004", "display": "History of bilateral mastectomy"}]}}
;

const CONDITION_HYSTERECTOMY =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://snomed.info/sct", "code": "428571003", "display": "History of total hysterectomy"}]}}
;

const CONDITION_COLORECTAL_CANCER =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://hl7.org/fhir/sid/icd-10-cm", "code": "C18.9", "display": "Malignant neoplasm of colon"}]}}
;

const CONDITION_PREGNANCY =
    \\{"resourceType": "Condition", "code": {"coding": [{"system": "http://snomed.info/sct", "code": "77386006", "display": "Pregnancy"}]}}
;

// -- Observations --

const OBS_MAMMOGRAM_2024 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "24606-6", "display": "MG Breast Screening"}]}, "effectiveDateTime": "2024-04-15", "status": "final"}
;

const OBS_PAP_SMEAR_2023 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "10524-7", "display": "Cytology cervix"}]}, "effectiveDateTime": "2023-09-10", "status": "final"}
;

const OBS_HPV_TEST_2022 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "21440-3", "display": "HPV DNA cervix probe"}]}, "effectiveDateTime": "2022-03-20", "status": "final"}
;

const OBS_BP_SYSTOLIC_130 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "8480-6", "display": "Systolic blood pressure"}]}, "effectiveDateTime": "2024-06-15", "valueQuantity": {"value": 130, "unit": "mmHg"}, "status": "final"}
;

const OBS_BP_DIASTOLIC_82 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "8462-4", "display": "Diastolic blood pressure"}]}, "effectiveDateTime": "2024-06-15", "valueQuantity": {"value": 82, "unit": "mmHg"}, "status": "final"}
;

const OBS_BP_SYSTOLIC_150 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "8480-6", "display": "Systolic blood pressure"}]}, "effectiveDateTime": "2024-08-20", "valueQuantity": {"value": 150, "unit": "mmHg"}, "status": "final"}
;

const OBS_BP_DIASTOLIC_95 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "8462-4", "display": "Diastolic blood pressure"}]}, "effectiveDateTime": "2024-08-20", "valueQuantity": {"value": 95, "unit": "mmHg"}, "status": "final"}
;

const OBS_HBA1C_7_5 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"}]}, "effectiveDateTime": "2024-05-10", "valueQuantity": {"value": 7.5, "unit": "%"}, "status": "final"}
;

const OBS_HBA1C_10_2 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"}]}, "effectiveDateTime": "2024-07-15", "valueQuantity": {"value": 10.2, "unit": "%"}, "status": "final"}
;

const OBS_EYE_EXAM =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://www.ama-assn.org/go/cpt", "code": "92014", "display": "Ophthalmological services"}]}, "effectiveDateTime": "2024-03-20", "status": "final"}
;

const OBS_UACR =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "14959-1", "display": "Microalbumin/Creatinine in Urine"}]}, "effectiveDateTime": "2024-04-10", "valueQuantity": {"value": 25, "unit": "mg/g"}, "status": "final"}
;

const OBS_FOBT_2024 =
    \\{"resourceType": "Observation", "code": {"coding": [{"system": "http://loinc.org", "code": "27396-1", "display": "Occult blood in Stool"}]}, "effectiveDateTime": "2024-02-15", "status": "final"}
;

// -- Procedures --

const PROC_COLONOSCOPY_2020 =
    \\{"resourceType": "Procedure", "code": {"coding": [{"system": "http://snomed.info/sct", "code": "73761001", "display": "Colonoscopy"}]}, "performedDateTime": "2020-11-15", "status": "completed"}
;

// -- Immunizations --

const IMM_DTAP_1 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "20", "display": "DTaP"}]}, "occurrenceDateTime": "2022-08-15", "status": "completed"}
;

const IMM_DTAP_2 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "20", "display": "DTaP"}]}, "occurrenceDateTime": "2022-10-15", "status": "completed"}
;

const IMM_DTAP_3 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "20", "display": "DTaP"}]}, "occurrenceDateTime": "2022-12-15", "status": "completed"}
;

const IMM_DTAP_4 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "20", "display": "DTaP"}]}, "occurrenceDateTime": "2023-06-15", "status": "completed"}
;

const IMM_IPV_1 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "10", "display": "IPV"}]}, "occurrenceDateTime": "2022-08-15", "status": "completed"}
;

const IMM_IPV_2 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "10", "display": "IPV"}]}, "occurrenceDateTime": "2022-10-15", "status": "completed"}
;

const IMM_IPV_3 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "10", "display": "IPV"}]}, "occurrenceDateTime": "2023-02-15", "status": "completed"}
;

const IMM_MMR =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "03", "display": "MMR"}]}, "occurrenceDateTime": "2023-07-15", "status": "completed"}
;

const IMM_HEPB_1 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "08", "display": "Hep B"}]}, "occurrenceDateTime": "2022-06-15", "status": "completed"}
;

const IMM_HEPB_2 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "08", "display": "Hep B"}]}, "occurrenceDateTime": "2022-07-15", "status": "completed"}
;

const IMM_HEPB_3 =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "08", "display": "Hep B"}]}, "occurrenceDateTime": "2023-01-15", "status": "completed"}
;

const IMM_VZV =
    \\{"resourceType": "Immunization", "vaccineCode": {"coding": [{"system": "http://hl7.org/fhir/sid/cvx", "code": "21", "display": "Varicella"}]}, "occurrenceDateTime": "2023-07-15", "status": "completed"}
;

// -- Encounters --

const ENC_WELL_CHILD =
    \\{"resourceType": "Encounter", "type": [{"coding": [{"system": "http://snomed.info/sct", "code": "410620009", "display": "Well child visit"}]}], "period": {"start": "2024-05-10"}, "status": "finished"}
;

// ============================================================================
// Temporal Tests
// ============================================================================

test "temporal: parse FHIR dates" {
    const d1 = try temporal.Date.parse("2024-01-15");
    try testing.expectEqual(@as(i32, 2024), d1.year);
    try testing.expectEqual(@as(u8, 1), d1.month);
    try testing.expectEqual(@as(u8, 15), d1.day);
    try testing.expectEqual(temporal.DatePrecision.day, d1.precision);

    const d2 = try temporal.Date.parse("2024-06");
    try testing.expectEqual(temporal.DatePrecision.month, d2.precision);

    const d3 = try temporal.Date.parse("2024");
    try testing.expectEqual(temporal.DatePrecision.year, d3.precision);
}

test "temporal: age calculation" {
    const birth = try temporal.Date.parse("1969-03-15");
    const ref = temporal.Date{ .year = 2024, .month = 12, .day = 31 };
    try testing.expectEqual(@as(i32, 55), birth.ageInYears(ref));
}

test "temporal: measurement year interval" {
    const my = temporal.DateInterval.measurementYear(2024);
    try testing.expect(my.containsDate(temporal.Date{ .year = 2024, .month = 6, .day = 15 }));
    try testing.expect(!my.containsDate(temporal.Date{ .year = 2023, .month = 12, .day = 31 }));
    try testing.expect(!my.containsDate(temporal.Date{ .year = 2025, .month = 1, .day = 1 }));
    try testing.expect(my.containsDate(temporal.Date{ .year = 2024, .month = 1, .day = 1 }));
    try testing.expect(my.containsDate(temporal.Date{ .year = 2024, .month = 12, .day = 31 }));
}

test "temporal: date arithmetic" {
    const d = try temporal.Date.parse("2024-01-31");
    const d2 = d.addMonths(1);
    try testing.expectEqual(@as(u8, 2), d2.month);
    try testing.expectEqual(@as(u8, 29), d2.day); // 2024 is leap year

    const d3 = d.addYears(-2);
    try testing.expectEqual(@as(i32, 2022), d3.year);
}

// ============================================================================
// Value Set Tests
// ============================================================================

test "valueset: contains code" {
    try testing.expect(valueset.VS_MAMMOGRAPHY.contains(valueset.Systems.LOINC, "24606-6"));
    try testing.expect(valueset.VS_MAMMOGRAPHY.contains(valueset.Systems.CPT, "77067"));
    try testing.expect(!valueset.VS_MAMMOGRAPHY.contains(valueset.Systems.LOINC, "99999-9"));
}

test "valueset: registry lookup" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const mammo = registry.getByOid("2.16.840.1.113883.3.464.1003.108.11.1047");
    try testing.expect(mammo != null);
    try testing.expect(std.mem.eql(u8, mammo.?.name, "Mammography"));

    try testing.expect(registry.memberOf(
        "2.16.840.1.113883.3.464.1003.108.11.1047",
        valueset.Systems.LOINC,
        "24606-6",
    ));
}

// ============================================================================
// CQL JSON Extraction Tests
// ============================================================================

test "cql: extract json string" {
    const json = PATIENT_FEMALE_55;
    try testing.expect(std.mem.eql(u8, cql.extractJsonString(json, "gender").?, "female"));
    try testing.expect(std.mem.eql(u8, cql.extractJsonString(json, "birthDate").?, "1969-03-15"));
    try testing.expect(std.mem.eql(u8, cql.extractJsonString(json, "id").?, "pt-1"));
}

test "cql: extract json date" {
    const d = cql.extractJsonDate(PATIENT_FEMALE_55, "birthDate").?;
    try testing.expectEqual(@as(i32, 1969), d.year);
    try testing.expectEqual(@as(u8, 3), d.month);
    try testing.expectEqual(@as(u8, 15), d.day);
}

test "cql: extract json number" {
    const json = OBS_BP_SYSTOLIC_130;
    const val = cql.extractJsonNumber(json, "value").?;
    try testing.expect(val > 129.0 and val < 131.0);
}

test "cql: codeable concept in value set" {
    try testing.expect(cql.codeableConceptInValueSet(OBS_MAMMOGRAM_2024, &valueset.VS_MAMMOGRAPHY));
    try testing.expect(!cql.codeableConceptInValueSet(OBS_PAP_SMEAR_2023, &valueset.VS_MAMMOGRAPHY));
    try testing.expect(cql.codeableConceptInValueSet(OBS_PAP_SMEAR_2023, &valueset.VS_CERVICAL_CYTOLOGY));
}

// ============================================================================
// BCS (Breast Cancer Screening) Tests
// ============================================================================

test "BCS: eligible female 55 with mammogram = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_MAMMOGRAM_2024 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.BCS.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(!result.in_denominator_exclusion);
    try testing.expect(result.in_numerator);
}

test "BCS: eligible female 55 without mammogram = gap" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &[_]measure.ResourceEntry{},
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.BCS.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(!result.in_numerator);
}

test "BCS: bilateral mastectomy = exclusion" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_BILATERAL_MASTECTOMY },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.BCS.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(result.in_denominator_exclusion);
}

test "BCS: male patient = not in population" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_MALE_60,
        .resources = &[_]measure.ResourceEntry{},
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.BCS.evaluate_fn(&ctx);
    try testing.expect(!result.in_initial_population);
}

test "BCS: female age 25 = not in population (too young)" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_25,
        .resources = &[_]measure.ResourceEntry{},
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.BCS.evaluate_fn(&ctx);
    try testing.expect(!result.in_initial_population);
}

// ============================================================================
// CCS (Cervical Cancer Screening) Tests
// ============================================================================

test "CCS: female 35 with pap smear within 3 years = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_PAP_SMEAR_2023 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_35,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CCS.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(result.in_numerator);
}

test "CCS: female 35 with HPV test within 5 years = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_HPV_TEST_2022 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_35,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CCS.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

test "CCS: hysterectomy = exclusion" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_HYSTERECTOMY },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_35,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CCS.evaluate_fn(&ctx);
    try testing.expect(result.in_denominator_exclusion);
}

// ============================================================================
// CBP (Controlling High Blood Pressure) Tests
// ============================================================================

test "CBP: controlled BP (130/82) = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_HYPERTENSION },
        .{ .resource_type = "Observation", .json = OBS_BP_SYSTOLIC_130 },
        .{ .resource_type = "Observation", .json = OBS_BP_DIASTOLIC_82 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_MALE_60,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CBP.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(result.in_numerator);
}

test "CBP: uncontrolled BP (150/95) = not in numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_HYPERTENSION },
        .{ .resource_type = "Observation", .json = OBS_BP_SYSTOLIC_150 },
        .{ .resource_type = "Observation", .json = OBS_BP_DIASTOLIC_95 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_MALE_60,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CBP.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_denominator);
    try testing.expect(!result.in_numerator);
}

test "CBP: no hypertension = not in population" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_MALE_60,
        .resources = &[_]measure.ResourceEntry{},
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CBP.evaluate_fn(&ctx);
    try testing.expect(!result.in_initial_population);
}

// ============================================================================
// CDC (Comprehensive Diabetes Care) Tests
// ============================================================================

test "CDC HbA1c Testing: diabetic with test = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
        .{ .resource_type = "Observation", .json = OBS_HBA1C_7_5 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_HBA1C_TESTING.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

test "CDC HbA1c Poor Control: A1c 7.5 = not in numerator (good control)" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
        .{ .resource_type = "Observation", .json = OBS_HBA1C_7_5 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_HBA1C_POOR_CONTROL.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(!result.in_numerator); // A1c 7.5 is NOT poor control
}

test "CDC HbA1c Poor Control: A1c 10.2 = numerator (poor control)" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
        .{ .resource_type = "Observation", .json = OBS_HBA1C_10_2 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_HBA1C_POOR_CONTROL.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator); // A1c 10.2 IS poor control
}

test "CDC HbA1c Poor Control: no test = numerator (missing data = poor control)" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_HBA1C_POOR_CONTROL.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator); // Missing = poor control
}

test "CDC Eye Exam: diabetic with eye exam = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
        .{ .resource_type = "Observation", .json = OBS_EYE_EXAM },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_EYE_EXAM.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

test "CDC Kidney Screening: diabetic with uACR = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_DIABETES },
        .{ .resource_type = "Observation", .json = OBS_UACR },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_DIABETIC_45,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.CDC_KIDNEY_SCREENING.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

// ============================================================================
// COL (Colorectal Cancer Screening) Tests
// ============================================================================

test "COL: FOBT within 1 year = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_FOBT_2024 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.COL.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

test "COL: colonoscopy within 10 years = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Procedure", .json = PROC_COLONOSCOPY_2020 },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.COL.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

test "COL: colorectal cancer = exclusion" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Condition", .json = CONDITION_COLORECTAL_CANCER },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_55,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.COL.evaluate_fn(&ctx);
    try testing.expect(result.in_denominator_exclusion);
}

test "COL: young female 25 = not in population" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_FEMALE_25,
        .resources = &[_]measure.ResourceEntry{},
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.COL.evaluate_fn(&ctx);
    try testing.expect(!result.in_initial_population);
}

// ============================================================================
// WCV (Well-Child Visits) Tests
// ============================================================================

test "WCV: teen with well-child visit = numerator" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Encounter", .json = ENC_WELL_CHILD },
    };

    const ctx = measure.PatientContext{
        .patient_json = PATIENT_TEEN_15,
        .resources = &resources,
        .measurement_period = temporal.DateInterval.measurementYear(2024),
        .registry = &registry,
    };

    const result = hedis.WCV.evaluate_fn(&ctx);
    try testing.expect(result.in_initial_population);
    try testing.expect(result.in_numerator);
}

// ============================================================================
// Measure Scoring Tests
// ============================================================================

test "measure: proportion scoring" {
    var result = measure.MeasureResult.init(testing.allocator, "test", temporal.DateInterval.measurementYear(2024));
    defer result.deinit();

    // Add 10 patients: 8 in denom, 2 excluded, 5 in numerator
    for (0..10) |i| {
        var pr = measure.PatientResult{ .patient_id = "test" };
        pr.in_initial_population = true;
        pr.in_denominator = true;
        if (i < 2) pr.in_denominator_exclusion = true;
        if (i >= 2 and i < 7) pr.in_numerator = true;
        try result.addPatientResult(pr);
    }

    result.calculateScore(.proportion);
    // Score = 5 / (10 - 2) = 5/8 = 0.625
    try testing.expect(result.score != null);
    const score = result.score.?;
    try testing.expect(score > 0.624 and score < 0.626);
}

// ============================================================================
// CDS Hooks Tests
// ============================================================================

test "hooks: gap analysis detects missing mammogram" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    var analysis = try hooks.runGapAnalysis(
        testing.allocator,
        PATIENT_FEMALE_55,
        &[_]measure.ResourceEntry{},
        &registry,
        temporal.Date{ .year = 2024, .month = 12, .day = 31 },
    );
    defer analysis.deinit();

    // Should have BCS as an open gap
    var found_bcs = false;
    for (analysis.gaps.items) |gap| {
        if (std.mem.eql(u8, gap.measure_id, "BCS")) {
            found_bcs = true;
        }
    }
    try testing.expect(found_bcs);
}

test "hooks: mammogram closes BCS gap" {
    var registry = valueset.ValueSetRegistry.init(testing.allocator);
    defer registry.deinit();
    try valueset.registerHedisValueSets(&registry);

    const resources = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_MAMMOGRAM_2024 },
    };

    var analysis = try hooks.runGapAnalysis(
        testing.allocator,
        PATIENT_FEMALE_55,
        &resources,
        &registry,
        temporal.Date{ .year = 2024, .month = 12, .day = 31 },
    );
    defer analysis.deinit();

    // BCS should be closed
    var bcs_closed = false;
    for (analysis.closed.items) |cl| {
        if (std.mem.eql(u8, cl.measure_id, "BCS")) {
            bcs_closed = true;
        }
    }
    try testing.expect(bcs_closed);
}

// ============================================================================
// Engine Integration Tests
// ============================================================================

test "engine: init and list measures" {
    var eng = try engine.Engine.init(testing.allocator);
    defer eng.deinit();

    const ids = engine.Engine.listMeasures();
    try testing.expectEqual(@as(usize, 12), ids.len);
    try testing.expect(std.mem.eql(u8, ids[0], "BCS"));
}

test "engine: evaluate BCS measure" {
    var eng = try engine.Engine.init(testing.allocator);
    defer eng.deinit();
    eng.setDate(temporal.Date{ .year = 2024, .month = 12, .day = 31 });

    const resources_with = [_]measure.ResourceEntry{
        .{ .resource_type = "Observation", .json = OBS_MAMMOGRAM_2024 },
    };
    const resources_without = [_]measure.ResourceEntry{};

    const patients = [_]engine.PatientBundle{
        .{ .patient_json = PATIENT_FEMALE_55, .resources = &resources_with },
        .{ .patient_json = PATIENT_FEMALE_35, .resources = &resources_without }, // Too young for BCS
        .{ .patient_json = PATIENT_MALE_60, .resources = &resources_without }, // Male
    };

    var result = (try eng.evaluateMeasure("BCS", &patients)).?;
    defer result.deinit();

    // Only 1 patient should be in initial population (female 55)
    try testing.expectEqual(@as(u32, 1), result.initial_population_count);
    try testing.expectEqual(@as(u32, 1), result.denominator_count);
    try testing.expectEqual(@as(u32, 1), result.numerator_count);
}

test "engine: gap analysis JSON output" {
    var eng = try engine.Engine.init(testing.allocator);
    defer eng.deinit();
    eng.setDate(temporal.Date{ .year = 2024, .month = 12, .day = 31 });

    var analysis = try eng.gapAnalysis(PATIENT_FEMALE_55, &[_]measure.ResourceEntry{});
    defer analysis.deinit();

    const json = try analysis.toJson(testing.allocator);
    defer testing.allocator.free(json);

    // Verify it's valid-looking JSON
    try testing.expect(json.len > 0);
    try testing.expect(std.mem.indexOf(u8, json, "\"patientId\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"openGaps\"") != null);
}

// ============================================================================
// MeasureReport Generation Tests
// ============================================================================

test "measure report: generates valid FHIR JSON" {
    var result = measure.MeasureResult.init(testing.allocator, "BCS", temporal.DateInterval.measurementYear(2024));
    defer result.deinit();

    for (0..5) |_| {
        var pr = measure.PatientResult{ .patient_id = "test" };
        pr.in_initial_population = true;
        pr.in_denominator = true;
        pr.in_numerator = true;
        try result.addPatientResult(pr);
    }
    result.calculateScore(.proportion);

    const report = try measure.generateMeasureReport(testing.allocator, &result, &hedis.BCS);
    defer testing.allocator.free(report);

    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "\"MeasureReport\"") != null);
    try testing.expect(std.mem.indexOf(u8, report, "\"initial-population\"") != null);
    try testing.expect(std.mem.indexOf(u8, report, "\"numerator\"") != null);
    try testing.expect(std.mem.indexOf(u8, report, "\"measureScore\"") != null);
}

// ============================================================================
// Measure Registry Tests
// ============================================================================

test "hedis: getMeasure by ID" {
    try testing.expect(hedis.getMeasure("BCS") != null);
    try testing.expect(hedis.getMeasure("CCS") != null);
    try testing.expect(hedis.getMeasure("CBP") != null);
    try testing.expect(hedis.getMeasure("CDC-HbA1c-Testing") != null);
    try testing.expect(hedis.getMeasure("CDC-HbA1c-PoorControl") != null);
    try testing.expect(hedis.getMeasure("CDC-Eye-Exam") != null);
    try testing.expect(hedis.getMeasure("CDC-Kidney-Screening") != null);
    try testing.expect(hedis.getMeasure("COL") != null);
    try testing.expect(hedis.getMeasure("WCV") != null);
    try testing.expect(hedis.getMeasure("PPC-Prenatal") != null);
    try testing.expect(hedis.getMeasure("PPC-Postpartum") != null);
    try testing.expect(hedis.getMeasure("CIS") != null);
    try testing.expect(hedis.getMeasure("NONEXISTENT") == null);
}

test "hedis: all measures have required fields" {
    for (hedis.ALL_MEASURES) |m| {
        try testing.expect(m.id.len > 0);
        try testing.expect(m.title.len > 0);
        try testing.expect(m.description.len > 0);
    }
}
