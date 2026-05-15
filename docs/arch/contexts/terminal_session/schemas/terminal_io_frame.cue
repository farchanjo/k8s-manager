// DDD role: ValueObject
package terminal_session

// #TerminalIOFrame is the value object representing a single logical
// channel frame exchanged between the application and the Kubernetes
// exec WebSocket endpoint under the v5.channel.k8s.io subprotocol.
//
// Every WebSocket binary frame on the wire begins with a 1-byte channel
// number prefix (0x00..0x04). TerminalSessionActor demultiplexes inbound
// frames and constructs #TerminalIOFrame values for each received message.
// Outbound frames are constructed from #TerminalIOFrame values by the
// actor before calling URLSessionWebSocketTask.send(_:).
//
// Invariants:
//   - channel is in range 0..4 inclusive.
//   - Exactly one of the frame variant fields is present.
//   - #StdinFrame and #ResizeFrame are outbound-only (client -> server).
//   - #StdoutFrame, #StderrFrame, and #ErrorFrame are inbound-only
//     (server -> client).
//   - sessionId must match the owning TerminalSession.id.
#TerminalIOFrame: #StdinFrame | #StdoutFrame | #StderrFrame | #ErrorFrame | #ResizeFrame

// #StdinFrame carries raw bytes from the operator's keyboard to the
// remote process's stdin stream. channel must be 0.
// bytes is the base64-encoded representation of the raw byte payload
// (UTF-8 text and control sequences including 0x03 for SIGINT etc.).
#StdinFrame: {
	// sessionId references the owning TerminalSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// channel must be 0 for stdin frames.
	channel!: 0

	// bytes is the base64-encoded payload. The raw byte sequence is
	// prepended with the channel byte (0x00) when written to the wire.
	bytes!: =~"^[A-Za-z0-9+/]*={0,2}$"
}

// #StdoutFrame carries raw bytes from the remote process's stdout stream
// to the terminal UI. channel must be 1.
#StdoutFrame: {
	// sessionId references the owning TerminalSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// channel must be 1 for stdout frames.
	channel!: 1

	// bytes is the base64-encoded payload received after stripping the
	// channel-byte prefix from the raw WebSocket binary frame.
	bytes!: =~"^[A-Za-z0-9+/]*={0,2}$"
}

// #StderrFrame carries raw bytes from the remote process's stderr stream.
// channel must be 2.
#StderrFrame: {
	// sessionId references the owning TerminalSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// channel must be 2 for stderr frames.
	channel!: 2

	// bytes is the base64-encoded payload.
	bytes!: =~"^[A-Za-z0-9+/]*={0,2}$"
}

// #ErrorFrame carries a JSON-encoded error message from the API server.
// This is the channel 3 message introduced in v5.channel.k8s.io.
// The payload is a UTF-8 JSON object; the most common form is
// {"ExitCode":<int>} when the remote process exits with an explicit code,
// or {"message":"<text>"} for API-level errors such as container not found.
// channel must be 3.
#ErrorFrame: {
	// sessionId references the owning TerminalSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// channel must be 3 for error frames.
	channel!: 3

	// json is the raw UTF-8 JSON text delivered by the API server on
	// channel 3. The application parses this to extract exit codes and
	// error messages.
	json!: string
}

// #ResizeFrame carries a terminal resize event from the application to
// the remote process's TTY. channel must be 4.
// The on-wire payload after the channel byte is UTF-8 JSON:
// {"Width":<int>,"Height":<int>}
// TerminalSessionActor debounces resize events to 100 ms before
// constructing and sending a #ResizeFrame (per ADR-0017).
#ResizeFrame: {
	// sessionId references the owning TerminalSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// channel must be 4 for resize frames.
	channel!: 4

	// rows is the new terminal height in character rows. Must be >= 1.
	rows!: int & >=1

	// cols is the new terminal width in character columns. Must be >= 1.
	cols!: int & >=1
}
