import SwiftUI

// The heatmap's metric filter — Distance / Active min / Steps vs. goal. The
// primary control of the Progress card, so it sits directly under the title as a
// full-width segmented control.
struct HeatmapMetricPicker: View {
    @Binding var metric: HeatmapMetric

    var body: some View {
        Picker("Metric", selection: $metric) {
            ForEach(HeatmapMetric.allCases, id: \.self) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}
