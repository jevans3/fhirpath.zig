const std = @import("std");

/// Precision level for date/time values, following FHIR/CQL conventions.
pub const DatePrecision = enum {
    year,
    month,
    day,

    pub fn label(self: DatePrecision) []const u8 {
        return switch (self) {
            .year => "year",
            .month => "month",
            .day => "day",
        };
    }
};

/// A parsed date with known precision.
pub const Date = struct {
    year: i32,
    month: u8 = 1, // 1-12
    day: u8 = 1, // 1-31
    precision: DatePrecision = .day,

    /// Parse a FHIR date string (YYYY, YYYY-MM, or YYYY-MM-DD).
    pub fn parse(s: []const u8) !Date {
        if (s.len < 4) return error.InvalidDate;
        const year = std.fmt.parseInt(i32, s[0..4], 10) catch return error.InvalidDate;
        if (s.len == 4) return .{ .year = year, .precision = .year };
        if (s.len < 7 or s[4] != '-') return error.InvalidDate;
        const month = std.fmt.parseInt(u8, s[5..7], 10) catch return error.InvalidDate;
        if (month < 1 or month > 12) return error.InvalidDate;
        if (s.len == 7) return .{ .year = year, .month = month, .precision = .month };
        if (s.len < 10 or s[7] != '-') return error.InvalidDate;
        const day = std.fmt.parseInt(u8, s[8..10], 10) catch return error.InvalidDate;
        if (day < 1 or day > 31) return error.InvalidDate;
        return .{ .year = year, .month = month, .day = day, .precision = .day };
    }

    /// Format as ISO date string.
    pub fn formatDate(self: Date, buf: []u8) ![]const u8 {
        return switch (self.precision) {
            .year => std.fmt.bufPrint(buf, "{d:0>4}", .{self.year}),
            .month => std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}", .{ self.year, self.month }),
            .day => std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day }),
        };
    }

    /// Convert to days since epoch (2000-01-01) for comparison.
    pub fn toDays(self: Date) i64 {
        return dateToDays(self.year, self.month, self.day);
    }

    /// Compare two dates. Returns ordering.
    pub fn compare(self: Date, other: Date) std.math.Order {
        if (self.year != other.year) return std.math.order(self.year, other.year);
        if (self.month != other.month) return std.math.order(self.month, other.month);
        return std.math.order(self.day, other.day);
    }

    /// Check if this date is before another.
    pub fn before(self: Date, other: Date) bool {
        return self.compare(other) == .lt;
    }

    /// Check if this date is after another.
    pub fn after(self: Date, other: Date) bool {
        return self.compare(other) == .gt;
    }

    /// Check if this date is on or before another.
    pub fn onOrBefore(self: Date, other: Date) bool {
        return self.compare(other) != .gt;
    }

    /// Check if this date is on or after another.
    pub fn onOrAfter(self: Date, other: Date) bool {
        return self.compare(other) != .lt;
    }

    /// Add years to this date.
    pub fn addYears(self: Date, years: i32) Date {
        var result = self;
        result.year += years;
        result.day = clampDay(result.year, result.month, result.day);
        return result;
    }

    /// Add months to this date.
    pub fn addMonths(self: Date, months: i32) Date {
        var result = self;
        const total_months = @as(i32, @intCast(result.month)) - 1 + months;
        if (total_months >= 0) {
            result.year += @divTrunc(total_months, 12);
            result.month = @intCast(@mod(total_months, 12) + 1);
        } else {
            const abs_total: i32 = -total_months;
            result.year -= @divTrunc(abs_total - 1, 12) + 1;
            result.month = @intCast(12 - @mod(abs_total - 1, 12));
        }
        result.day = clampDay(result.year, result.month, result.day);
        return result;
    }

    /// Add days to this date.
    pub fn addDays(self: Date, days_to_add: i32) Date {
        const current_days = self.toDays();
        const new_days = current_days + days_to_add;
        return daysToDate(new_days);
    }

    /// Calculate age in years as of a reference date.
    pub fn ageInYears(self: Date, as_of: Date) i32 {
        var age = as_of.year - self.year;
        if (as_of.month < self.month or (as_of.month == self.month and as_of.day < self.day)) {
            age -= 1;
        }
        return age;
    }

    /// Calculate difference in calendar days.
    pub fn diffDays(self: Date, other: Date) i64 {
        return other.toDays() - self.toDays();
    }

    /// Calculate difference in months (truncated).
    pub fn diffMonths(self: Date, other: Date) i32 {
        const year_diff = other.year - self.year;
        const month_diff = @as(i32, @intCast(other.month)) - @as(i32, @intCast(self.month));
        var total = year_diff * 12 + month_diff;
        if (other.day < self.day) total -= 1;
        return total;
    }
};

/// An interval between two dates (inclusive on both ends by default).
pub const DateInterval = struct {
    start: Date,
    end: Date,
    start_inclusive: bool = true,
    end_inclusive: bool = true,

    /// Create a measurement year interval: [start_year-01-01, end_year-12-31].
    pub fn measurementYear(year: i32) DateInterval {
        return .{
            .start = .{ .year = year, .month = 1, .day = 1 },
            .end = .{ .year = year, .month = 12, .day = 31 },
        };
    }

    /// Create an interval of N years ending on a given date.
    pub fn yearsEndingOn(end_date: Date, years: i32) DateInterval {
        return .{
            .start = end_date.addYears(-years).addDays(1),
            .end = end_date,
        };
    }

    /// Create an interval of N months ending on a given date.
    pub fn monthsEndingOn(end_date: Date, months: i32) DateInterval {
        return .{
            .start = end_date.addMonths(-months).addDays(1),
            .end = end_date,
        };
    }

    /// Create an interval of N days ending on a given date.
    pub fn daysEndingOn(end_date: Date, days: i32) DateInterval {
        return .{
            .start = end_date.addDays(-days + 1),
            .end = end_date,
        };
    }

    /// Check if a date falls within this interval.
    pub fn containsDate(self: DateInterval, d: Date) bool {
        const after_start = if (self.start_inclusive) d.onOrAfter(self.start) else d.after(self.start);
        const before_end = if (self.end_inclusive) d.onOrBefore(self.end) else d.before(self.end);
        return after_start and before_end;
    }

    /// Check if this interval overlaps with another.
    pub fn overlaps(self: DateInterval, other: DateInterval) bool {
        return self.start.onOrBefore(other.end) and other.start.onOrBefore(self.end);
    }

    /// Check if this interval fully contains another.
    pub fn containsInterval(self: DateInterval, other: DateInterval) bool {
        return self.start.onOrBefore(other.start) and self.end.onOrAfter(other.end);
    }

    /// Duration of the interval in days.
    pub fn durationDays(self: DateInterval) i64 {
        return self.start.diffDays(self.end) + 1;
    }

    /// Intersect two intervals.
    pub fn intersect(self: DateInterval, other: DateInterval) ?DateInterval {
        const s = if (self.start.after(other.start)) self.start else other.start;
        const e = if (self.end.before(other.end)) self.end else other.end;
        if (s.after(e)) return null;
        return .{ .start = s, .end = e };
    }
};

/// Enrollment period for continuous coverage checks.
pub const EnrollmentPeriod = struct {
    start: Date,
    end: Date,
};

/// Check if a patient has continuous enrollment during a given interval,
/// allowing a specified number of gap days.
pub fn hasContinuousEnrollment(
    periods: []const EnrollmentPeriod,
    interval: DateInterval,
    allowed_gap_days: i32,
) bool {
    if (periods.len == 0) return false;

    // Sort periods by start date (simple insertion sort for typically small arrays).
    // We work on the assumption periods are already sorted; if not, the caller should sort.
    var covered_through: Date = interval.start;

    for (periods) |period| {
        // Does this period overlap with what we need?
        if (period.end.before(interval.start)) continue;
        if (period.start.after(interval.end)) break;

        // Check gap from where we've covered to this period's start
        const gap = covered_through.diffDays(period.start);
        if (gap > allowed_gap_days) return false;

        // Extend coverage
        if (period.end.after(covered_through)) {
            covered_through = period.end;
        }
    }

    return covered_through.onOrAfter(interval.end);
}

// ============================================================================
// Internal date arithmetic helpers
// ============================================================================

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    return @mod(year, 4) == 0;
}

fn daysInMonth(year: i32, month: u8) u8 {
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isLeapYear(year)) return 29;
    if (month < 1 or month > 12) return 30;
    return days[month - 1];
}

fn clampDay(year: i32, month: u8, day: u8) u8 {
    const max_day = daysInMonth(year, month);
    return if (day > max_day) max_day else day;
}

fn dateToDays(year: i32, month: u8, day: u8) i64 {
    // Days from epoch 2000-01-01
    const y: i64 = @intCast(year);
    const m: i64 = @intCast(month);
    const d: i64 = @intCast(day);

    // Use a modified Julian day calculation
    const a = @divTrunc(14 - m, 12);
    const y2 = y + 4800 - a;
    const m2 = m + 12 * a - 3;
    const jdn = d + @divTrunc(153 * m2 + 2, 5) + 365 * y2 + @divTrunc(y2, 4) - @divTrunc(y2, 100) + @divTrunc(y2, 400) - 32045;
    // Epoch for 2000-01-01 is JDN 2451545
    return jdn - 2451545;
}

fn daysToDate(days: i64) Date {
    // Convert from days since 2000-01-01 back to calendar date
    const jdn = days + 2451545;
    const a = jdn + 32044;
    const b = @divTrunc(4 * a + 3, 146097);
    const c = a - @divTrunc(146097 * b, 4);
    const d = @divTrunc(4 * c + 3, 1461);
    const e = c - @divTrunc(1461 * d, 4);
    const m = @divTrunc(5 * e + 2, 153);
    const day_val = e - @divTrunc(153 * m + 2, 5) + 1;
    const month_val = m + 3 - 12 * @divTrunc(m, 10);
    const year_val = 100 * b + d - 4800 + @divTrunc(m, 10);
    return .{
        .year = @intCast(year_val),
        .month = @intCast(month_val),
        .day = @intCast(day_val),
        .precision = .day,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parse date" {
    const d1 = try Date.parse("2024-01-15");
    try std.testing.expectEqual(@as(i32, 2024), d1.year);
    try std.testing.expectEqual(@as(u8, 1), d1.month);
    try std.testing.expectEqual(@as(u8, 15), d1.day);

    const d2 = try Date.parse("2024-06");
    try std.testing.expectEqual(DatePrecision.month, d2.precision);

    const d3 = try Date.parse("2024");
    try std.testing.expectEqual(DatePrecision.year, d3.precision);
}

test "date comparison" {
    const d1 = try Date.parse("2024-01-15");
    const d2 = try Date.parse("2024-06-30");
    try std.testing.expect(d1.before(d2));
    try std.testing.expect(d2.after(d1));
    try std.testing.expect(!d1.after(d2));
}

test "add years" {
    const d1 = try Date.parse("1990-03-15");
    const d2 = d1.addYears(50);
    try std.testing.expectEqual(@as(i32, 2040), d2.year);
    try std.testing.expectEqual(@as(u8, 3), d2.month);
    try std.testing.expectEqual(@as(u8, 15), d2.day);
}

test "add months" {
    const d1 = try Date.parse("2024-01-31");
    const d2 = d1.addMonths(1); // Feb 2024 (leap year)
    try std.testing.expectEqual(@as(u8, 2), d2.month);
    try std.testing.expectEqual(@as(u8, 29), d2.day); // Clamped to Feb 29
}

test "age in years" {
    const birth = try Date.parse("1990-06-15");
    const ref = try Date.parse("2024-03-15");
    try std.testing.expectEqual(@as(i32, 33), birth.ageInYears(ref));

    const ref2 = try Date.parse("2024-06-15");
    try std.testing.expectEqual(@as(i32, 34), birth.ageInYears(ref2));
}

test "measurement year" {
    const my = DateInterval.measurementYear(2024);
    try std.testing.expectEqual(@as(i32, 2024), my.start.year);
    try std.testing.expectEqual(@as(u8, 1), my.start.month);
    try std.testing.expectEqual(@as(u8, 1), my.start.day);
    try std.testing.expectEqual(@as(u8, 12), my.end.month);
    try std.testing.expectEqual(@as(u8, 31), my.end.day);
}

test "interval contains date" {
    const interval = DateInterval.measurementYear(2024);
    const d_in = try Date.parse("2024-06-15");
    const d_before = try Date.parse("2023-12-31");
    const d_after = try Date.parse("2025-01-01");
    try std.testing.expect(interval.containsDate(d_in));
    try std.testing.expect(!interval.containsDate(d_before));
    try std.testing.expect(!interval.containsDate(d_after));
}

test "date round trip" {
    const d1 = try Date.parse("2024-02-29"); // Leap year
    const days = d1.toDays();
    const d2 = daysToDate(days);
    try std.testing.expectEqual(d1.year, d2.year);
    try std.testing.expectEqual(d1.month, d2.month);
    try std.testing.expectEqual(d1.day, d2.day);
}
