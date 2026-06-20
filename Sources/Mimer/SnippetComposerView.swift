import SwiftUI

/// Compose a reusable snippet. Kept forever; surfaced in the palette's Snippets section.
struct SnippetComposerView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Snippet").font(.headline)
            Text("Reusable text, kept forever. Find it in ⇧⌘V under Snippets.")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 150)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Snippet") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
    }
}
