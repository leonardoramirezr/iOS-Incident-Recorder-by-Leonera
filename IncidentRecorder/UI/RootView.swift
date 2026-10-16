import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.hasCompletedOnboarding {
                MainCameraView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.hasCompletedOnboarding)
        .preferredColorScheme(.dark)
        .tint(.red)
    }
}
