// DDD role: AggregateRoot
package app_shell

// #WindowLayout is the aggregate root for the primary window
// arrangement. It captures the main window state, any detached
// terminal windows, and the chat presentation mode. The aggregate is
// persisted in the local_persistence bounded context under the key
// "app_shell/window_layout" and is restored on cold launch.
//
// Identifiers are UUIDv7 (time-ordered) to support future audit
// logging that relies on monotonic ordering of window-open events.
#WindowLayout: {
	// id uniquely identifies this layout snapshot. Generated once at
	// first launch; never changes for the lifetime of the installation.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// mainWindow captures the geometry and visibility state of the
	// single primary NavigationSplitView window.
	mainWindow!: #MainWindowState

	// openTerminals lists all detached terminal windows that were open
	// when the layout was last persisted. On restore, each entry
	// triggers a TerminalSession reconnect or reopen attempt.
	openTerminals: [...#OpenTerminalWindow]

	// chatPresentation determines how the AI assistant surface is
	// presented relative to the main window.
	chatPresentation!: #ChatPresentation
}

// #MainWindowState captures the geometry, column widths, and panel
// visibility flags for the primary NavigationSplitView window.
#MainWindowState: {
	// sidebarColumnWidth is the persisted width in points of the
	// NavigationSplitView sidebar column. Clamped to [220, 360] by the
	// NavigationSplitView layout engine; values outside the range are
	// accepted here to allow the UI to clamp gracefully on restore.
	sidebarColumnWidth: int & >=220 & <=360 | *260

	// contentColumnWidth is the persisted width in points of the
	// NavigationSplitView content list column. Clamped to [320, 560].
	contentColumnWidth: int & >=320 & <=560 | *420

	// detailWidthMinimum is the floor width in points for the detail
	// pane. NavigationSplitView enforces this as a resizing constraint.
	// Must be at least 480 pt per ADR-0021.
	detailWidthMinimum: int & >=480 | *480

	// sidebarVisible tracks whether the sidebar column is currently
	// shown. The operator can toggle via the View menu or the standard
	// sidebar button in the toolbar.
	sidebarVisible: bool | *true

	// inspectorVisible tracks whether the .inspector panel is open.
	// Defaults to closed; the operator opens it via Command-Option-I.
	inspectorVisible: bool | *false

	// statusBarVisible tracks whether the bottom status bar is shown.
	// Defaults to visible; can be toggled via View menu.
	statusBarVisible: bool | *true

	// frame captures the screen position and size of the window.
	// Units are points in the screen coordinate system. May be null on
	// first launch (the window manager positions it with a cascade).
	frame?: #WindowFrame
}

// #WindowFrame captures the origin and size of a window in screen
// point coordinates. The coordinate system follows macOS convention:
// origin at bottom-left of the screen.
#WindowFrame: {
	// x is the horizontal distance from the left edge of the screen.
	x: number

	// y is the vertical distance from the bottom edge of the screen.
	y: number

	// width is the total window width including chrome.
	width: number & >0

	// height is the total window height including chrome.
	height: number & >0
}

// #ChatPresentation determines how the AI assistant chat surface
// appears relative to the primary window.
#ChatPresentation: {
	// kind selects the presentation mode.
	//
	// "docked_sheet" — chat slides up as a .sheet attached to the main
	//   window. Operator can still interact with the sidebar and content
	//   list behind the sheet (macOS 15+ .sheet presentationBackground).
	//
	// "separate_window" — chat opens in a second NSWindow with its own
	//   Window menu entry. The primary window remains fully interactive.
	//
	// "inspector_overlay" — chat occupies the .inspector panel of the
	//   main window. Replaces the annotation/diff inspector content
	//   while active.
	kind: "docked_sheet" | "separate_window" | "inspector_overlay" | *"docked_sheet"
}

// #OpenTerminalWindow captures the state of a detached terminal
// window. Detached windows are created when the operator tears a
// terminal tab out of the docked terminal panel.
#OpenTerminalWindow: {
	// id uniquely identifies this window instance within the layout.
	// New UUIDv7 is issued each time the operator detaches a tab.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// terminalSessionId references the terminal_session bounded context.
	// The app_shell never stores session credentials or PTY state; it
	// only holds the identifier needed to request a session restore from
	// the TerminalSession domain service on application relaunch.
	terminalSessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// windowFrame captures the detached window position and size.
	// May be absent if the window was never positioned (should not occur
	// in practice; the layout persister writes the frame on every resize).
	windowFrame?: #WindowFrame

	// dockedToMain indicates whether this terminal window was docked to
	// the main window at the time the layout was last persisted. Docked
	// windows are restored as tabs in the main window's terminal panel;
	// undocked windows are restored as independent NSWindows.
	dockedToMain: bool | *false
}
