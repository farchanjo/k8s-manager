// Domain/Services/SelfMonitoringSampler.swift — app_shell bounded context
// DDD role: DomainService
// ADR ref: ADR-0027

import Darwin
import Foundation

// MARK: - MachMetricsReader

/// Wraps Darwin mach task APIs.  All functions are free (no retained state).
private enum MachMetricsReader {

    // MARK: Memory

    /// Returns resident memory in bytes from `MACH_TASK_BASIC_INFO`.
    static func residentMemoryBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return SelfMetricSample.unavailableSentinel }
        return Int(info.resident_size)
    }

    // MARK: CPU

    /// Returns (userMicros, systemMicros) accumulated since process start.
    ///
    /// Uses `mach_task_basic_info.user_time` + `system_time`.
    static func cpuTimeMicros() -> (user: UInt64, system: UInt64)? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user   = UInt64(info.user_time.seconds)   * 1_000_000 + UInt64(info.user_time.microseconds)
        let system = UInt64(info.system_time.seconds) * 1_000_000 + UInt64(info.system_time.microseconds)
        return (user, system)
    }

    // MARK: Threads

    /// Returns thread count via `task_threads`.
    ///
    /// Deallocates the port array to avoid a mach port leak.
    static func threadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let list = threadList else {
            return SelfMetricSample.unavailableSentinel
        }
        let count = Int(threadCount)
        let vmSize = vm_size_t(MemoryLayout<thread_t>.size) * vm_size_t(threadCount)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vmSize)
        return count
    }

    // MARK: File descriptors

    /// Counts open file descriptors using `proc_pidinfo(PROC_PIDLISTFDS)`.
    static func fileDescriptorCount() -> Int {
        let pid = getpid()
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return SelfMetricSample.unavailableSentinel }
        return Int(bufSize) / MemoryLayout<proc_fdinfo>.stride
    }
}

// MARK: - SelfMonitoringSampler

/// Domain service that periodically collects process metrics using Darwin mach
/// task APIs and pushes each `SelfMetricSample` into `SelfMonitoringStateAggregate`.
///
/// ### Threading
/// Actor serialises all mutable state.  CPU % is derived by diffing consecutive
/// `mach_task_basic_info` user+system time readings; the first sample reports 0.0.
///
/// ### Sandbox graceful degradation
/// Fields unavailable under the App Sandbox degrade to `SelfMetricSample.unavailableSentinel`.
public actor SelfMonitoringSampler {

    // MARK: Dependencies

    private let aggregate: SelfMonitoringStateAggregate
    private let intervalSeconds: Double

    // MARK: Mutable state

    private var samplingTask: Task<Void, Never>?
    private var previousCPUMicros: (user: UInt64, system: UInt64)?
    private var previousSampleDate: Date?

    // MARK: Init

    /// - Parameters:
    ///   - aggregate: The aggregate that owns the ring buffer.
    ///   - intervalSeconds: Sample cadence in seconds (default 30).
    public init(aggregate: SelfMonitoringStateAggregate, intervalSeconds: Double = 30) {
        self.aggregate = aggregate
        self.intervalSeconds = intervalSeconds
    }

    // MARK: Lifecycle

    /// Begins periodic sampling.  A second call cancels the previous task first.
    public func start() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// Cancels the sampling task.
    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    // MARK: Private

    private func runLoop() async {
        while !Task.isCancelled {
            let sample = collectSample()
            await aggregate.appendSample(sample)
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
        }
    }

    private func collectSample() -> SelfMetricSample {
        let now = Date()
        let rss     = MachMetricsReader.residentMemoryBytes()
        let threads = MachMetricsReader.threadCount()
        let fds     = MachMetricsReader.fileDescriptorCount()
        let cpu     = measureCPUPercent(at: now)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return SelfMetricSample(
            timestampRFC3339: formatter.string(from: now),
            cpuUsagePercent: cpu,
            memoryRSSBytes: rss,
            memoryPeakRSSBytes: rss,   // peak not separately exposed by MACH_TASK_BASIC_INFO
            threadCount: threads,
            fileDescriptorCount: fds,
            networkBytesIn: SelfMetricSample.unavailableSentinel,
            networkBytesOut: SelfMetricSample.unavailableSentinel,
            activeWatchStreams: SelfMetricSample.unavailableSentinel,
            activeExecSessions: SelfMetricSample.unavailableSentinel,
            activePortForwards: SelfMetricSample.unavailableSentinel,
            activeChatStreams: SelfMetricSample.unavailableSentinel,
            sqliteSizeBytes: SelfMetricSample.unavailableSentinel,
            cacheSizeBytes: SelfMetricSample.unavailableSentinel,
            actorCount: SelfMetricSample.unavailableSentinel,
            eventLoopGroupCount: SelfMetricSample.unavailableSentinel
        )
    }

    /// Computes CPU % by diffing cumulative mach task time against the previous reading.
    /// Returns 0.0 on the first call (no previous baseline).
    private func measureCPUPercent(at now: Date) -> Double {
        guard let ticks = MachMetricsReader.cpuTimeMicros() else { return 0.0 }

        defer {
            previousCPUMicros  = ticks
            previousSampleDate = now
        }

        guard
            let prev = previousCPUMicros,
            let prevDate = previousSampleDate
        else {
            return 0.0
        }

        let wallMicros = now.timeIntervalSince(prevDate) * 1_000_000
        guard wallMicros > 0 else { return 0.0 }

        let deltaTicks = Double((ticks.user + ticks.system) - (prev.user + prev.system))
        return min(100.0 * deltaTicks / wallMicros, 100.0)
    }
}
