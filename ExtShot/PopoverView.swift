import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ExtShot")
                .font(.headline)
                .padding(.top, 8)
            
            Button(action: {
                Task { @MainActor in
                    await ScreenshotManager.shared.takeScreenshot(size: CGSize(width: 1280, height: 800))
                }
            }) {
                HStack {
                    Text("Large (1280 x 800)")
                    Spacer()
                    Text("⌥1")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
            
            Button(action: {
                Task { @MainActor in
                    await ScreenshotManager.shared.takeScreenshot(size: CGSize(width: 640, height: 400))
                }
            }) {
                HStack {
                    Text("Small (640 x 400)")
                    Spacer()
                    Text("⌥2")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
        .padding()
    }
}
