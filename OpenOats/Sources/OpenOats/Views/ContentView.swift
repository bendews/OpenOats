import AppKit
import SwiftUI

struct ContentView: View {
    private enum ControlBarAction {
        case toggle
        case confirmDownload
    }

    private enum MainWindowLayoutPhase: Equatable {
        case compactTimeline
        case expandedTimeline
        case liveSession

        var metrics: MainWindowMetrics {
            switch self {
            case .compactTimeline, .liveSession:
                return MainWindowMetrics(
                    minSize: OpenOatsRootApp.compactMainWindowMinSize,
                    idealSize: OpenOatsRootApp.compactMainWindowIdealSize,
                    maxSize: OpenOatsRootApp.compactMainWindowMaxSize
                )
            case .expandedTimeline:
                return MainWindowMetrics(
                    minSize: OpenOatsRootApp.expandedMainWindowMinSize,
                    idealSize: OpenOatsRootApp.expandedMainWindowIdealSize,
                    maxSize: OpenOatsRootApp.expandedMainWindowMaxSize
                )
            }
        }
    }

    private struct MainWindowMetrics {
        let minSize: NSSize
        let idealSize: NSSize
        let maxSize: NSSize
    }

    @Bindable var settings: AppSettings
    @Environment(AppContainer.self) private var container
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @State private var overlayManager = OverlayManager()
    @State private var miniBarManager = MiniBarManager()
    @State private var liveSessionController: LiveSessionController?
    @State private var mainWindowNotesController: NotesController?
    @State private var isMainWindowBrowserPresented = false
    @State private var lastSyncedWindowLayoutPhase: MainWindowLayoutPhase?
    @AppStorage("isTranscriptExpanded") private var isTranscriptExpanded = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showConsentSheet = false
    @State private var pendingControlBarAction: ControlBarAction?

    var body: some View {
        bodyWithModifiers
    }

    private var rootContent: some View {
        let controllerState = liveSessionController?.state ?? LiveSessionState()

        return VStack(spacing: 0) {
            HStack {
                Text("OpenOats")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if controllerState.isRunning {
                    Button {
                        openWindow(id: "notes")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                            Text("Past Meetings")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open the standalone Notes window while recording")
                    .accessibilityIdentifier("app.pastMeetingsButton")
                } else if !isMainWindowBrowserPresented {
                    Button {
                        coordinator.queueSessionSelection(nil)
                        previewMainWindowNavigationIfNeeded()
                        presentMainWindowBrowser()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                            Text("Past Meetings")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Browse upcoming meetings and saved history in the main window")
                    .accessibilityIdentifier("app.pastMeetingsButton")
                }

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityIdentifier("app.settingsButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let lastSession = controllerState.lastEndedSession, !isMainWindowBrowserPresented {
                if lastSession.utteranceCount > 0 {
                    HStack {
                        Text(sessionEndedBannerText(for: lastSession))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("app.sessionEndedBanner")
                        Spacer()
                        if controllerState.lastSessionHasNotes {
                            Button {
                                coordinator.queueSessionSelection(lastSession.id)
                                previewMainWindowNavigationIfNeeded()
                                presentMainWindowBrowser()
                            } label: {
                                Label("View Notes", systemImage: "doc.text")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("app.viewNotesButton")
                        } else {
                            Button {
                                coordinator.queueSessionSelection(lastSession.id)
                                previewMainWindowNavigationIfNeeded()
                                presentMainWindowBrowser()
                            } label: {
                                Label("Generate Notes", systemImage: "sparkles")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(OpenOatsProminentButtonStyle())
                            .controlSize(.small)
                            .accessibilityIdentifier("app.generateNotesButton")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)

                    Divider()
                } else if let transcriptIssue = lastSession.transcriptIssue {
                    let recoveryIsPending = coordinator.pendingRecoverySessionID == lastSession.id
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)

                        Text(transcriptIssue.sessionEndedBannerText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("app.sessionEndedBanner")
                        Spacer()
                        if recoveryIsPending {
                            Text("Recovery queued")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("app.recoveryQueuedLabel")
                        } else if controllerState.lastEndedSessionCanRetranscribe {
                            Button {
                                coordinator.queueSessionRetranscription(lastSession.id)
                                previewMainWindowNavigationIfNeeded()
                                presentMainWindowBrowser()
                            } label: {
                                Label("Re-transcribe", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(OpenOatsProminentButtonStyle())
                            .controlSize(.small)
                            .accessibilityIdentifier("app.retranscribeSessionButton")
                        }
                        Button {
                            coordinator.queueSessionSelection(lastSession.id)
                            previewMainWindowNavigationIfNeeded()
                            presentMainWindowBrowser()
                        } label: {
                            Label("Open Session", systemImage: "arrow.right.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("app.reviewSessionButton")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)

                    Divider()
                }
            }

            if controllerState.isRunning, let event = controllerState.matchedCalendarEvent {
                MatchedCalendarEventBanner(event: event)

                Divider()
            }

            if controllerState.isRunning {
                let sidebarLabel = settings.sidebarMode == .sidecast ? "Sidecast" : "Suggestions"
                let visibilityLabel = overlayManager.isVisible ? "visible" : "hidden"

                HStack(spacing: 6) {
                    Circle()
                        .fill(controllerState.isGeneratingSuggestions ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(sidebarLabel + " " + visibilityLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        toggleOverlay()
                    } label: {
                        Text(overlayManager.isVisible ? "Hide Panel" : "Show Panel")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            if controllerState.isRunning {
                Spacer(minLength: 0)

                if controllerState.showLiveTranscript {
                    DisclosureGroup(isExpanded: $isTranscriptExpanded) {
                        IsolatedTranscriptWrapper(state: controllerState)
                            .frame(height: 150)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Transcript")
                                .font(.system(size: 12, weight: .medium))
                            if !controllerState.liveTranscript.isEmpty {
                                Text("(\(controllerState.liveTranscript.count))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if isTranscriptExpanded && !controllerState.liveTranscript.isEmpty {
                                Button {
                                    openWindow(id: "transcript")
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .padding(4)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .help("Open transcript in separate window")

                                Button {
                                    copyTranscript()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .padding(4)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .help("Copy transcript")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Divider()
                ScratchpadSection(
                    text: Binding(
                        get: { controllerState.scratchpadText },
                        set: { liveSessionController?.updateScratchpad($0) }
                    )
                )
            } else {
                idleHomeShell
            }

            Divider()

            IsolatedControlBarWrapper(
                state: controllerState,
                onToggle: {
                    pendingControlBarAction = .toggle
                },
                onMuteToggle: {
                    liveSessionController?.toggleMicMute()
                },
                onConfirmDownload: {
                    pendingControlBarAction = .confirmDownload
                }
            )
        }
    }

    private var bodyWithModifiers: some View {
        contentWithEventHandlers
    }

    @ViewBuilder
    private var idleHomeShell: some View {
        HSplitView {
            IdleHomeDashboardView(
                settings: settings,
                selectedTimelineSelection: isMainWindowBrowserPresented ? coordinator.mainWindowBrowserSelection : nil,
                onSelectTimelineEvent: selectTimelineEvent,
                onSelectSavedSession: selectSavedSession
            )
            .frame(
                minWidth: isMainWindowBrowserPresented ? OpenOatsRootApp.timelinePaneMinWidth : nil,
                idealWidth: isMainWindowBrowserPresented ? OpenOatsRootApp.timelinePaneIdealWidth : nil,
                maxWidth: isMainWindowBrowserPresented ? OpenOatsRootApp.timelinePaneMaxWidth : .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            if isMainWindowBrowserPresented {
                mainWindowBrowserDetailPane
                    .frame(
                        minWidth: OpenOatsRootApp.detailPaneMinWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: isMainWindowBrowserPresented)
    }

    private var mainWindowBrowserDetailPane: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mainWindowBrowserLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(mainWindowBrowserTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button {
                    collapseMainWindowBrowser()
                } label: {
                    Label("Collapse", systemImage: "sidebar.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("mainWindow.detail.collapse")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            Group {
                if let mainWindowNotesController {
                    NotesView(
                        settings: settings,
                        layoutMode: .detailOnly,
                        navigationConsumer: .mainWindow,
                        controller: mainWindowNotesController
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
    }

    private var mainWindowBrowserLabel: String {
        guard let selection = coordinator.mainWindowBrowserSelection else {
            return "Meeting browser"
        }

        switch selection.target {
        case .meetingFamily(let event):
            return mainWindowEventStatus(for: event).label
        case .session:
            return "Saved meeting"
        }
    }

    private var mainWindowBrowserTitle: String {
        guard let selection = coordinator.mainWindowBrowserSelection else {
            return "Select a meeting"
        }

        switch selection.target {
        case .meetingFamily(let event):
            return event.title
        case .session(let sessionID):
            let session = (mainWindowNotesController?.state.sessionHistory ?? coordinator.sessionHistory)
                .first(where: { $0.id == sessionID })
            let trimmedTitle = session?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? "Untitled"
        }
    }

    private func mainWindowEventStatus(for event: CalendarEvent) -> (label: String, systemImage: String) {
        let now = Date()
        if event.endDate <= now {
            return ("Past meeting", "clock.arrow.trianglehead.counterclockwise.rotate.90")
        }
        if event.startDate <= now {
            return ("Meeting in progress", "dot.radiowaves.left.and.right")
        }
        return ("Upcoming meeting", "calendar.badge.clock")
    }

    private var sizedRootContent: some View {
        let metrics = windowLayoutPhase.metrics

        return rootContent
            .frame(
                minWidth: metrics.minSize.width,
                idealWidth: metrics.idealSize.width,
                maxWidth: metrics.maxSize.width,
                minHeight: metrics.minSize.height,
                idealHeight: metrics.idealSize.height,
                maxHeight: metrics.maxSize.height
            )
            .background(.ultraThinMaterial)
    }

    private var contentWithOverlay: some View {
        sizedRootContent.overlay {
            if showOnboarding {
                SetupWizardView(
                    isPresented: $showOnboarding,
                    settings: settings
                )
                    .transition(.opacity)
            }
            if showConsentSheet {
                RecordingConsentView(
                    isPresented: $showConsentSheet,
                    settings: settings
                )
                .transition(.opacity)
            }
        }
    }

    private var contentWithLifecycle: some View {
        contentWithOverlay
        .onAppear {
            scheduleMainWindowLayoutSync(windowLayoutPhase)
        }
        .onChange(of: windowLayoutPhase) { _, phase in
            scheduleMainWindowLayoutSync(phase)
        }
        .onChange(of: coordinator.mainWindowBrowserSelection?.stableID) { _, _ in
            guard isMainWindowBrowserPresented else { return }
            scheduleMainWindowLayoutSync(windowLayoutPhase)
        }
        .onChange(of: mainWindowBrowserLayoutSignature) { _, _ in
            guard isMainWindowBrowserPresented else { return }
            scheduleMainWindowLayoutSync(windowLayoutPhase)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing {
                hasCompletedOnboarding = true
            }
        }
        .onChange(of: showConsentSheet) { _, isShowing in
            if !isShowing && settings.hasAcknowledgedRecordingConsent
                && !(liveSessionController?.state.isRunning ?? false) {
                liveSessionController?.startSession(settings: settings)
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }

            let controller = LiveSessionController(coordinator: coordinator, container: container)
            controller.onRunningStateChanged = { [weak miniBarManager, weak overlayManager] isRunning in
                if isRunning {
                    miniBarManager?.state.onTap = {
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == OpenOatsRootApp.mainWindowID }) {
                            window.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                    showMiniBar(controller: controller, miniBarManager: miniBarManager)
                    if settings.sidebarMode == .classicSuggestions {
                        coordinator.suggestionEngine?.startPreFetching()
                    }
                    if settings.suggestionPanelEnabled {
                        showSidebarContent()
                    }
                } else {
                    miniBarManager?.hide()
                    coordinator.suggestionEngine?.stopPreFetching()
                    overlayManager?.hideAfterDelay(seconds: 2)
                }
            }
            controller.openNotesWindow = { [weak controller] in
                if controller?.state.isRunning == true {
                    openWindow(id: "notes")
                } else {
                    presentMainWindowBrowser()
                }
            }
            controller.onMiniBarContentUpdate = { [weak controller, weak miniBarManager] in
                showMiniBar(controller: controller, miniBarManager: miniBarManager)
            }
            coordinator.liveSessionController = controller
            liveSessionController = controller

            overlayManager.defaults = container.defaults
            miniBarManager.defaults = container.defaults
            await container.seedIfNeeded(coordinator: coordinator)
            await coordinator.loadHistory()
            await ensureMainWindowNotesControllerLoaded()
            previewMainWindowNavigationIfNeeded()
            if coordinator.requestedNotesNavigation?.consumer == .mainWindow, !controller.state.isRunning {
                isMainWindowBrowserPresented = true
            }
            controller.handlePendingExternalCommandIfPossible(settings: settings) {
                if controller.state.isRunning {
                    openWindow(id: "notes")
                } else {
                    presentMainWindowBrowser()
                }
            }

            await controller.performInitialSetup()

            container.updateCalendarIntegration(enabled: settings.calendarIntegrationEnabled)

            if settings.meetingAutoDetectEnabled {
                container.enableDetection(settings: settings, coordinator: coordinator)
                await container.detectionController?.evaluateImmediate()
            }

            await controller.runPollingLoop(settings: settings)
        }
        .onChange(of: settings.meetingAutoDetectEnabled) {
            if settings.meetingAutoDetectEnabled {
                container.enableDetection(settings: settings, coordinator: coordinator)
                Task {
                    await container.detectionController?.evaluateImmediate()
                }
            } else {
                container.disableDetection(coordinator: coordinator)
            }
        }
        .onChange(of: settings.calendarIntegrationEnabled) {
            container.updateCalendarIntegration(enabled: settings.calendarIntegrationEnabled)
        }
        .onChange(of: settings.suggestionsAlwaysOnTop) {
            overlayManager.updateAlwaysOnTop(settings.suggestionsAlwaysOnTop)
        }
        .onChange(of: settings.sidebarMode) {
            if settings.sidebarMode == .classicSuggestions {
                coordinator.suggestionEngine?.startPreFetching()
            } else {
                coordinator.suggestionEngine?.stopPreFetching()
            }
            guard liveSessionController?.state.isRunning == true, settings.suggestionPanelEnabled else { return }
            showSidebarContent()
        }
    }

    private var contentWithEventHandlers: some View {
        contentWithLifecycle
        .onKeyPress(.escape) {
            if overlayManager.isVisible {
                overlayManager.hide()
                return .handled
            }
            if isMainWindowBrowserPresented {
                collapseMainWindowBrowser()
                return .handled
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSuggestionPanel)) { _ in
            toggleOverlay()
        }
        .onChange(of: coordinator.requestedNotesNavigation?.id) { _, requestID in
            guard requestID != nil,
                  coordinator.requestedNotesNavigation?.consumer == .mainWindow,
                  !(liveSessionController?.state.isRunning ?? false) else { return }
            previewMainWindowNavigationIfNeeded()
            presentMainWindowBrowser()
        }
        .onChange(of: pendingControlBarAction) {
            guard let action = pendingControlBarAction else { return }
            pendingControlBarAction = nil
            handleControlBarAction(action)
        }
    }

    private var windowLayoutPhase: MainWindowLayoutPhase {
        guard !(liveSessionController?.state.isRunning ?? false) else {
            return .liveSession
        }
        return isMainWindowBrowserPresented ? .expandedTimeline : .compactTimeline
    }

    private var mainWindowBrowserLayoutSignature: String {
        guard let controller = mainWindowNotesController else {
            return "unloaded"
        }

        let state = controller.state
        let cleanupToken: String
        switch state.cleanupStatus {
        case .idle:
            cleanupToken = state.loadedTranscript.contains(where: { $0.cleanedText != nil }) ? "cleaned" : "idle"
        case .inProgress(let completed, let total):
            cleanupToken = "in-progress-\(completed)-of-\(total)"
        case .completed:
            cleanupToken = "completed"
        case .error(let message):
            cleanupToken = "error-\(message)"
        }

        return [
            state.selectedMeetingFamily?.key ?? "no-family",
            state.selectedSessionID ?? "no-session",
            state.loadedTranscript.isEmpty ? "no-transcript" : "transcript",
            state.loadedNotes == nil ? "no-notes" : "notes",
            state.availableAudioSources.isEmpty ? "no-audio" : "audio",
            state.canRetranscribeSelectedSession ? "retranscribe" : "no-retranscribe",
            state.hasOriginalTranscriptBackup ? "has-backup" : "no-backup",
            cleanupToken,
        ].joined(separator: "|")
    }

    @MainActor
    private func ensureMainWindowNotesControllerLoaded() async {
        guard mainWindowNotesController == nil else { return }
        let controller = NotesController(coordinator: coordinator, settings: settings)
        mainWindowNotesController = controller
        await controller.loadHistory()
    }

    @MainActor
    private func scheduleMainWindowLayoutSync(_ phase: MainWindowLayoutPhase) {
        Task { @MainActor in
            await Task.yield()
            syncMainWindowLayout(phase)
        }
    }

    @MainActor
    private func syncMainWindowLayout(_ phase: MainWindowLayoutPhase) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == OpenOatsRootApp.mainWindowID }) else {
            return
        }

        let priorPhase = lastSyncedWindowLayoutPhase
        defer {
            lastSyncedWindowLayoutPhase = phase
        }

        let metrics = phase.metrics
        let minimumWidth = resolvedMinimumWindowWidth(for: window, phase: phase, fallback: metrics.minSize.width)

        window.contentMinSize = NSSize(width: minimumWidth, height: metrics.minSize.height)
        window.contentMaxSize = metrics.maxSize

        let currentSize = window.contentLayoutRect.size
        let targetWidth: CGFloat
        switch phase {
        case .expandedTimeline:
            targetWidth = max(currentSize.width, minimumWidth)
        case .compactTimeline, .liveSession:
            targetWidth = min(currentSize.width, metrics.idealSize.width)
        }

        let targetSize = NSSize(
            width: min(max(targetWidth, minimumWidth), metrics.maxSize.width),
            height: min(max(currentSize.height, metrics.minSize.height), metrics.maxSize.height)
        )

        guard abs(targetSize.width - currentSize.width) > 0.5
            || abs(targetSize.height - currentSize.height) > 0.5 else {
            return
        }

        let shouldAnimateResize = priorPhase != nil && priorPhase != phase
        applyMainWindowContentSize(targetSize, to: window, animated: shouldAnimateResize)
    }

    @MainActor
    private func applyMainWindowContentSize(
        _ targetSize: NSSize,
        to window: NSWindow,
        animated: Bool
    ) {
        if !animated {
            window.setContentSize(targetSize)
            return
        }

        let currentFrame = window.frame
        var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        targetFrame.origin.x = currentFrame.origin.x
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height
        window.setFrame(targetFrame, display: true, animate: true)
    }

    @MainActor
    private func resolvedMinimumWindowWidth(
        for window: NSWindow,
        phase: MainWindowLayoutPhase,
        fallback: CGFloat
    ) -> CGFloat {
        guard phase == .expandedTimeline,
              let contentView = window.contentViewController?.view ?? window.contentView else {
            return fallback
        }

        contentView.layoutSubtreeIfNeeded()

        let fittingWidth = contentView.fittingSize.width
        guard fittingWidth.isFinite, fittingWidth > 0 else {
            return fallback
        }

        return min(max(fallback, fittingWidth), phase.metrics.maxSize.width)
    }

    @MainActor
    private func presentMainWindowBrowser() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            isMainWindowBrowserPresented = true
        }
        focusMainWindow()
    }

    @MainActor
    private func collapseMainWindowBrowser() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            isMainWindowBrowserPresented = false
        }
        coordinator.collapseMainWindowBrowser()
        mainWindowNotesController?.selectSession(nil)
    }

    @MainActor
    private func previewMainWindowNavigationIfNeeded() {
        guard let request = coordinator.requestedNotesNavigation, request.consumer == .mainWindow else {
            return
        }

        switch request.target {
        case .session(let sessionID), .retranscribeSession(let sessionID):
            coordinator.selectMainWindowSession(sessionID)
        case .meetingHistory(let event), .manualTranscript(let event):
            coordinator.selectMainWindowMeetingFamily(event)
        case .clearSelection:
            coordinator.collapseMainWindowBrowser()
        }
    }

    private func selectTimelineEvent(_ event: CalendarEvent) {
        let target = IdleDashboardNavigationResolver.target(
            for: event,
            sessionHistory: mainWindowNotesController?.state.sessionHistory ?? coordinator.sessionHistory,
            aliases: settings.meetingHistoryAliasesByKey,
            now: Date()
        )

        switch target {
        case .session(let sessionID):
            coordinator.queueSessionSelection(sessionID)
        case .meetingHistory(let resolvedEvent):
            coordinator.queueMeetingHistory(resolvedEvent)
        case .manualTranscript(let resolvedEvent):
            coordinator.queueManualTranscript(resolvedEvent)
        }

        previewMainWindowNavigationIfNeeded()
        presentMainWindowBrowser()
    }

    private func selectSavedSession(_ session: SessionIndex) {
        coordinator.queueSessionSelection(session.id)
        previewMainWindowNavigationIfNeeded()
        presentMainWindowBrowser()
    }

    @MainActor
    private func focusMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == OpenOatsRootApp.mainWindowID }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Actions

    private func startSession() {
        guard settings.hasAcknowledgedRecordingConsent else {
            withAnimation(.easeInOut(duration: 0.25)) {
                showConsentSheet = true
            }
            return
        }
        liveSessionController?.startSession(settings: settings)
    }

    private func stopSession() {
        liveSessionController?.stopSession(settings: settings)
    }

    private func showMiniBar(controller: LiveSessionController?, miniBarManager: MiniBarManager?) {
        guard let controller, let miniBarManager else { return }
        miniBarManager.update(
            audioLevel: controller.state.audioLevel,
            suggestions: controller.state.suggestions,
            isGenerating: controller.state.isGeneratingSuggestions
        )
        miniBarManager.show()
    }

    private func toggleOverlay() {
        switch settings.sidebarMode {
        case .classicSuggestions:
            overlayManager.toggle(content: SuggestionPanelContent(engine: coordinator.suggestionEngine))
        case .sidecast:
            overlayManager.toggleSidecast(content: sidecastContent())
        }
    }

    private func showSidebarContent() {
        switch settings.sidebarMode {
        case .classicSuggestions:
            overlayManager.showSidePanel(content: SuggestionPanelContent(engine: coordinator.suggestionEngine))
        case .sidecast:
            overlayManager.showSidecastSidebar(content: sidecastContent())
        }
    }

    private func sidecastContent() -> SidecastPanelContent {
        SidecastPanelContent(settings: settings, engine: coordinator.sidecastEngine)
    }

    private func copyTranscript() {
        guard let controller = liveSessionController else { return }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        let lines = controller.state.liveTranscript.map { u in
            "[\(timeFmt.string(from: u.timestamp))] \(u.speaker.displayLabel): \(u.displayText)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @MainActor
    private func handleControlBarAction(_ action: ControlBarAction) {
        switch action {
        case .toggle:
            if liveSessionController?.state.isRunning ?? false {
                stopSession()
            } else if liveSessionController?.state.downloadProgress == nil {
                startSession()
            }
        case .confirmDownload:
            liveSessionController?.downloadModelOnly(settings: settings)
        }
    }

    private func sessionEndedBannerText(for session: SessionIndex) -> String {
        if let recovery = session.transcriptRecovery {
            return "\(recovery.sessionEndedBannerText) · \(session.utteranceCount) utterances"
        }
        return "Session ended · \(session.utteranceCount) utterances"
    }
}

// MARK: - Scratchpad Section

private struct ScratchpadSection: View {
    @Binding var text: String
    @AppStorage("isScratchpadExpanded") private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } label: {
            HStack(spacing: 6) {
                Text("My Notes")
                    .font(.system(size: 12, weight: .medium))
                if !text.isEmpty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Isolated View Wrappers

private struct IsolatedTranscriptWrapper: View {
    let state: LiveSessionState

    var body: some View {
        TranscriptView(
            utterances: state.liveTranscript,
            volatileYouText: state.volatileYouText,
            volatileThemText: state.volatileThemText
        )
    }
}

private struct IsolatedControlBarWrapper: View {
    let state: LiveSessionState
    let onToggle: () -> Void
    let onMuteToggle: () -> Void
    let onConfirmDownload: () -> Void

    var body: some View {
        ControlBar(
            isRunning: state.isRunning,
            audioLevel: state.audioLevel,
            isMicMuted: state.isMicMuted,
            modelDisplayName: state.modelDisplayName,
            transcriptionPrompt: state.transcriptionPrompt,
            batchStatus: state.batchStatus,
            batchIsImporting: state.batchIsImporting,
            kbIndexingStatus: state.kbIndexingStatus,
            statusMessage: state.statusMessage,
            errorMessage: state.errorMessage,
            recordingHealthNotice: state.recordingHealthNotice,
            needsDownload: state.needsDownload,
            downloadProgress: state.downloadProgress,
            downloadDetail: state.downloadDetail,
            onToggle: onToggle,
            onMuteToggle: onMuteToggle,
            onConfirmDownload: onConfirmDownload
        )
    }
}
