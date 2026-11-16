import SwiftUI

/// Editing rules for a custom From/To export range (issue #168).
///
/// The pickers used to bound each other: From to `...end` and To to `start...today`. After one
/// completed range, a later week was unreachable by changing From first, and an earlier week by
/// changing To first. Only choosing Today (start = end) cleared the bounds. Each endpoint now
/// accepts any day up to today; moving one past the other carries the other with it, so the range
/// stays valid without disabling days.
enum CustomDateRangeEditing {
    static func settingStart(
        _ newStart: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let newEnd = calendar.startOfDay(for: newStart) > calendar.startOfDay(for: end) ? newStart : end
        return (newStart, newEnd)
    }

    static func settingEnd(
        _ newEnd: Date,
        start: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let newStart = calendar.startOfDay(for: newEnd) < calendar.startOfDay(for: start) ? newEnd : start
        return (newStart, newEnd)
    }

    /// A From binding that carries To forward when From moves past it.
    static func startBinding(start: Binding<Date>, end: Binding<Date>) -> Binding<Date> {
        Binding(get: { start.wrappedValue }, set: { value in
            let range = settingStart(value, end: end.wrappedValue)
            if range.end != end.wrappedValue { end.wrappedValue = range.end }
            start.wrappedValue = range.start
        })
    }

    /// A To binding that carries From back when To moves before it.
    static func endBinding(start: Binding<Date>, end: Binding<Date>) -> Binding<Date> {
        Binding(get: { end.wrappedValue }, set: { value in
            let range = settingEnd(value, start: start.wrappedValue)
            if range.start != start.wrappedValue { start.wrappedValue = range.start }
            end.wrappedValue = range.end
        })
    }
}
