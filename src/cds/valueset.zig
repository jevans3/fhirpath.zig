const std = @import("std");

/// A code within a specific coding system (e.g., SNOMED, LOINC, ICD-10, CPT).
pub const Code = struct {
    system: []const u8,
    code: []const u8,
    display: []const u8 = "",
};

/// Well-known code system URIs.
pub const Systems = struct {
    pub const SNOMED = "http://snomed.info/sct";
    pub const LOINC = "http://loinc.org";
    pub const ICD10 = "http://hl7.org/fhir/sid/icd-10-cm";
    pub const CPT = "http://www.ama-assn.org/go/cpt";
    pub const RXNORM = "http://www.nlm.nih.gov/research/umls/rxnorm";
    pub const CVX = "http://hl7.org/fhir/sid/cvx";
    pub const HCPCS = "https://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets";
    pub const FHIR_RESOURCE_TYPE = "http://hl7.org/fhir/resource-types";
    pub const OBSERVATION_CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category";
    pub const CONDITION_CLINICAL = "http://terminology.hl7.org/CodeSystem/condition-clinical";
    pub const CONDITION_VERIFICATION = "http://terminology.hl7.org/CodeSystem/condition-ver-status";
    pub const ENCOUNTER_CLASS = "http://terminology.hl7.org/CodeSystem/v3-ActCode";
};

/// A set of codes that define a clinical concept for measure evaluation.
/// Value sets are the primary way HEDIS/CQL measures reference clinical concepts.
pub const ValueSet = struct {
    oid: []const u8,
    name: []const u8,
    version: []const u8 = "",
    codes: []const Code,

    /// Check if a code (system + code) is a member of this value set.
    pub fn contains(self: *const ValueSet, system: []const u8, code: []const u8) bool {
        for (self.codes) |c| {
            if (std.mem.eql(u8, c.system, system) and std.mem.eql(u8, c.code, code)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a code (any system) is a member of this value set.
    pub fn containsCode(self: *const ValueSet, code: []const u8) bool {
        for (self.codes) |c| {
            if (std.mem.eql(u8, c.code, code)) {
                return true;
            }
        }
        return false;
    }
};

/// Registry that holds all value sets available for measure evaluation.
/// Supports lookup by OID and by name.
pub const ValueSetRegistry = struct {
    allocator: std.mem.Allocator,
    by_oid: std.StringHashMap(*const ValueSet),
    by_name: std.StringHashMap(*const ValueSet),

    pub fn init(allocator: std.mem.Allocator) ValueSetRegistry {
        return .{
            .allocator = allocator,
            .by_oid = std.StringHashMap(*const ValueSet).init(allocator),
            .by_name = std.StringHashMap(*const ValueSet).init(allocator),
        };
    }

    pub fn deinit(self: *ValueSetRegistry) void {
        self.by_oid.deinit();
        self.by_name.deinit();
    }

    pub fn register(self: *ValueSetRegistry, vs: *const ValueSet) !void {
        try self.by_oid.put(vs.oid, vs);
        if (vs.name.len > 0) {
            try self.by_name.put(vs.name, vs);
        }
    }

    pub fn getByOid(self: *const ValueSetRegistry, oid: []const u8) ?*const ValueSet {
        return self.by_oid.get(oid);
    }

    pub fn getByName(self: *const ValueSetRegistry, name: []const u8) ?*const ValueSet {
        return self.by_name.get(name);
    }

    /// Check if a code is in any registered value set with the given OID.
    pub fn memberOf(self: *const ValueSetRegistry, oid: []const u8, system: []const u8, code: []const u8) bool {
        if (self.by_oid.get(oid)) |vs| {
            return vs.contains(system, code);
        }
        return false;
    }
};

// ============================================================================
// HEDIS Value Sets - Representative codes for common measures
// ============================================================================

// --- Breast Cancer Screening (BCS) ---
pub const VS_MAMMOGRAPHY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.11.1047",
    .name = "Mammography",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "24606-6", .display = "MG Breast Screening" },
        .{ .system = Systems.LOINC, .code = "24605-8", .display = "MG Breast Diagnostic" },
        .{ .system = Systems.LOINC, .code = "26346-7", .display = "MG Breast Bilateral" },
        .{ .system = Systems.LOINC, .code = "26349-1", .display = "MG Breast Left" },
        .{ .system = Systems.LOINC, .code = "26350-9", .display = "MG Breast Right" },
        .{ .system = Systems.CPT, .code = "77067", .display = "Screening mammography bilateral" },
        .{ .system = Systems.CPT, .code = "77066", .display = "Diagnostic mammography bilateral" },
        .{ .system = Systems.CPT, .code = "77065", .display = "Diagnostic mammography unilateral" },
        .{ .system = Systems.HCPCS, .code = "G0202", .display = "Screening mammography digital" },
        .{ .system = Systems.SNOMED, .code = "384151000119104", .display = "Screening mammography of bilateral breasts" },
        .{ .system = Systems.SNOMED, .code = "24623002", .display = "Screening mammography" },
    },
};

pub const VS_BILATERAL_MASTECTOMY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1005",
    .name = "Bilateral Mastectomy",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "Z90.13", .display = "Acquired absence of bilateral breasts and nipples" },
        .{ .system = Systems.SNOMED, .code = "136071000119101", .display = "History of bilateral mastectomy" },
        .{ .system = Systems.SNOMED, .code = "428529004", .display = "History of bilateral mastectomy" },
    },
};

pub const VS_UNILATERAL_MASTECTOMY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1020",
    .name = "Unilateral Mastectomy",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "Z90.11", .display = "Acquired absence of right breast and nipple" },
        .{ .system = Systems.ICD10, .code = "Z90.12", .display = "Acquired absence of left breast and nipple" },
        .{ .system = Systems.SNOMED, .code = "429400009", .display = "History of unilateral mastectomy" },
        .{ .system = Systems.SNOMED, .code = "137681000119103", .display = "History of unilateral mastectomy of left breast" },
        .{ .system = Systems.SNOMED, .code = "137671000119100", .display = "History of unilateral mastectomy of right breast" },
    },
};

// --- Cervical Cancer Screening (CCS) ---
pub const VS_CERVICAL_CYTOLOGY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.12.1017",
    .name = "Cervical Cytology",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "10524-7", .display = "Cytology cervix" },
        .{ .system = Systems.LOINC, .code = "18500-9", .display = "Thin prep cytology" },
        .{ .system = Systems.LOINC, .code = "19762-4", .display = "General categories cervix" },
        .{ .system = Systems.LOINC, .code = "19764-0", .display = "Cytology cervix by thin prep" },
        .{ .system = Systems.LOINC, .code = "19765-7", .display = "Cytology cervix by smear" },
        .{ .system = Systems.CPT, .code = "88141", .display = "Cytopathology cervical/vaginal" },
        .{ .system = Systems.CPT, .code = "88142", .display = "Cytopathology thin layer" },
        .{ .system = Systems.CPT, .code = "88143", .display = "Cytopathology thin layer rescreening" },
        .{ .system = Systems.CPT, .code = "88147", .display = "Cytopathology automated smear screening" },
        .{ .system = Systems.CPT, .code = "88148", .display = "Cytopathology automated with manual rescreening" },
        .{ .system = Systems.CPT, .code = "88150", .display = "Cytopathology manual screening" },
        .{ .system = Systems.CPT, .code = "88152", .display = "Cytopathology automated thin prep" },
        .{ .system = Systems.CPT, .code = "88153", .display = "Cytopathology manual rescreening" },
        .{ .system = Systems.CPT, .code = "88164", .display = "Cytopathology thin layer, manual" },
        .{ .system = Systems.CPT, .code = "88165", .display = "Cytopathology thin layer, screened automated" },
        .{ .system = Systems.CPT, .code = "88166", .display = "Cytopathology thin layer, physician rescreen" },
        .{ .system = Systems.CPT, .code = "88167", .display = "Cytopathology thin layer automated rescreening" },
        .{ .system = Systems.CPT, .code = "88174", .display = "Cytopathology automated screening" },
        .{ .system = Systems.CPT, .code = "88175", .display = "Cytopathology automated screening with manual rescreening" },
    },
};

pub const VS_HPV_TEST = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.110.12.1059",
    .name = "HPV Test",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "21440-3", .display = "HPV DNA cervix probe" },
        .{ .system = Systems.LOINC, .code = "30167-1", .display = "HPV DNA cervix QL" },
        .{ .system = Systems.LOINC, .code = "38372-9", .display = "HPV 16+18+31+33+35+39+45+51+52+56+58+59+66+68" },
        .{ .system = Systems.LOINC, .code = "59263-4", .display = "HPV genotypes cervix" },
        .{ .system = Systems.LOINC, .code = "59264-2", .display = "HPV genotypes vaginal" },
        .{ .system = Systems.LOINC, .code = "77399-4", .display = "HPV 16 cervix" },
        .{ .system = Systems.LOINC, .code = "77400-0", .display = "HPV 18 cervix" },
        .{ .system = Systems.CPT, .code = "87624", .display = "HPV high-risk types" },
        .{ .system = Systems.CPT, .code = "87625", .display = "HPV types 16 and 18" },
    },
};

pub const VS_HYSTERECTOMY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1014",
    .name = "Hysterectomy with No Residual Cervix",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "Z90.710", .display = "Acquired absence of cervix and uterus" },
        .{ .system = Systems.ICD10, .code = "Z90.712", .display = "Acquired absence of cervix with remaining uterus" },
        .{ .system = Systems.SNOMED, .code = "428571003", .display = "History of total hysterectomy" },
        .{ .system = Systems.SNOMED, .code = "116140006", .display = "Total hysterectomy" },
    },
};

// --- Controlling High Blood Pressure (CBP) ---
pub const VS_ESSENTIAL_HYPERTENSION = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.104.12.1011",
    .name = "Essential Hypertension",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "I10", .display = "Essential (primary) hypertension" },
        .{ .system = Systems.SNOMED, .code = "59621000", .display = "Essential hypertension" },
        .{ .system = Systems.SNOMED, .code = "38341003", .display = "Hypertensive disorder" },
    },
};

pub const VS_BP_SYSTOLIC = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.104.12.1017",
    .name = "Systolic Blood Pressure",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "8480-6", .display = "Systolic blood pressure" },
        .{ .system = Systems.LOINC, .code = "8459-0", .display = "Systolic blood pressure sitting" },
    },
};

pub const VS_BP_DIASTOLIC = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.104.12.1018",
    .name = "Diastolic Blood Pressure",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "8462-4", .display = "Diastolic blood pressure" },
        .{ .system = Systems.LOINC, .code = "8453-3", .display = "Diastolic blood pressure sitting" },
    },
};

// --- Comprehensive Diabetes Care (CDC) ---
pub const VS_DIABETES = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.103.12.1001",
    .name = "Diabetes",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "E10.9", .display = "Type 1 diabetes mellitus without complications" },
        .{ .system = Systems.ICD10, .code = "E11.9", .display = "Type 2 diabetes mellitus without complications" },
        .{ .system = Systems.ICD10, .code = "E11.65", .display = "Type 2 diabetes mellitus with hyperglycemia" },
        .{ .system = Systems.ICD10, .code = "E11.69", .display = "Type 2 diabetes mellitus with other specified complication" },
        .{ .system = Systems.ICD10, .code = "E13.9", .display = "Other specified diabetes mellitus without complications" },
        .{ .system = Systems.SNOMED, .code = "73211009", .display = "Diabetes mellitus" },
        .{ .system = Systems.SNOMED, .code = "44054006", .display = "Type 2 diabetes mellitus" },
        .{ .system = Systems.SNOMED, .code = "46635009", .display = "Type 1 diabetes mellitus" },
    },
};

pub const VS_HBA1C_LAB_TEST = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1013",
    .name = "HbA1c Lab Test",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "4548-4", .display = "Hemoglobin A1c/Hemoglobin.total in Blood" },
        .{ .system = Systems.LOINC, .code = "4549-2", .display = "Hemoglobin A1c/Hemoglobin.total in Blood by Electrophoresis" },
        .{ .system = Systems.LOINC, .code = "17856-6", .display = "Hemoglobin A1c/Hemoglobin.total in Blood by HPLC" },
        .{ .system = Systems.LOINC, .code = "59261-8", .display = "Hemoglobin A1c/Hemoglobin.total in Blood by IFCC protocol" },
        .{ .system = Systems.CPT, .code = "83036", .display = "Hemoglobin; glycosylated (A1C)" },
    },
};

pub const VS_DIABETIC_RETINAL_SCREENING = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.115.12.1088",
    .name = "Diabetic Retinal Screening",
    .codes = &[_]Code{
        .{ .system = Systems.SNOMED, .code = "252779009", .display = "Single bright white flash electroretinography" },
        .{ .system = Systems.SNOMED, .code = "6615001", .display = "Electroretinography with medical evaluation" },
        .{ .system = Systems.CPT, .code = "92002", .display = "Ophthalmological services, new patient" },
        .{ .system = Systems.CPT, .code = "92004", .display = "Ophthalmological services, new patient, comprehensive" },
        .{ .system = Systems.CPT, .code = "92012", .display = "Ophthalmological services, established patient" },
        .{ .system = Systems.CPT, .code = "92014", .display = "Ophthalmological services, established patient, comprehensive" },
        .{ .system = Systems.CPT, .code = "92227", .display = "Remote imaging for detection of retinal disease" },
        .{ .system = Systems.CPT, .code = "92228", .display = "Remote imaging with physician review" },
        .{ .system = Systems.LOINC, .code = "32451-7", .display = "Physical findings of Eye" },
    },
};

pub const VS_URINE_ALBUMIN_CREATININE_RATIO = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.109.12.1024",
    .name = "Urine Albumin Creatinine Ratio",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "13705-9", .display = "Albumin/Creatinine [Mass ratio] in 24h Urine" },
        .{ .system = Systems.LOINC, .code = "14958-3", .display = "Microalbumin/Creatinine in Urine" },
        .{ .system = Systems.LOINC, .code = "14959-1", .display = "Microalbumin/Creatinine [Mass ratio] in Urine" },
        .{ .system = Systems.LOINC, .code = "30000-4", .display = "Microalbumin/Creatinine [Ratio] in Urine" },
        .{ .system = Systems.LOINC, .code = "32294-1", .display = "Albumin/Creatinine [Ratio] in Urine" },
        .{ .system = Systems.LOINC, .code = "44292-1", .display = "Microalbumin [Mass/volume] in 24h Urine" },
        .{ .system = Systems.LOINC, .code = "9318-7", .display = "Albumin/Creatinine [Mass ratio] in Urine" },
    },
};

// --- Colorectal Cancer Screening (COL) ---
pub const VS_COLONOSCOPY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.12.1020",
    .name = "Colonoscopy",
    .codes = &[_]Code{
        .{ .system = Systems.CPT, .code = "44388", .display = "Colonoscopy through stoma" },
        .{ .system = Systems.CPT, .code = "44389", .display = "Colonoscopy through stoma with biopsy" },
        .{ .system = Systems.CPT, .code = "44390", .display = "Colonoscopy through stoma with foreign body removal" },
        .{ .system = Systems.CPT, .code = "44391", .display = "Colonoscopy through stoma with control of bleeding" },
        .{ .system = Systems.CPT, .code = "44392", .display = "Colonoscopy through stoma with polypectomy" },
        .{ .system = Systems.CPT, .code = "45378", .display = "Colonoscopy diagnostic" },
        .{ .system = Systems.CPT, .code = "45380", .display = "Colonoscopy with biopsy" },
        .{ .system = Systems.CPT, .code = "45381", .display = "Colonoscopy with submucosal injection" },
        .{ .system = Systems.CPT, .code = "45382", .display = "Colonoscopy with control of bleeding" },
        .{ .system = Systems.CPT, .code = "45384", .display = "Colonoscopy with polypectomy" },
        .{ .system = Systems.CPT, .code = "45385", .display = "Colonoscopy with snare polypectomy" },
        .{ .system = Systems.SNOMED, .code = "73761001", .display = "Colonoscopy" },
        .{ .system = Systems.SNOMED, .code = "174158000", .display = "Open colonoscopy" },
    },
};

pub const VS_FOBT = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1011",
    .name = "Fecal Occult Blood Test",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "12503-9", .display = "Occult blood [Presence] in Stool --4th specimen" },
        .{ .system = Systems.LOINC, .code = "12504-7", .display = "Occult blood [Presence] in Stool --5th specimen" },
        .{ .system = Systems.LOINC, .code = "14563-1", .display = "Occult blood [Presence] in Stool --1st specimen" },
        .{ .system = Systems.LOINC, .code = "14564-9", .display = "Occult blood [Presence] in Stool --2nd specimen" },
        .{ .system = Systems.LOINC, .code = "14565-6", .display = "Occult blood [Presence] in Stool --3rd specimen" },
        .{ .system = Systems.LOINC, .code = "27396-1", .display = "Occult blood [Presence] in Stool" },
        .{ .system = Systems.LOINC, .code = "29771-3", .display = "Occult blood [Presence] in Stool by Guaiac" },
        .{ .system = Systems.LOINC, .code = "56490-6", .display = "Occult blood [Presence] in Stool by Immunoassay" },
        .{ .system = Systems.LOINC, .code = "57905-2", .display = "Occult blood [Presence] in Stool by Immunoassay qualitative" },
        .{ .system = Systems.LOINC, .code = "58453-2", .display = "Occult blood [Mass/volume] in Stool by Immunoassay" },
        .{ .system = Systems.CPT, .code = "82270", .display = "Blood occult by peroxidase activity feces" },
        .{ .system = Systems.CPT, .code = "82274", .display = "Blood occult by fecal hemoglobin determination" },
    },
};

pub const VS_FIT_DNA = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.12.1039",
    .name = "FIT-DNA Test",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "77354-9", .display = "Stool DNA panel" },
        .{ .system = Systems.CPT, .code = "81528", .display = "Oncology colorectal screening fecal DNA" },
    },
};

pub const VS_FLEXIBLE_SIGMOIDOSCOPY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1010",
    .name = "Flexible Sigmoidoscopy",
    .codes = &[_]Code{
        .{ .system = Systems.CPT, .code = "45330", .display = "Sigmoidoscopy diagnostic" },
        .{ .system = Systems.CPT, .code = "45331", .display = "Sigmoidoscopy with biopsy" },
        .{ .system = Systems.CPT, .code = "45332", .display = "Sigmoidoscopy with foreign body removal" },
        .{ .system = Systems.CPT, .code = "45333", .display = "Sigmoidoscopy with polypectomy" },
        .{ .system = Systems.CPT, .code = "45334", .display = "Sigmoidoscopy with control of bleeding" },
        .{ .system = Systems.CPT, .code = "45335", .display = "Sigmoidoscopy with submucosal injection" },
        .{ .system = Systems.CPT, .code = "45337", .display = "Sigmoidoscopy with decompression" },
        .{ .system = Systems.SNOMED, .code = "44441009", .display = "Flexible sigmoidoscopy" },
    },
};

pub const VS_CT_COLONOGRAPHY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.12.1038",
    .name = "CT Colonography",
    .codes = &[_]Code{
        .{ .system = Systems.LOINC, .code = "79101-2", .display = "CT Colon and Rectum" },
        .{ .system = Systems.CPT, .code = "74261", .display = "CT colonography diagnostic" },
        .{ .system = Systems.CPT, .code = "74263", .display = "CT colonography screening" },
    },
};

pub const VS_COLORECTAL_CANCER = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.108.12.1001",
    .name = "Colorectal Cancer",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "C18.0", .display = "Malignant neoplasm of cecum" },
        .{ .system = Systems.ICD10, .code = "C18.1", .display = "Malignant neoplasm of appendix" },
        .{ .system = Systems.ICD10, .code = "C18.2", .display = "Malignant neoplasm of ascending colon" },
        .{ .system = Systems.ICD10, .code = "C18.4", .display = "Malignant neoplasm of transverse colon" },
        .{ .system = Systems.ICD10, .code = "C18.5", .display = "Malignant neoplasm of splenic flexure" },
        .{ .system = Systems.ICD10, .code = "C18.6", .display = "Malignant neoplasm of descending colon" },
        .{ .system = Systems.ICD10, .code = "C18.7", .display = "Malignant neoplasm of sigmoid colon" },
        .{ .system = Systems.ICD10, .code = "C18.9", .display = "Malignant neoplasm of colon unspecified" },
        .{ .system = Systems.ICD10, .code = "C19", .display = "Malignant neoplasm of rectosigmoid junction" },
        .{ .system = Systems.ICD10, .code = "C20", .display = "Malignant neoplasm of rectum" },
        .{ .system = Systems.SNOMED, .code = "93761005", .display = "Primary malignant neoplasm of colon" },
        .{ .system = Systems.SNOMED, .code = "363406005", .display = "Malignant tumor of colon" },
        .{ .system = Systems.SNOMED, .code = "93771007", .display = "Primary malignant neoplasm of rectum" },
    },
};

pub const VS_TOTAL_COLECTOMY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.198.12.1019",
    .name = "Total Colectomy",
    .codes = &[_]Code{
        .{ .system = Systems.ICD10, .code = "Z90.49", .display = "Acquired absence of other parts of digestive tract" },
        .{ .system = Systems.SNOMED, .code = "36192008", .display = "Total colectomy" },
        .{ .system = Systems.SNOMED, .code = "787878004", .display = "History of total colectomy" },
        .{ .system = Systems.CPT, .code = "44150", .display = "Colectomy total abdominal" },
        .{ .system = Systems.CPT, .code = "44151", .display = "Colectomy total abdominal with proctectomy" },
        .{ .system = Systems.CPT, .code = "44155", .display = "Colectomy total abdominal with ileostomy" },
        .{ .system = Systems.CPT, .code = "44156", .display = "Colectomy total abdominal with continent ileostomy" },
        .{ .system = Systems.CPT, .code = "44157", .display = "Colectomy total abdominal with ileoanal anastomosis" },
        .{ .system = Systems.CPT, .code = "44158", .display = "Colectomy total abdominal with ileoanal anastomosis with proctectomy" },
        .{ .system = Systems.CPT, .code = "44210", .display = "Laparoscopic colectomy total abdominal" },
        .{ .system = Systems.CPT, .code = "44211", .display = "Laparoscopic colectomy total abdominal with proctectomy" },
        .{ .system = Systems.CPT, .code = "44212", .display = "Laparoscopic colectomy total abdominal with ileostomy" },
    },
};

// --- Well-Child Visits (WCV) ---
pub const VS_WELL_CHILD_VISIT = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.101.12.1024",
    .name = "Well Child Visits",
    .codes = &[_]Code{
        .{ .system = Systems.CPT, .code = "99381", .display = "Preventive visit new patient infant" },
        .{ .system = Systems.CPT, .code = "99382", .display = "Preventive visit new patient age 1-4" },
        .{ .system = Systems.CPT, .code = "99383", .display = "Preventive visit new patient age 5-11" },
        .{ .system = Systems.CPT, .code = "99384", .display = "Preventive visit new patient age 12-17" },
        .{ .system = Systems.CPT, .code = "99385", .display = "Preventive visit new patient age 18-39" },
        .{ .system = Systems.CPT, .code = "99391", .display = "Preventive visit established patient infant" },
        .{ .system = Systems.CPT, .code = "99392", .display = "Preventive visit established patient age 1-4" },
        .{ .system = Systems.CPT, .code = "99393", .display = "Preventive visit established patient age 5-11" },
        .{ .system = Systems.CPT, .code = "99394", .display = "Preventive visit established patient age 12-17" },
        .{ .system = Systems.CPT, .code = "99395", .display = "Preventive visit established patient age 18-39" },
        .{ .system = Systems.SNOMED, .code = "410620009", .display = "Well child visit" },
    },
};

// --- Prenatal and Postpartum Care (PPC) ---
pub const VS_PRENATAL_VISIT = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.101.12.1009",
    .name = "Prenatal Visits",
    .codes = &[_]Code{
        .{ .system = Systems.CPT, .code = "99500", .display = "Home visit for prenatal monitoring" },
        .{ .system = Systems.CPT, .code = "59400", .display = "Routine obstetric care" },
        .{ .system = Systems.CPT, .code = "59425", .display = "Antepartum care only" },
        .{ .system = Systems.CPT, .code = "59426", .display = "Antepartum care only 7 or more visits" },
        .{ .system = Systems.CPT, .code = "59410", .display = "Vaginal delivery including postpartum care" },
        .{ .system = Systems.SNOMED, .code = "18114009", .display = "Prenatal examination and care" },
    },
};

pub const VS_POSTPARTUM_VISIT = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.101.12.1010",
    .name = "Postpartum Visits",
    .codes = &[_]Code{
        .{ .system = Systems.CPT, .code = "59430", .display = "Postpartum care only" },
        .{ .system = Systems.CPT, .code = "99501", .display = "Home visit for postnatal assessment" },
        .{ .system = Systems.SNOMED, .code = "169762003", .display = "Postnatal visit" },
        .{ .system = Systems.SNOMED, .code = "384637004", .display = "Postpartum visit" },
    },
};

pub const VS_PREGNANCY = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.111.12.1012",
    .name = "Pregnancy",
    .codes = &[_]Code{
        .{ .system = Systems.SNOMED, .code = "77386006", .display = "Pregnancy" },
        .{ .system = Systems.SNOMED, .code = "72892002", .display = "Normal pregnancy" },
        .{ .system = Systems.ICD10, .code = "Z33.1", .display = "Pregnant state incidental" },
        .{ .system = Systems.ICD10, .code = "O09.90", .display = "Supervision of high risk pregnancy unspecified" },
    },
};

// --- Childhood Immunization Status (CIS) ---
pub const VS_DTAP_VACCINE = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.196.12.1214",
    .name = "DTaP Vaccine",
    .codes = &[_]Code{
        .{ .system = Systems.CVX, .code = "20", .display = "DTaP" },
        .{ .system = Systems.CVX, .code = "50", .display = "DTaP-Hib" },
        .{ .system = Systems.CVX, .code = "106", .display = "DTaP 5 pertussis antigens" },
        .{ .system = Systems.CVX, .code = "107", .display = "DTaP NOS" },
        .{ .system = Systems.CVX, .code = "110", .display = "DTaP-Hep B-IPV" },
        .{ .system = Systems.CVX, .code = "120", .display = "DTaP-Hib-IPV" },
    },
};

pub const VS_IPV_VACCINE = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.196.12.1219",
    .name = "IPV Vaccine",
    .codes = &[_]Code{
        .{ .system = Systems.CVX, .code = "10", .display = "IPV" },
        .{ .system = Systems.CVX, .code = "89", .display = "Polio NOS" },
        .{ .system = Systems.CVX, .code = "110", .display = "DTaP-Hep B-IPV" },
        .{ .system = Systems.CVX, .code = "120", .display = "DTaP-Hib-IPV" },
    },
};

pub const VS_MMR_VACCINE = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.196.12.1224",
    .name = "MMR Vaccine",
    .codes = &[_]Code{
        .{ .system = Systems.CVX, .code = "03", .display = "MMR" },
        .{ .system = Systems.CVX, .code = "94", .display = "MMRV" },
    },
};

pub const VS_HEP_B_VACCINE = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.196.12.1216",
    .name = "Hepatitis B Vaccine",
    .codes = &[_]Code{
        .{ .system = Systems.CVX, .code = "08", .display = "Hep B adolescent or pediatric" },
        .{ .system = Systems.CVX, .code = "44", .display = "Hep B adult" },
        .{ .system = Systems.CVX, .code = "45", .display = "Hep B NOS" },
        .{ .system = Systems.CVX, .code = "51", .display = "Hep A-Hep B" },
        .{ .system = Systems.CVX, .code = "110", .display = "DTaP-Hep B-IPV" },
    },
};

pub const VS_VZV_VACCINE = ValueSet{
    .oid = "2.16.840.1.113883.3.464.1003.196.12.1232",
    .name = "Varicella Vaccine",
    .codes = &[_]Code{
        .{ .system = Systems.CVX, .code = "21", .display = "Varicella" },
        .{ .system = Systems.CVX, .code = "94", .display = "MMRV" },
    },
};

/// Helper to register all built-in HEDIS value sets into a registry.
pub fn registerHedisValueSets(registry: *ValueSetRegistry) !void {
    // Breast Cancer Screening
    try registry.register(&VS_MAMMOGRAPHY);
    try registry.register(&VS_BILATERAL_MASTECTOMY);
    try registry.register(&VS_UNILATERAL_MASTECTOMY);
    // Cervical Cancer Screening
    try registry.register(&VS_CERVICAL_CYTOLOGY);
    try registry.register(&VS_HPV_TEST);
    try registry.register(&VS_HYSTERECTOMY);
    // Controlling High Blood Pressure
    try registry.register(&VS_ESSENTIAL_HYPERTENSION);
    try registry.register(&VS_BP_SYSTOLIC);
    try registry.register(&VS_BP_DIASTOLIC);
    // Comprehensive Diabetes Care
    try registry.register(&VS_DIABETES);
    try registry.register(&VS_HBA1C_LAB_TEST);
    try registry.register(&VS_DIABETIC_RETINAL_SCREENING);
    try registry.register(&VS_URINE_ALBUMIN_CREATININE_RATIO);
    // Colorectal Cancer Screening
    try registry.register(&VS_COLONOSCOPY);
    try registry.register(&VS_FOBT);
    try registry.register(&VS_FIT_DNA);
    try registry.register(&VS_FLEXIBLE_SIGMOIDOSCOPY);
    try registry.register(&VS_CT_COLONOGRAPHY);
    try registry.register(&VS_COLORECTAL_CANCER);
    try registry.register(&VS_TOTAL_COLECTOMY);
    // Well-Child Visits
    try registry.register(&VS_WELL_CHILD_VISIT);
    // Prenatal and Postpartum Care
    try registry.register(&VS_PRENATAL_VISIT);
    try registry.register(&VS_POSTPARTUM_VISIT);
    try registry.register(&VS_PREGNANCY);
    // Childhood Immunization Status
    try registry.register(&VS_DTAP_VACCINE);
    try registry.register(&VS_IPV_VACCINE);
    try registry.register(&VS_MMR_VACCINE);
    try registry.register(&VS_HEP_B_VACCINE);
    try registry.register(&VS_VZV_VACCINE);
}
