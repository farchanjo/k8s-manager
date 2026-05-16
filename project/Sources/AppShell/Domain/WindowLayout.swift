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
    /// Cluster strip (vertical avatar column, ADR-0051) visibility — toggleable
    /// per ADR-0072 §"Change 4". Defaults to `true` on a fresh install or
    /// schema migration so the operator's existing one-click cluster-switch
    /// muscle memory keeps working until they explicitly hide the strip.
    public var clusterStripVisible: Bool
    public var frame: WindowFrame?

    public static let defaults = MainWindowState(
        sidebarColumnWidth: 260,
        contentColumnWidth: 420,
        detailWidthMinimum: 480,
        sidebarVisible: true,
        inspectorVisible: false,
        statusBarVisible: true,
        clusterStripVisible: true,
        frame: nil
    )

    public init(
        sidebarColumnWidth: Int = 260,
        contentColumnWidth: Int = 420,
        detailWidthMinimum: Int = 480,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = false,
        statusBarVisible: Bool = true,
        clusterStripVisible: Bool = true,
        frame: WindowFrame? = nil
    ) {
        self.sidebarColumnWidth = sidebarColumnWidth
        self.contentColumnWidth = contentColumnWidth
        self.detailWidthMinimum = detailWidthMinimum
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.statusBarVisible = statusBarVisible
        self.clusterStripVisible = clusterStripVisible
        self.frame = frame
    }

    /// Codable migration shim — when an older persisted JSON lacks
    /// `clusterStripVisible`, decode it as `true` so the strip remains
    /// visible until the operator explicitly toggles it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sidebarColumnWidth = try c.decode(Int.self, forKey: .sidebarColumnWidth)
        self.contentColumnWidth = try c.decode(Int.self, forKey: .contentColumnWidth)
        self.detailWidthMinimum = try c.decode(Int.self, forKey: .detailWidthMinimum)
        self.sidebarVisible = try c.decode(Bool.self, forKey: .sidebarVisible)
        self.inspectorVisible = try c.decode(Bool.self, forKey: .inspectorVisible)
        self.statusBarVisible = try c.decode(Bool.self, forKey: .statusBarVisible)
        self.clusterStripVisible = try c.decodeIfPresent(Bool.self, forKey: .clusterStripVisible) ?? true
        self.frame = try c.decodeIfPresent(WindowFrame.self, forKey: .frame)
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
