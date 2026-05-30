import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Jot")
                .font(.headline)

            Button("Start Recording") {
                // TODO: begin session
            }
            .buttonStyle(.borderedProminent)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 280)
    }
}
