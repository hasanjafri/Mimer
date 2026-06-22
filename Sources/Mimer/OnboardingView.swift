import SwiftUI

/// First-run welcome: teaches the hotkey + favorites, and offers (but never
/// forces) the auto-paste permission in context. The app is fully usable with
/// zero permissions — recall + manual ⌘V works immediately.
struct OnboardingView: View {
    let onDone: () -> Void

    @State private var canPaste = Paster.canPostEvents
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: glyphSize))
                .foregroundStyle(.tint)
            Text("Mimer remembers your clipboard")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Label("Press **⇧⌘V** anywhere to search and paste", systemImage: "command")
                Label("Click the menu-bar icon for recent clips", systemImage: "menubar.arrow.up.rectangle")
                Label("Press **⌘D** or the ★ to keep a clip forever", systemImage: "star")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-paste").font(.headline)
                    Text(canPaste
                         ? "Enabled — ⏎ pastes for you."
                         : "Optional: let ⏎ paste into the app you were in. Otherwise the clip is copied and you press ⌘V.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if canPaste {
                    Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Enable") {
                        Paster.requestPostEventAccess()
                        canPaste = Paster.canPostEvents
                    }
                }
            }

            Button("Get started", action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(28)
        .frame(width: 440)
    }
}
