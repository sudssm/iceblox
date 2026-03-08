import SwiftUI

struct SplashScreenView: View {
    var onStartCamera: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("CamerasApp")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Button(action: onStartCamera) {
                    Text("Start Camera")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
