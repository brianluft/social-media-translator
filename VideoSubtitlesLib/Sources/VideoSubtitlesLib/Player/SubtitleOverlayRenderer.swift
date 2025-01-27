import SwiftUI

@MainActor
public class SubtitleOverlayRenderer {
    public struct Style: Sendable {
        public let font: Font
        public let textColor: Color
        public let backgroundColor: Color
        public let cornerRadius: CGFloat
        public let padding: EdgeInsets

        public static let `default` = Style(
            font: .system(size: 16, weight: .medium),
            textColor: .white,
            backgroundColor: Color.black.opacity(0.7),
            cornerRadius: 4,
            padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        )

        public init(
            font: Font,
            textColor: Color,
            backgroundColor: Color,
            cornerRadius: CGFloat,
            padding: EdgeInsets
        ) {
            self.font = font
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.cornerRadius = cornerRadius
            self.padding = padding
        }
    }

    private let style: Style

    public init(style: Style = .default) {
        self.style = style
    }

    public func createSubtitleOverlay(for segments: [TranslatedSegment]) -> some View {
        ZStack {
            ForEach(segments) { [self] segment in
                Text(segment.translatedText)
                    .font(style.font)
                    .foregroundColor(style.textColor)
                    .padding(style.padding)
                    .background(style.backgroundColor)
                    .cornerRadius(style.cornerRadius)
                    .position(
                        x: segment.position.midX,
                        y: segment.position.midY
                    )
            }
        }
    }
}
