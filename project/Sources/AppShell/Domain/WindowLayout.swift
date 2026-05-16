// Domain/WindowLayout.swift — app_shell bounded context
// DDD role: AggregateRoot (#WindowLayout)
// CUE source: docs/arch/contexts/app_shell/schemas/window_layout.cue

// MARK: - WindowFrame

/// Screen position and size of a window in macOS point coordinates (origin at bottom-left).
public struct WindowFrame: Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

// MARK: - MainWindowState

/// Geometry, column widths, and panel visibility for the primary NavigationSplitView window.
public struct MainWindowState: Sendable, Codable {
    /// Sidebar column width in points [220, 360].
    public var sidebarColumnWidth: Int
    /// Content list column width in points [320, 560].
    public var contentColumnWidth: Int
    /// Detail pane minimum width ≥480 pt (ADR-0021).
    public var detailWidthMinimum: Int
    public var sidebarVisible: Bool
    public var inspectorVisible: Bool
    public var statusBarVisible: Bool
    public var frame: WindowFrame?

    public static let defaults = MainWindowState(
        sidebarColumnWidth: 260,
        contentColumnWidth: 420,
        detailWidthMinimum: 480,
        sidebarVisible: true,
        inspectorVisible: false,
        statusBarVisible: true,
        frame: nil
    )

    public init(
        sidebarColumnWidth: Int = 260,
        contentColumnWidth: Int = 420,
        detailWidthMinimum: Int = 480,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = false,
        statusBarVisible: Bool = true,
        frame: WindowFrame? = nil
    ) {
        self.sidebarColumnWidth = sidebarColumnWidth
        self.contentColumnWidth = contentColumnWidth
        self.detailWidthMinimum = detailWidthMinimum
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.statusBarVisible = statusBarVisible
        self.frame = frame
    }
}

// MARK: - ChatPresentation

/// How the AI assistant chat surface appears relative to the primary window.
public struct ChatPresentation: Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case dockedSheet = "docked_sheet"
        case separateWindow = "separate_window"
        case inspectorOverlay = "inspector_overlay"
    }

    public let kind: Kind

    public static let `default` = ChatPresentation(kind: .dockedSheet)

    public init(kind: Kind = .dockedSheet) {
        self.kind = kind
    }
}

// MARK: - OpenTerminalWindow

/// State of a detached terminal window within the layout snapshot.
public struct OpenTerminalWindow: Sendable, Codable, Identifiable {
    /// UUIDv7 issued each time the operator detaches a tab.
    public let id: String
    /// References the `terminal_session` bounded context — no credentials stored here.
    public let terminalSessionId: String
    public var windowFrame: WindowFrame?
    public var dockedToMain: Bool

    public init(
        id: String,
        terminalSessionId: String,
        windowFrame: WindowFrame? = nil,
        dockedToMain: Bool = false
    ) {
        self.id = id
        self.terminalSessionId = terminalSessionId
        self.windowFrame = windowFrame
        self.dockedToMain = dockedToMain
    }
}

// MARK: - WindowLayout (AggregateRoot)

/// Aggregate root for the primary window arrangement.
///
/// Persisted under `app_shell/window_layout` in `local_persistence` and restored on cold launch.
public struct WindowLayout: Sendable, Codable, Identifiable {
    /// UUIDv7 stable identity (generated once at first launch).
    public let id: String
    public var mainWindow: MainWindowState
    /// All detached terminal windows open at the time of last persist.
    public var openTerminals: [OpenTerminalWindow]
    public var chatPresentation: ChatPresentation

    public init(
        id: String,
        mainWindow: MainWindowState = .defaults,
        openTerminals: [OpenTerminalWindow] = [],
        chatPresentation: ChatPresentation = .default
    ) {
        self.id = id
        self.mainWindow = mainWindow
        self.openTerminals = openTerminals
        self.chatPresentation = chatPresentation
    }
}
