import SwiftUI

/// The onboarding personalization forwarded to the coach.
///
/// This is the section people forget they filled in — it was collected once,
/// screens away, and then quietly travels with every question. Saying "you
/// shared this during onboarding" reconnects the data to the moment it was
/// given, which is the difference between a disclosure and a reminder.
struct CoachPreviewAboutYouCard: View {
    let profile: CoachProfile?

    var body: some View {
        CardSection(title: "About you") {
            if let profile, !profile.isEmpty {
                VStack(spacing: 0) {
                    CoachDataRow(label: "Walking habit", value: profile.walkVolume?.label)
                    CoachDataRow(label: "Usual time of day", value: profile.walkTime?.label)
                    CoachDataRow(label: "Other training",
                                 value: profile.otherTraining.isEmpty
                                 ? nil
                                 : profile.otherTraining.map(\.label).joined(separator: ", "))
                    CoachDataRow(label: "Training phase", value: profile.trainingPhase?.label)
                }
                Text("You shared this during onboarding. Everything here is optional.")
                    .font(Typography.caption).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not shared — you haven't told Buddy anything about your routine.")
                    .font(Typography.callout).foregroundColor(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
