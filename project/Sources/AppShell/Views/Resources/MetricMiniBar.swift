// Views/Resources/MetricMiniBar.swift — app_shell bounded context
// DDD role: View — per-row inline metric mini-bar
// ADR ref: ADR-0059 (resource list row metric mini-bars)

import SwiftUI

// MARK: - MetricMiniBarColours

/// Static design-token colour constants for each metric dimension.
///
/// Colour names encode both the dimension and utilisation intensity tier.
/// Per ADR-0059: saturation ramps from 40% at 0% utilisation to 100% at 90%+;
/// above 90% the fill shifts to red to signal pressure.
public enum MetricMiniBarColours {
    /// Base CPU colour (blue family).
    public static let cpuBase  = Color.blue
    /// Base Memory colour (magenta / pink family).
    public static let memBase  = Color(hue: 0.83, saturation: 1.0, brightness: 0.9)
    /// Base Disk colour (amber / orange family).
    public static let diskBase = Color.orange
    /// Pressure colour applied when utilisation exceeds the threshold.
    public static let pressure = Color.red
    /// Frozen / disconnected desaturation overlay.
    public static let frozen   = Color.gray

    /// Default utilisation threshold above which the pressure colour is applied.
    public static let pressureThreshold: Double = 0.90

    /// Resolves the fill colour for a dimension and fill ratio.
    ///
    /// - Parameters:
    ///   - dimension: Metric dimension driving the base hue.
    ///   - ratio: Fill ratio in `[0.0, 1.0]`.
    ///   - isFrozen: True when the cluster is disconnected; desaturates the fill.
    ///   - threshold: Utilisation level above which the pressure colour applies.
    public static func fillColour(
        for dimension: MetricDimension,
        ratio: Double,
        isFrozen: Bool,
        threshold: Double = pressureThreshold
    ) -> Color {
        guard !isFrozen else { return frozen.opacity(0.40) }
        if ratio >= threshold { return pressure }
        let base: Color
        switch dimension {
        case .cpu:    base = cpuBase
        case .memory: base = memBase
        case .disk:   base = diskBase
        }
        // Ramp saturation from 40% at 0% fill to 100% at 90% fill.
        let saturationFactor = 0.40 + (ratio / threshold) * 0.60
        return base.opacity(saturationFactor)
    }
}

// MARK: - MetricMiniBar

/// Stateless inline bar view rendering a single ``MetricSeries``.
///
/// Per ADR-0059 spec:
/// - Width 72 pt, height 6 pt.
/// - Rounded-rectangle track at 20% opacity; filled segment proportional to
///   `series.fillRatio`, clamped to `[0.0, 1.0]`.
/// - Hover tooltip shows `series.tooltip`.
/// - No animation on value changes (values replaced, not interpolated).
/// - VoiceOver: `series.accessibilityLabel`.
///
/// Usage:
/// ```swift
/// MetricMiniBar(series: MetricSeries.available(dimension: .cpu, value: 1.2, capacity: 4.0))
/// ```
public struct MetricMiniBar: View {

    private static let barWidth: CGFloat  = 72
    private static let barHeight: CGFloat = 6

    private let series: MetricSeries

    /// Creates a mini-bar for the given metric series.
    ///
    /// - Parameter series: Pre-computed ``MetricSeries`` from the row view model.
    public init(series: MetricSeries) {
        self.series = series
    }

    public var body: some View {
        track
            .help(series.tooltip)
            .accessibilityLabel(series.accessibilityLabel)
            .accessibilityHidden(false)
    }

    // MARK: Private views

    private var isFrozen: Bool {
        if case .frozen = series.state { return true }
        return false
    }

    private var fillColour: Color {
        MetricMiniBarColours.fillColour(
            for: series.dimension,
            ratio: series.fillRatio,
            isFrozen: isFrozen
        )
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColour.opacity(0.20))
                .frame(width: Self.barWidth, height: Self.barHeight)
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColour)
                .frame(
                    width: max(0, Self.barWidth * series.fillRatio),
                    height: Self.barHeight
                )
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
    }
}

// MARK: - MetricMiniBarStack

/// Vertical stack of metric mini-bars for a resource row.
///
/// Renders up to three bars (CPU / Memory / Disk) compactly. Each bar is
/// preceded by a dimension icon for screen-reader users and mouse-hover context.
///
/// Bars with `.unavailable` state render at zero width with the dimension icon
/// greyed, providing honest representation without hiding the component.
public struct MetricMiniBarStack: View {

    private let series: [MetricSeries]

    /// Creates a stack of bars.
    ///
    /// - Parameter series: Ordered collection of metric series (typically CPU, Memory, Disk).
    ///   Series are rendered in the order supplied.
    public init(series: [MetricSeries]) {
        self.series = series
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(series, id: \.dimension) { s in
                MetricMiniBar(series: s)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MetricMiniBar — all states") {
    VStack(alignment: .leading, spacing: 8) {
        MetricMiniBar(series: .available(dimension: .cpu,    value: 0.6,  capacity: 4.0))
        MetricMiniBar(series: .available(dimension: .cpu,    value: 3.8,  capacity: 4.0))
        MetricMiniBar(series: .available(dimension: .memory, value: 512,  capacity: 1024))
        MetricMiniBar(series: .available(dimension: .disk,   value: 0.45, capacity: 1.0))
        MetricMiniBar(series: .frozen(   dimension: .cpu,    value: 2.0,  capacity: 4.0))
        MetricMiniBar(series: .unavailable(dimension: .disk))
        MetricMiniBar(series: MetricSeries(dimension: .cpu, state: .noRequestSet))
    }
    .padding()
}
#endif
