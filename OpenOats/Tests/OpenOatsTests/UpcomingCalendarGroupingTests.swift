import XCTest
@testable import OpenOatsKit

final class UpcomingCalendarGroupingTests: XCTestCase {
    func testSectionTitleUsesTodayAndTomorrowLabels() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let todayGroup = UpcomingCalendarGrouping.DayGroup(
            date: today,
            events: [makeEvent(id: "today", title: "Demo Day", start: today)]
        )
        let tomorrowGroup = UpcomingCalendarGrouping.DayGroup(
            date: tomorrow,
            events: [makeEvent(id: "tomorrow", title: "Planning", start: tomorrow)]
        )

        XCTAssertEqual(todayGroup.sectionTitle, "Today")
        XCTAssertEqual(tomorrowGroup.sectionTitle, "Tomorrow")
    }

    func testGroupsEventsByDayAndSortsWithinEachDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = makeDate(year: 2026, month: 4, day: 20, hour: 9, minute: 45, calendar: calendar)
        let midday = makeDate(year: 2026, month: 4, day: 20, hour: 11, minute: 30, calendar: calendar)
        let nextDay = makeDate(year: 2026, month: 4, day: 21, hour: 14, minute: 30, calendar: calendar)

        let events = [
            makeEvent(id: "later", title: "Product Planning", start: midday),
            makeEvent(id: "next", title: "Platform Feedback", start: nextDay),
            makeEvent(id: "first", title: "Payment Ops", start: morning),
        ]

        let groups = UpcomingCalendarGrouping.groups(for: events, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].events.map(\.id), ["first", "later"])
        XCTAssertEqual(groups[1].events.map(\.id), ["next"])
    }

    func testGroupDateUsesStartOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let eventDate = makeDate(year: 2026, month: 4, day: 22, hour: 9, minute: 45, calendar: calendar)
        let groups = UpcomingCalendarGrouping.groups(
            for: [makeEvent(id: "event", title: "Payment Ops", start: eventDate)],
            calendar: calendar
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].date, calendar.startOfDay(for: eventDate))
    }

    func testMeetingHistoryResolverMatchesNormalizedTitlesNewestFirst() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let event = makeEvent(id: "evt", title: "Payment Ops / Merchant stand up", start: startedAt)
        let sessions = [
            SessionIndex(
                id: "older",
                startedAt: startedAt.addingTimeInterval(-1_000),
                endedAt: nil,
                templateSnapshot: nil,
                title: "Payment Ops Merchant stand-up",
                utteranceCount: 8,
                hasNotes: false,
                language: nil,
                meetingApp: nil,
                engine: nil,
                tags: nil,
                source: nil
            ),
            SessionIndex(
                id: "newer",
                startedAt: startedAt.addingTimeInterval(-100),
                endedAt: nil,
                templateSnapshot: nil,
                title: "  Payment Ops Merchant   stand up  ",
                utteranceCount: 12,
                hasNotes: true,
                language: nil,
                meetingApp: nil,
                engine: nil,
                tags: nil,
                source: nil
            ),
        ]

        let matched = MeetingHistoryResolver.matchingSessions(for: event, sessionHistory: sessions)
        XCTAssertEqual(matched.map(\.id), ["newer", "older"])
    }

    func testMeetingHistoryResolverMatchesRecurringSeriesEvenWhenTitleDrifts() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let event = makeEvent(
            id: "evt",
            title: "Regular Platform feedback",
            start: startedAt,
            externalIdentifier: "series-platform-feedback"
        )
        let sessions = [
            SessionIndex(
                id: "drifted",
                startedAt: startedAt.addingTimeInterval(-100),
                endedAt: nil,
                templateSnapshot: nil,
                title: "Platform council review",
                utteranceCount: 12,
                hasNotes: true,
                language: nil,
                meetingApp: nil,
                engine: nil,
                tags: nil,
                source: nil,
                meetingFamilyKey: MeetingHistoryResolver.seriesHistoryKey(forExternalIdentifier: "series-platform-feedback")
            ),
        ]

        let matched = MeetingHistoryResolver.matchingSessions(for: event, sessionHistory: sessions)
        XCTAssertEqual(matched.map(\.id), ["drifted"])
    }

    func testMeetingHistoryResolverReturnsEmptyWithoutTitleMatch() {
        let event = makeEvent(id: "evt", title: "Design Review", start: Date())
        let sessions = [
            SessionIndex(
                id: "other",
                startedAt: Date().addingTimeInterval(-100),
                endedAt: nil,
                templateSnapshot: nil,
                title: "Weekly Sync",
                utteranceCount: 5,
                hasNotes: true,
                language: nil,
                meetingApp: nil,
                engine: nil,
                tags: nil,
                source: nil
            ),
        ]

        XCTAssertTrue(MeetingHistoryResolver.matchingSessions(for: event, sessionHistory: sessions).isEmpty)
    }

    func testMeetingHistoryResolverMatchesAliasedTitles() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            SessionIndex(
                id: "legacy",
                startedAt: startedAt.addingTimeInterval(-500),
                endedAt: nil,
                templateSnapshot: nil,
                title: "Payment Ops",
                utteranceCount: 10,
                hasNotes: true,
                language: nil,
                meetingApp: nil,
                engine: nil,
                tags: nil,
                source: nil
            ),
        ]

        let matched = MeetingHistoryResolver.matchingSessions(
            forHistoryKey: MeetingHistoryResolver.historyKey(for: "Payment Ops / Merchant standup"),
            sessionHistory: sessions,
            aliases: [
                MeetingHistoryResolver.historyKey(for: "Payment Ops"):
                    MeetingHistoryResolver.historyKey(for: "Payment Ops / Merchant standup")
            ]
        )

        XCTAssertEqual(matched.map(\.id), ["legacy"])
    }

    func testSelectionPrefersCalendarCoverageBeforeFillingRemainingSlots() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            makeEvent(id: "a1", title: "Alpha 1", start: base.addingTimeInterval(60), calendarID: "A", calendarTitle: "Work"),
            makeEvent(id: "a2", title: "Alpha 2", start: base.addingTimeInterval(120), calendarID: "A", calendarTitle: "Work"),
            makeEvent(id: "a3", title: "Alpha 3", start: base.addingTimeInterval(180), calendarID: "A", calendarTitle: "Work"),
            makeEvent(id: "b1", title: "Beta 1", start: base.addingTimeInterval(240), calendarID: "B", calendarTitle: "Personal"),
            makeEvent(id: "c1", title: "Gamma 1", start: base.addingTimeInterval(300), calendarID: "C", calendarTitle: "Side"),
        ]

        let selected = UpcomingEventSelection.select(from: events, limit: 4)

        XCTAssertEqual(selected.map(\.id), ["a1", "a2", "b1", "c1"])
    }

    func testDistinctCalendarCountUsesCalendarIdentity() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            makeEvent(id: "a1", title: "Alpha 1", start: base, calendarID: "A", calendarTitle: "Work"),
            makeEvent(id: "a2", title: "Alpha 2", start: base.addingTimeInterval(60), calendarID: "A", calendarTitle: "Work"),
            makeEvent(id: "b1", title: "Beta 1", start: base.addingTimeInterval(120), calendarID: "B", calendarTitle: "Personal"),
        ]

        XCTAssertEqual(UpcomingEventSelection.distinctCalendarCount(in: events), 2)
    }

    func testEarlierTodaySelectionReturnsEndedMeetingsNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = makeEvent(
            id: "older",
            title: "Morning Sync",
            start: now.addingTimeInterval(-4_000),
            duration: 1_200
        )
        let newer = makeEvent(
            id: "newer",
            title: "Lunch Review",
            start: now.addingTimeInterval(-2_000),
            duration: 1_200
        )
        let current = makeEvent(
            id: "current",
            title: "Current Meeting",
            start: now.addingTimeInterval(-300),
            duration: 1_800
        )
        let future = makeEvent(
            id: "future",
            title: "Later Today",
            start: now.addingTimeInterval(1_800),
            duration: 1_200
        )

        let selected = EarlierTodaySelection.select(
            from: [older, future, current, newer],
            now: now,
            currentEventID: current.id
        )

        XCTAssertEqual(selected.map(\.id), ["newer", "older"])
    }

    func testComingUpGroupsIncludeTodayWhenOnlyEarlierTodayEventsExist() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let referenceDate = makeDate(year: 2026, month: 4, day: 24, hour: 17, minute: 0, calendar: calendar)
        let earlierToday = [
            makeEvent(
                id: "ended",
                title: "Standup",
                start: makeDate(year: 2026, month: 4, day: 24, hour: 9, minute: 0, calendar: calendar)
            )
        ]
        let future = [
            makeEvent(
                id: "future",
                title: "Planning",
                start: makeDate(year: 2026, month: 4, day: 27, hour: 11, minute: 30, calendar: calendar)
            )
        ]

        let groups = ComingUpDayGroupSelection.groups(
            for: future,
            earlierTodayEvents: earlierToday,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].date, calendar.startOfDay(for: referenceDate))
        XCTAssertTrue(groups[0].events.isEmpty)
        XCTAssertEqual(groups[1].events.map(\.id), ["future"])
    }

    func testSavedHistorySelectionOmitsTodayAndKeepsNewestSessionsFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let referenceDate = makeDate(year: 2026, month: 4, day: 24, hour: 17, minute: 0, calendar: calendar)
        let sessions = [
            makeSession(
                id: "today",
                title: "Today Sync",
                startedAt: makeDate(year: 2026, month: 4, day: 24, hour: 9, minute: 0, calendar: calendar),
                utteranceCount: 4
            ),
            makeSession(
                id: "yesterday-late",
                title: "Yesterday Review",
                startedAt: makeDate(year: 2026, month: 4, day: 23, hour: 16, minute: 30, calendar: calendar),
                utteranceCount: 8
            ),
            makeSession(
                id: "yesterday-early",
                title: "Yesterday Standup",
                startedAt: makeDate(year: 2026, month: 4, day: 23, hour: 9, minute: 0, calendar: calendar),
                utteranceCount: 3
            ),
            makeSession(
                id: "older",
                title: "Older Planning",
                startedAt: makeDate(year: 2026, month: 4, day: 20, hour: 12, minute: 0, calendar: calendar),
                utteranceCount: 6
            ),
        ]

        let selected = IdleDashboardHistorySelection.select(
            from: sessions,
            referenceDate: referenceDate,
            calendar: calendar,
            limit: 10
        )

        XCTAssertEqual(selected.map(\.id), ["yesterday-late", "yesterday-early", "older"])
    }

    func testSavedHistoryGroupingSortsDaysAndSessionsNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let sessions = [
            makeSession(
                id: "older-day",
                title: "Monday Planning",
                startedAt: makeDate(year: 2026, month: 4, day: 20, hour: 11, minute: 0, calendar: calendar),
                utteranceCount: 5
            ),
            makeSession(
                id: "same-day-earlier",
                title: "Tuesday Standup",
                startedAt: makeDate(year: 2026, month: 4, day: 21, hour: 9, minute: 0, calendar: calendar),
                utteranceCount: 7
            ),
            makeSession(
                id: "same-day-later",
                title: "Tuesday Review",
                startedAt: makeDate(year: 2026, month: 4, day: 21, hour: 16, minute: 0, calendar: calendar),
                utteranceCount: 9
            ),
        ]

        let groups = UpcomingCalendarGrouping.groups(for: sessions, calendar: calendar)

        XCTAssertEqual(groups.map { $0.sessions.map(\.id) }, [["same-day-later", "same-day-earlier"], ["older-day"]])
    }

    func testEndedEventWithUsableHistoryRoutesToMeetingHistory() {
        let endedEvent = makeEvent(
            id: "ended",
            title: "Payment Ops",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 60
        )
        let sessions = [
            makeSession(
                id: "saved",
                title: "Payment Ops",
                startedAt: endedEvent.startDate.addingTimeInterval(-86_400),
                utteranceCount: 12,
                hasNotes: true
            ),
        ]

        let target = IdleDashboardNavigationResolver.target(
            for: endedEvent,
            sessionHistory: sessions,
            aliases: [:],
            now: endedEvent.endDate.addingTimeInterval(60)
        )

        XCTAssertEqual(target, .meetingHistory(endedEvent))
    }

    func testEndedEventWithoutUsableHistoryRoutesToManualTranscript() {
        let endedEvent = makeEvent(
            id: "ended",
            title: "Design Review",
            start: Date(timeIntervalSince1970: 1_700_100_000),
            duration: 60
        )
        let sessions = [
            makeSession(
                id: "empty",
                title: "Design Review",
                startedAt: endedEvent.startDate.addingTimeInterval(-86_400),
                utteranceCount: 0,
                hasNotes: false
            ),
        ]

        let target = IdleDashboardNavigationResolver.target(
            for: endedEvent,
            sessionHistory: sessions,
            aliases: [:],
            now: endedEvent.endDate.addingTimeInterval(60)
        )

        XCTAssertEqual(target, .manualTranscript(endedEvent))
    }

    private func makeEvent(
        id: String,
        title: String,
        start: Date,
        externalIdentifier: String? = nil,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        duration: TimeInterval = 30 * 60
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            externalIdentifier: externalIdentifier,
            calendarID: calendarID,
            calendarTitle: calendarTitle,
            calendarColorHex: nil,
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )
    }

    private func makeSession(
        id: String,
        title: String,
        startedAt: Date,
        utteranceCount: Int,
        hasNotes: Bool = false,
        meetingFamilyKey: String? = nil
    ) -> SessionIndex {
        SessionIndex(
            id: id,
            startedAt: startedAt,
            endedAt: nil,
            templateSnapshot: nil,
            title: title,
            utteranceCount: utteranceCount,
            hasNotes: hasNotes,
            language: nil,
            meetingApp: nil,
            engine: nil,
            tags: nil,
            source: nil,
            meetingFamilyKey: meetingFamilyKey
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
