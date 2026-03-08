import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Cameras")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Hello, World!")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
