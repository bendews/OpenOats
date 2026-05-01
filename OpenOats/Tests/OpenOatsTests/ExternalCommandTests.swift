import XCTest
@testable import OpenOatsKit

@MainActor
final class ExternalCommandTests: XCTestCase {

    func testQueueExternalCommandSetsProperty() {
        let coordinator = AppCoordinator()
        XCTAssertNil(coordinator.pendingExternalCommand)

        coordinator.queueExternalCommand(.startSession())
        XCTAssertNotNil(coordinator.pendingExternalCommand)
        XCTAssertEqual(coordinator.pendingExternalCommand?.command, .startSession())
    }

    func testCompleteExternalCommandClearsMatchingRequest() {
        let coordinator = AppCoordinator()
        coordinator.queueExternalCommand(.stopSession)
        let requestID = coordinator.pendingExternalCommand!.id

        coordinator.completeExternalCommand(requestID)
        XCTAssertNil(coordinator.pendingExternalCommand)
    }

    func testCompleteExternalCommandIgnoresMismatchedID() {
        let coordinator = AppCoordinator()
        coordinator.queueExternalCommand(.stopSession)

        coordinator.completeExternalCommand(UUID())
        XCTAssertNotNil(coordinator.pendingExternalCommand)
    }

    func testOpenNotesQueuesSessionSelection() {
        let coordinator = AppCoordinator()
        coordinator.queueSessionSelection("session_abc")
        XCTAssertEqual(coordinator.requestedNotesNavigation?.target, .session("session_abc"))
        XCTAssertEqual(coordinator.requestedNotesNavigation?.consumer, .mainWindow)
    }

    func testConsumeRequestedSessionSelectionClearsAfterRead() {
        let coordinator = AppCoordinator()
        coordinator.queueSessionSelection("session_abc")

        let consumed = coordinator.consumeRequestedSessionSelection(for: .mainWindow)
        XCTAssertEqual(consumed, .session("session_abc"))
        XCTAssertNil(coordinator.requestedNotesNavigation)
    }

    func testQueueNilSessionSelectionRequestsClearSelection() {
        let coordinator = AppCoordinator()
        coordinator.queueSessionSelection(nil)

        XCTAssertEqual(coordinator.requestedNotesNavigation?.target, .clearSelection)
        XCTAssertEqual(coordinator.requestedNotesNavigation?.consumer, .mainWindow)
    }

    func testStandaloneNavigationRequestsAreNotConsumedByMainWindow() {
        let coordinator = AppCoordinator()
        coordinator.queueSessionSelection("session_abc", consumer: .standaloneWindow)

        XCTAssertNil(coordinator.consumeRequestedSessionSelection(for: .mainWindow))
        XCTAssertEqual(
            coordinator.consumeRequestedSessionSelection(for: .standaloneWindow),
            .session("session_abc")
        )
        XCTAssertNil(coordinator.requestedNotesNavigation)
    }

    func testQueueMeetingHistoryRequestsHistoryTarget() {
        let coordinator = AppCoordinator()
        let event = CalendarEvent(
            id: "evt",
            title: "Payment Ops",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )

        coordinator.queueMeetingHistory(event)

        XCTAssertEqual(coordinator.requestedNotesNavigation?.target, .meetingHistory(event))
        XCTAssertEqual(coordinator.requestedNotesNavigation?.consumer, .mainWindow)
    }

    func testSelectMainWindowMeetingFamilyStoresBrowserSelection() {
        let coordinator = AppCoordinator()
        let event = CalendarEvent(
            id: "evt",
            title: "Payment Ops",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )

        coordinator.selectMainWindowMeetingFamily(event)

        XCTAssertEqual(
            coordinator.mainWindowBrowserSelection,
            AppCoordinator.MainWindowBrowserSelection(target: .meetingFamily(event))
        )
        XCTAssertEqual(coordinator.mainWindowBrowserSelection?.calendarEventID, "evt")
    }

    func testSelectMainWindowSessionStoresBrowserSelection() {
        let coordinator = AppCoordinator()

        coordinator.selectMainWindowSession("session_abc")

        XCTAssertEqual(
            coordinator.mainWindowBrowserSelection,
            AppCoordinator.MainWindowBrowserSelection(target: .session("session_abc"))
        )
        XCTAssertEqual(coordinator.mainWindowBrowserSelection?.stableID, "session:session_abc")
    }

    func testCollapseMainWindowBrowserClearsSelection() {
        let coordinator = AppCoordinator()
        coordinator.selectMainWindowSession("session_abc")

        coordinator.collapseMainWindowBrowser()

        XCTAssertNil(coordinator.mainWindowBrowserSelection)
    }

    func testQueueExternalStartSessionCanCarryMeetingContextAndScratchpad() {
        let coordinator = AppCoordinator()
        let event = CalendarEvent(
            id: "evt",
            title: "Payment Ops",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/payment-ops")
        )

        coordinator.queueExternalCommand(.startSession(calendarEvent: event, scratchpadSeed: "Follow up on fees"))

        XCTAssertEqual(
            coordinator.pendingExternalCommand?.command,
            .startSession(calendarEvent: event, scratchpadSeed: "Follow up on fees")
        )
    }

    func testConsumeRequestedSessionSelectionReturnsNilWhenEmpty() {
        let coordinator = AppCoordinator()
        let consumed = coordinator.consumeRequestedSessionSelection(for: .mainWindow)
        XCTAssertNil(consumed)
    }
}
