const std = @import("std");
const temporal = @import("temporal.zig");
const valueset = @import("valueset.zig");
const measure = @import("measure.zig");
const cql = @import("cql.zig");

// ============================================================================
// HEDIS Measure Definitions
// ============================================================================

/// Breast Cancer Screening (BCS)
/// Women 50-74 who had a mammogram in the measurement period or year prior.
pub const BCS = measure.MeasureDefinition{
    .id = "BCS",
    .title = "Breast Cancer Screening",
    .description = "Percentage of women 50-74 years of age who had a mammogram to screen for breast cancer.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateBCS,
    .strata_count = 2,
    .version = "2024",
    .clinical_recommendation = "USPSTF recommends biennial screening mammography for women aged 50-74 years.",
};

fn evaluateBCS(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    // Initial Population: Women 50-74 at end of measurement period
    const age = ctx.ageAtEnd() orelse return result;
    if (!ctx.genderIs(.female)) return result;
    if (age < 50 or age > 74) return result;
    result.in_initial_population = true;

    // Denominator: Same as initial population
    result.in_denominator = true;

    // Denominator Exclusion: Bilateral mastectomy or two unilateral mastectomies
    if (ctx.hasResourceWithCode("Condition", "code", &valueset.VS_BILATERAL_MASTECTOMY) or
        ctx.hasResourceWithCode("Procedure", "code", &valueset.VS_BILATERAL_MASTECTOMY))
    {
        result.in_denominator_exclusion = true;
        return result;
    }

    // Check for two unilateral mastectomies (different sides)
    if (hasHistoryTwoUnilateralMastectomies(ctx)) {
        result.in_denominator_exclusion = true;
        return result;
    }

    // Numerator: Mammogram during measurement period or 15 months prior to end
    const lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addMonths(-27), // 27 months lookback for biennial
        .end = ctx.measurement_period.end,
    };

    if (ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_MAMMOGRAPHY, "effectiveDateTime", lookback) or
        ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_MAMMOGRAPHY, "effectiveDateTime", lookback) or
        ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_MAMMOGRAPHY, "performedDateTime", lookback))
    {
        result.in_numerator = true;
    }

    // Strata: Age groups 50-64, 65-74
    result.strata[0] = age >= 50 and age <= 64;
    result.strata[1] = age >= 65 and age <= 74;

    return result;
}

fn hasHistoryTwoUnilateralMastectomies(ctx: *const measure.PatientContext) bool {
    var has_left = false;
    var has_right = false;

    for (ctx.resources) |entry| {
        if (!std.mem.eql(u8, entry.resource_type, "Condition") and
            !std.mem.eql(u8, entry.resource_type, "Procedure")) continue;

        if (!cql.codeableConceptInValueSet(entry.json, &valueset.VS_UNILATERAL_MASTECTOMY)) {
            continue;
        }

        // Heuristic laterality detection: look for "left"/"right" markers in the JSON.
        const json_bytes = entry.json;

        if (std.mem.indexOf(u8, json_bytes, "left") != null or
            std.mem.indexOf(u8, json_bytes, "Left") != null)
        {
            has_left = true;
        }

        if (std.mem.indexOf(u8, json_bytes, "right") != null or
            std.mem.indexOf(u8, json_bytes, "Right") != null)
        {
            has_right = true;
        }

        if (has_left and has_right) {
            return true;
        }
    }

    return has_left and has_right;
}

/// Cervical Cancer Screening (CCS)
/// Women 21-64 with cervical cytology (3yr) or HPV test (5yr, age 30+).
pub const CCS = measure.MeasureDefinition{
    .id = "CCS",
    .title = "Cervical Cancer Screening",
    .description = "Percentage of women 21-64 years of age who were screened for cervical cancer.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCCS,
    .strata_count = 2,
    .version = "2024",
    .clinical_recommendation = "USPSTF recommends cervical cytology every 3 years for women aged 21-65, or HPV testing every 5 years for women 30-65.",
};

fn evaluateCCS(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (!ctx.genderIs(.female)) return result;
    if (age < 21 or age > 64) return result;
    result.in_initial_population = true;
    result.in_denominator = true;

    // Denominator Exclusion: Hysterectomy with no residual cervix
    if (ctx.hasResourceWithCode("Procedure", "code", &valueset.VS_HYSTERECTOMY) or
        ctx.hasResourceWithCode("Condition", "code", &valueset.VS_HYSTERECTOMY))
    {
        result.in_denominator_exclusion = true;
        return result;
    }

    // Numerator: Cervical cytology within 3 years OR (age 30+) HPV test within 5 years
    const cytology_lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addYears(-3),
        .end = ctx.measurement_period.end,
    };

    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_CERVICAL_CYTOLOGY, "effectiveDateTime", cytology_lookback) or
        ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_CERVICAL_CYTOLOGY, "effectiveDateTime", cytology_lookback))
    {
        result.in_numerator = true;
    }

    if (!result.in_numerator and age >= 30) {
        const hpv_lookback = temporal.DateInterval{
            .start = ctx.measurement_period.end.addYears(-5),
            .end = ctx.measurement_period.end,
        };
        if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_HPV_TEST, "effectiveDateTime", hpv_lookback) or
            ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_HPV_TEST, "effectiveDateTime", hpv_lookback))
        {
            result.in_numerator = true;
        }
    }

    // Strata: 21-29 (cytology only), 30-64 (cytology or HPV)
    result.strata[0] = age >= 21 and age <= 29;
    result.strata[1] = age >= 30 and age <= 64;

    return result;
}

/// Controlling High Blood Pressure (CBP)
/// Adults 18-85 with hypertension diagnosis and adequate BP control.
pub const CBP = measure.MeasureDefinition{
    .id = "CBP",
    .title = "Controlling High Blood Pressure",
    .description = "Percentage of patients 18-85 with a diagnosis of hypertension whose blood pressure was adequately controlled (<140/90).",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCBP,
    .strata_count = 2,
    .version = "2024",
    .clinical_recommendation = "JNC 8 recommends BP target <140/90 mmHg for most adults with hypertension.",
};

fn evaluateCBP(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 18 or age > 85) return result;

    // Must have hypertension diagnosis
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_ESSENTIAL_HYPERTENSION)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: Most recent BP reading in measurement period has systolic < 140 AND diastolic < 90
    const systolic = ctx.mostRecentObservationValue(&valueset.VS_BP_SYSTOLIC, ctx.measurement_period);
    const diastolic = ctx.mostRecentObservationValue(&valueset.VS_BP_DIASTOLIC, ctx.measurement_period);

    if (systolic != null and diastolic != null) {
        if (systolic.? < 140.0 and diastolic.? < 90.0) {
            result.in_numerator = true;
        }
    }

    // Strata: 18-59, 60-85
    result.strata[0] = age >= 18 and age <= 59;
    result.strata[1] = age >= 60 and age <= 85;

    return result;
}

/// Comprehensive Diabetes Care - HbA1c Testing (CDC-HbA1c)
/// Diabetic patients 18-75 who had an HbA1c test during measurement period.
pub const CDC_HBA1C_TESTING = measure.MeasureDefinition{
    .id = "CDC-HbA1c-Testing",
    .title = "Comprehensive Diabetes Care: HbA1c Testing",
    .description = "Percentage of patients 18-75 with diabetes who had an HbA1c test during the measurement period.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCDC_HbA1cTesting,
    .version = "2024",
    .clinical_recommendation = "ADA recommends HbA1c testing at least twice a year for patients with diabetes.",
};

fn evaluateCDC_HbA1cTesting(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 18 or age > 75) return result;
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_DIABETES)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: HbA1c lab test during measurement period
    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_HBA1C_LAB_TEST, "effectiveDateTime", ctx.measurement_period)) {
        result.in_numerator = true;
    }

    return result;
}

/// Comprehensive Diabetes Care - HbA1c Poor Control >9% (CDC-HbA1c-Control)
/// Diabetic patients 18-75 whose most recent HbA1c > 9%.
/// NOTE: This is an INVERSE measure - lower is better (higher = more patients with poor control).
pub const CDC_HBA1C_POOR_CONTROL = measure.MeasureDefinition{
    .id = "CDC-HbA1c-PoorControl",
    .title = "Comprehensive Diabetes Care: HbA1c Poor Control (>9%)",
    .description = "Percentage of patients 18-75 with diabetes whose most recent HbA1c was greater than 9.0%.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCDC_HbA1cPoorControl,
    .version = "2024",
    .clinical_recommendation = "ADA recommends an HbA1c target of <7% for most adults. HbA1c >9% indicates poor glycemic control.",
};

fn evaluateCDC_HbA1cPoorControl(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 18 or age > 75) return result;
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_DIABETES)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: Most recent HbA1c > 9.0% OR no HbA1c test (treat missing as poor control)
    const hba1c = ctx.mostRecentObservationValue(&valueset.VS_HBA1C_LAB_TEST, ctx.measurement_period);
    if (hba1c) |value| {
        if (value > 9.0) {
            result.in_numerator = true;
        }
        result.observation_value = value;
    } else {
        // No test = numerator (considered poor control for this inverse measure)
        result.in_numerator = true;
    }

    return result;
}

/// Comprehensive Diabetes Care - Eye Exam (CDC-Eye)
/// Diabetic patients 18-75 who had a retinal eye exam.
pub const CDC_EYE_EXAM = measure.MeasureDefinition{
    .id = "CDC-Eye-Exam",
    .title = "Comprehensive Diabetes Care: Eye Exam",
    .description = "Percentage of patients 18-75 with diabetes who had a retinal or dilated eye exam.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCDC_EyeExam,
    .version = "2024",
    .clinical_recommendation = "ADA recommends an initial dilated comprehensive eye exam within 5 years of diabetes diagnosis and annually thereafter.",
};

fn evaluateCDC_EyeExam(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 18 or age > 75) return result;
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_DIABETES)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: Retinal eye exam during measurement period or year prior
    const lookback = temporal.DateInterval{
        .start = ctx.measurement_period.start.addYears(-1),
        .end = ctx.measurement_period.end,
    };

    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_DIABETIC_RETINAL_SCREENING, "effectiveDateTime", lookback) or
        ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_DIABETIC_RETINAL_SCREENING, "performedDateTime", lookback) or
        ctx.hasResourceWithCodeInPeriod("Encounter", "type", &valueset.VS_DIABETIC_RETINAL_SCREENING, "period.start", lookback))
    {
        result.in_numerator = true;
    }

    return result;
}

/// Comprehensive Diabetes Care - Kidney Screening (CDC-Kidney)
/// Diabetic patients 18-75 who had a urine albumin-creatinine ratio test.
pub const CDC_KIDNEY_SCREENING = measure.MeasureDefinition{
    .id = "CDC-Kidney-Screening",
    .title = "Comprehensive Diabetes Care: Kidney Health Evaluation",
    .description = "Percentage of patients 18-75 with diabetes who had a kidney health evaluation (uACR test).",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCDC_KidneyScreening,
    .version = "2024",
    .clinical_recommendation = "ADA recommends annual urine albumin-creatinine ratio testing for all patients with type 2 diabetes.",
};

fn evaluateCDC_KidneyScreening(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 18 or age > 75) return result;
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_DIABETES)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: uACR test during measurement period
    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_URINE_ALBUMIN_CREATININE_RATIO, "effectiveDateTime", ctx.measurement_period)) {
        result.in_numerator = true;
    }

    return result;
}

/// Colorectal Cancer Screening (COL)
/// Adults 45-75 with appropriate screening.
pub const COL = measure.MeasureDefinition{
    .id = "COL",
    .title = "Colorectal Cancer Screening",
    .description = "Percentage of adults 45-75 who had appropriate screening for colorectal cancer.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCOL,
    .strata_count = 2,
    .version = "2024",
    .clinical_recommendation = "USPSTF recommends screening for colorectal cancer in adults aged 45-75.",
};

fn evaluateCOL(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 45 or age > 75) return result;
    result.in_initial_population = true;
    result.in_denominator = true;

    // Denominator Exclusion: Colorectal cancer diagnosis or total colectomy
    if (ctx.hasResourceWithCode("Condition", "code", &valueset.VS_COLORECTAL_CANCER) or
        ctx.hasResourceWithCode("Procedure", "code", &valueset.VS_TOTAL_COLECTOMY) or
        ctx.hasResourceWithCode("Condition", "code", &valueset.VS_TOTAL_COLECTOMY))
    {
        result.in_denominator_exclusion = true;
        return result;
    }

    // Numerator: Any of the following screening tests within appropriate lookback:
    // 1. FOBT within 1 year
    const fobt_lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addYears(-1),
        .end = ctx.measurement_period.end,
    };
    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_FOBT, "effectiveDateTime", fobt_lookback) or
        ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_FOBT, "effectiveDateTime", fobt_lookback))
    {
        result.in_numerator = true;
        result.strata[0] = age >= 45 and age <= 64;
        result.strata[1] = age >= 65 and age <= 75;
        return result;
    }

    // 2. FIT-DNA within 3 years
    const fit_dna_lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addYears(-3),
        .end = ctx.measurement_period.end,
    };
    if (ctx.hasResourceWithCodeInPeriod("Observation", "code", &valueset.VS_FIT_DNA, "effectiveDateTime", fit_dna_lookback) or
        ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_FIT_DNA, "effectiveDateTime", fit_dna_lookback))
    {
        result.in_numerator = true;
        result.strata[0] = age >= 45 and age <= 64;
        result.strata[1] = age >= 65 and age <= 75;
        return result;
    }

    // 3. Flexible sigmoidoscopy within 5 years
    const sig_lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addYears(-5),
        .end = ctx.measurement_period.end,
    };
    if (ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_FLEXIBLE_SIGMOIDOSCOPY, "performedDateTime", sig_lookback)) {
        result.in_numerator = true;
        result.strata[0] = age >= 45 and age <= 64;
        result.strata[1] = age >= 65 and age <= 75;
        return result;
    }

    // 4. CT Colonography within 5 years
    if (ctx.hasResourceWithCodeInPeriod("DiagnosticReport", "code", &valueset.VS_CT_COLONOGRAPHY, "effectiveDateTime", sig_lookback)) {
        result.in_numerator = true;
        result.strata[0] = age >= 45 and age <= 64;
        result.strata[1] = age >= 65 and age <= 75;
        return result;
    }

    // 5. Colonoscopy within 10 years
    const colonoscopy_lookback = temporal.DateInterval{
        .start = ctx.measurement_period.end.addYears(-10),
        .end = ctx.measurement_period.end,
    };
    if (ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_COLONOSCOPY, "performedDateTime", colonoscopy_lookback)) {
        result.in_numerator = true;
    }

    result.strata[0] = age >= 45 and age <= 64;
    result.strata[1] = age >= 65 and age <= 75;

    return result;
}

/// Well-Child Visits in the First 30 Months of Life (W30)
pub const WCV = measure.MeasureDefinition{
    .id = "WCV",
    .title = "Child and Adolescent Well-Care Visits",
    .description = "Percentage of members 3-21 years who had at least one well-care visit during the measurement period.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateWCV,
    .strata_count = 3,
    .version = "2024",
    .clinical_recommendation = "AAP recommends annual well-child visits for children and adolescents.",
};

fn evaluateWCV(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    const age = ctx.ageAtEnd() orelse return result;
    if (age < 3 or age > 21) return result;
    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: At least one well-child/well-care visit during measurement period
    if (ctx.hasResourceWithCodeInPeriod("Encounter", "type", &valueset.VS_WELL_CHILD_VISIT, "period.start", ctx.measurement_period) or
        ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_WELL_CHILD_VISIT, "performedDateTime", ctx.measurement_period))
    {
        result.in_numerator = true;
    }

    // Strata: 3-11, 12-17, 18-21
    result.strata[0] = age >= 3 and age <= 11;
    result.strata[1] = age >= 12 and age <= 17;
    result.strata[2] = age >= 18 and age <= 21;

    return result;
}

/// Prenatal and Postpartum Care (PPC) - Timeliness of Prenatal Care
pub const PPC_PRENATAL = measure.MeasureDefinition{
    .id = "PPC-Prenatal",
    .title = "Prenatal and Postpartum Care: Timeliness of Prenatal Care",
    .description = "Percentage of deliveries in which women had a prenatal care visit in the first trimester.",
    .scoring = .proportion,
    .evaluate_fn = &evaluatePPC_Prenatal,
    .version = "2024",
    .clinical_recommendation = "ACOG recommends initiating prenatal care in the first trimester.",
};

fn evaluatePPC_Prenatal(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    // Check for pregnancy/delivery in measurement period
    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_PREGNANCY)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: Prenatal visit in first trimester (within 280 days before delivery - first 84 days)
    // Simplified: check for prenatal visit during measurement period
    if (ctx.hasResourceWithCodeInPeriod("Encounter", "type", &valueset.VS_PRENATAL_VISIT, "period.start", ctx.measurement_period) or
        ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_PRENATAL_VISIT, "performedDateTime", ctx.measurement_period))
    {
        result.in_numerator = true;
    }

    return result;
}

/// Prenatal and Postpartum Care (PPC) - Postpartum Care
pub const PPC_POSTPARTUM = measure.MeasureDefinition{
    .id = "PPC-Postpartum",
    .title = "Prenatal and Postpartum Care: Postpartum Care",
    .description = "Percentage of deliveries in which women had a postpartum visit within 7-84 days after delivery.",
    .scoring = .proportion,
    .evaluate_fn = &evaluatePPC_Postpartum,
    .version = "2024",
    .clinical_recommendation = "ACOG recommends postpartum care within 3-12 weeks of delivery.",
};

fn evaluatePPC_Postpartum(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    if (!ctx.hasResourceWithCode("Condition", "code", &valueset.VS_PREGNANCY)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: Postpartum visit within 7-84 days after delivery
    if (ctx.hasResourceWithCodeInPeriod("Encounter", "type", &valueset.VS_POSTPARTUM_VISIT, "period.start", ctx.measurement_period) or
        ctx.hasResourceWithCodeInPeriod("Procedure", "code", &valueset.VS_POSTPARTUM_VISIT, "performedDateTime", ctx.measurement_period))
    {
        result.in_numerator = true;
    }

    return result;
}

/// Childhood Immunization Status (CIS)
/// Children who turned 2 during measurement period with required immunizations.
pub const CIS = measure.MeasureDefinition{
    .id = "CIS",
    .title = "Childhood Immunization Status",
    .description = "Percentage of children who turned 2 years old during the measurement period and had required immunizations.",
    .scoring = .proportion,
    .evaluate_fn = &evaluateCIS,
    .version = "2024",
    .clinical_recommendation = "CDC/ACIP recommended childhood immunization schedule.",
};

fn evaluateCIS(ctx: *const measure.PatientContext) measure.PatientResult {
    var result = measure.PatientResult{ .patient_id = cql.extractJsonString(ctx.patient_json, "id") orelse "unknown" };

    // Initial Population: Children who turn 2 during measurement period
    const bd = ctx.birthDate() orelse return result;
    const second_birthday = bd.addYears(2);
    if (!ctx.measurement_period.containsDate(second_birthday)) return result;

    result.in_initial_population = true;
    result.in_denominator = true;

    // Numerator: All required immunizations by 2nd birthday
    // Combo 3 (DTaP/IPV/MMR/HiB/HepB/VZV) - simplified check
    const birth_to_two = temporal.DateInterval{
        .start = bd,
        .end = second_birthday,
    };

    var total_required: u32 = 0;
    var total_met: u32 = 0;

    // DTaP: 4 doses by age 2
    total_required += 4;
    const dtap_count = ctx.countResourcesWithCode("Immunization", "vaccineCode", &valueset.VS_DTAP_VACCINE, "occurrenceDateTime", birth_to_two);
    total_met += @min(dtap_count, 4);

    // IPV: 3 doses by age 2
    total_required += 3;
    const ipv_count = ctx.countResourcesWithCode("Immunization", "vaccineCode", &valueset.VS_IPV_VACCINE, "occurrenceDateTime", birth_to_two);
    total_met += @min(ipv_count, 3);

    // MMR: 1 dose by age 2
    total_required += 1;
    const mmr_count = ctx.countResourcesWithCode("Immunization", "vaccineCode", &valueset.VS_MMR_VACCINE, "occurrenceDateTime", birth_to_two);
    total_met += @min(mmr_count, 1);

    // HepB: 3 doses by age 2
    total_required += 3;
    const hepb_count = ctx.countResourcesWithCode("Immunization", "vaccineCode", &valueset.VS_HEP_B_VACCINE, "occurrenceDateTime", birth_to_two);
    total_met += @min(hepb_count, 3);

    // VZV: 1 dose by age 2
    total_required += 1;
    const vzv_count = ctx.countResourcesWithCode("Immunization", "vaccineCode", &valueset.VS_VZV_VACCINE, "occurrenceDateTime", birth_to_two);
    total_met += @min(vzv_count, 1);

    // Meet numerator if all required immunizations are present
    if (total_met >= total_required) {
        result.in_numerator = true;
    }

    return result;
}

// ============================================================================
// Measure Registry
// ============================================================================

/// All built-in HEDIS measure definitions.
pub const ALL_MEASURES = [_]*const measure.MeasureDefinition{
    &BCS,
    &CCS,
    &CBP,
    &CDC_HBA1C_TESTING,
    &CDC_HBA1C_POOR_CONTROL,
    &CDC_EYE_EXAM,
    &CDC_KIDNEY_SCREENING,
    &COL,
    &WCV,
    &PPC_PRENATAL,
    &PPC_POSTPARTUM,
    &CIS,
};

/// Look up a measure definition by ID.
pub fn getMeasure(id: []const u8) ?*const measure.MeasureDefinition {
    for (ALL_MEASURES) |m| {
        if (std.mem.eql(u8, m.id, id)) return m;
    }
    return null;
}

/// Get all measure IDs.
pub fn listMeasureIds() [ALL_MEASURES.len][]const u8 {
    var ids: [ALL_MEASURES.len][]const u8 = undefined;
    for (ALL_MEASURES, 0..) |m, i| {
        ids[i] = m.id;
    }
    return ids;
}
