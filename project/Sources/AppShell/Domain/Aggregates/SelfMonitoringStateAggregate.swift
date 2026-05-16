// Domain/Aggregates/SelfMonitoringStateAggregate.swift — app_shell bounded context
// DDD role: AggregateRoot orchestration (actor)
// ADR ref: ADR-0027, ADR-0034

import Foundation

/// Actor orchestrating self-monitoring state and the in-memory sample ring buffer.
///
/// The `SelfMonitoringSampler` domain service pushes `SelfMetricSample` values here.
/// The Settings → Diagnostics view model reads state via `stateStream()` and `samplesStream()`.
public actor SelfMonitoringStateAggregate {

    // MARK: State

    private var preferences: SelfMonitoringState
    private var ringBuffer: [SelfMetricSample]

    private var prefContinuations: [UUID: AsyncStream<SelfMonitoringState>.Continuation] = [:]
    private var sampleContinuations: [UUID: AsyncStream<[SelfMetricSample]>.Continuation] = [:]

    // MARK: Init

    public init(initial: SelfMonitoringState) {
        self.preferences = initial
        self.ringBuffer = []
    }

    // MARK: Read

    public var currentPreferences: SelfMonitoringState { preferences }
    public var currentSamples: [SelfMetricSample] { ringBuffer }

    // MARK: Mutations — preferences

    public func updatePreferences(
        sampleInterval: SelfMonitoringState.SampleInterval? = nil,
        surfaceInTray: Bool? = nil,
        retentionMinutes: Int? = nil,
        exportEnabled: Bool? = nil
    ) {
        if let v = sampleInterval { preferences.sampleIntervalSeconds = v }
        if let v = surfaceInTray { preferences.surfaceInTray = v }
        if let v = retentionMinutes {
            preferences.retentionMinutes = v
            trimRingIfNeeded()
        }
        if let v = exportEnabled { preferences.exportEnabled = v }
        broadcastPrefs()
    }

    // MARK: Mutations — samples

    public func appendSample(_ sample: SelfMetricSample) {
        ringBuffer.append(sample)
        trimRingIfNeeded()
        broadcastSamples()
    }

    // MARK: Streams

    public func stateStream() -> AsyncStream<SelfMonitoringState> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.addPrefContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removePrefContinuation(key: key) }
            }
        }
    }

    public func samplesStream() -> AsyncStream<[SelfMetricSample]> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.addSampleContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeSampleContinuation(key: key) }
            }
        }
    }

    // MARK: Private

    private func trimRingIfNeeded() {
        let cap = max(1, (preferences.retentionMinutes * 60) / preferences.sampleIntervalSeconds.rawValue)
        if ringBuffer.count > cap {
            ringBuffer.removeFirst(ringBuffer.count - cap)
        }
    }

    private func addPrefContinuation(
        _ continuation: AsyncStream<SelfMonitoringState>.Continuation, key: UUID
    ) {
        continuation.yield(preferences)
        prefContinuations[key] = continuation
    }

    private func removePrefContinuation(key: UUID) {
        prefContinuations.removeValue(forKey: key)
    }

    private func addSampleContinuation(
        _ continuation: AsyncStream<[SelfMetricSample]>.Continuation, key: UUID
    ) {
        continuation.yield(ringBuffer)
        sampleContinuations[key] = continuation
    }

    private func removeSampleContinuation(key: UUID) {
        sampleContinuations.removeValue(forKey: key)
    }

    private func broadcastPrefs() {
        for cont in prefContinuations.values { cont.yield(preferences) }
    }

    private func broadcastSamples() {
        for cont in sampleContinuations.values { cont.yield(ringBuffer) }
    }
}
