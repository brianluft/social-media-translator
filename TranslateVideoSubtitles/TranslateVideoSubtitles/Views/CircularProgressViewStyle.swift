import SwiftUI

struct CircularProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .trim(from: 0.0, to: CGFloat(configuration.fractionCompleted ?? 0))
            .stroke(style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
            .foregroundColor(.blue)
            .rotationEffect(.degrees(-90))
            .frame(width: 24, height: 24)
            .animation(.linear, value: configuration.fractionCompleted)
            .background(
                Circle()
                    .stroke(lineWidth: 3.0)
                    .opacity(0.3)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
            )
    }
}
