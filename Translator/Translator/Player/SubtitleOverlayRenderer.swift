import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Renders subtitle overlays on video frames with customizable styling
@MainActor
public class SubtitleOverlayRenderer {
    /// Defines the visual appearance of subtitle overlays
    public struct Style: Sendable {
        public let font: Font
        public let textColor: Color
        public let backgroundColor: Color
        public let cornerRadius: CGFloat
        public let padding: EdgeInsets

        /// Default style for subtitle overlays
        public static let `default` = Style(
            font: .system(size: 16, weight: .medium),
            textColor: .white,
            backgroundColor: Color.black.opacity(0.7),
            cornerRadius: 4,
            padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        )

        /// Creates a new subtitle style configuration
        /// - Parameters:
        ///   - font: The font to use for subtitle text
        ///   - textColor: The color of the subtitle text
        ///   - backgroundColor: The background color behind subtitles
        ///   - cornerRadius: The corner radius of the subtitle background
        ///   - padding: The padding around subtitle text
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
    private var textSizeCache: [String: CGSize] = [:]

    /// Creates a new subtitle overlay renderer
    /// - Parameter style: The style configuration for rendering subtitles
    public init(style: Style = .default) {
        self.style = style
    }

    private func measureText(_ text: String) -> CGSize {
        if let cached = textSizeCache[text] {
            return cached
        }

        #if os(iOS)
        let systemFont = UIFont.systemFont(ofSize: 16, weight: .medium)
        #else
        let systemFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        #endif

        let size = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: systemFont],
            context: nil
        ).size

        // Add padding
        let paddedSize = CGSize(
            width: size.width + style.padding.leading + style.padding.trailing,
            height: size.height + style.padding.top + style.padding.bottom
        )

        textSizeCache[text] = paddedSize
        return paddedSize
    }

    private func adjustPosition(
        _ originalPosition: CGPoint,
        size: CGSize,
        in bounds: CGSize,
        avoiding occupiedRects: inout [CGRect]
    ) -> CGPoint {
        var position = originalPosition

        // Create rect for this subtitle
        let rect = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // Keep subtitle on screen
        if rect.minX < 0 {
            position.x = size.width / 2
        } else if rect.maxX > bounds.width {
            position.x = bounds.width - size.width / 2
        }

        if rect.minY < 0 {
            position.y = size.height / 2
        } else if rect.maxY > bounds.height {
            position.y = bounds.height - size.height / 2
        }

        // Avoid overlaps by shifting vertically
        var adjustedRect = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        while occupiedRects.contains(where: { $0.intersects(adjustedRect) }) {
            // Try moving up first since subtitles are usually at bottom
            position.y -= size.height + 4 // Add small gap

            // If moving up puts us off screen, try moving down instead
            if position.y - size.height / 2 < 0 {
                position.y = originalPosition.y + size.height + 4
            }

            adjustedRect = CGRect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        occupiedRects.append(adjustedRect)
        return position
    }

    /// Creates a SwiftUI view that renders the provided text segments as subtitle overlays
    /// - Parameter segments: Array of tuples containing text segments and their translated text
    /// - Returns: A SwiftUI view that can be overlaid on a video player
    public func createSubtitleOverlay(for segments: [(segment: TextSegment, text: String)]) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Sort segments by vertical position (higher y = lower in frame = higher z-index)
                // Use horizontal position as tiebreaker (right = higher z-index)
                let sortedSegments = segments.sorted { first, second in
                    if first.segment.position.midY == second.segment.position.midY {
                        return first.segment.position.midX < second.segment.position.midX
                    }
                    return first.segment.position.midY < second.segment.position.midY
                }

                ForEach(sortedSegments, id: \.segment.id) { [self] segment in
                    let textSize = measureText(segment.text)
                    let originalPosition = CGPoint(
                        x: segment.segment.position.midX * geometry.size.width,
                        y: segment.segment.position.midY * geometry.size.height
                    )

                    // Store and adjust positions to prevent overlaps
                    var occupiedRects: [CGRect] = []
                    let adjustedPosition = adjustPosition(
                        originalPosition,
                        size: textSize,
                        in: geometry.size,
                        avoiding: &occupiedRects
                    )

                    Text(segment.text)
                        .font(style.font)
                        .foregroundColor(style.textColor)
                        .padding(style.padding)
                        .background(style.backgroundColor)
                        .cornerRadius(style.cornerRadius)
                        .position(adjustedPosition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Renders subtitle overlays on photos with text forced to fit within original bounds
@MainActor
public class PhotoSubtitleOverlayRenderer {
    /// Defines the visual appearance of subtitle overlays
    public struct Style: Sendable {
        /// The font used for subtitle text
        public let font: Font
        /// The color of the subtitle text
        public let textColor: Color
        /// The background color behind subtitles
        public let backgroundColor: Color
        /// The corner radius of the subtitle background
        public let cornerRadius: CGFloat
        /// The padding around subtitle text
        public let padding: EdgeInsets

        /// Default style for subtitle overlays
        public static let `default` = Style(
            font: .system(size: 16, weight: .medium),
            textColor: .white,
            backgroundColor: Color.black.opacity(0.7),
            cornerRadius: 2,
            padding: EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
        )

        /// Creates a new subtitle overlay renderer for photos
        /// - Parameter style: The style configuration for rendering subtitles
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

    /// Creates a new subtitle overlay renderer for photos
    /// - Parameter style: The style configuration for rendering subtitles
    public init(style: Style = .default) {
        self.style = style
    }

    /// Creates a SwiftUI view that renders the provided text segments as subtitle overlays
    /// - Parameter segments: Array of tuples containing text segments and their translated text
    /// - Returns: A SwiftUI view that can be overlaid on a photo
    public func createSubtitleOverlay(for segments: [(segment: TextSegment, text: String)]) -> some View {
        GeometryReader { [self] geometry in
            ZStack {
                // Sort segments by vertical position (higher y = lower in frame = higher z-index)
                // Use horizontal position as tiebreaker (right = higher z-index)
                let sortedSegments = segments.sorted { first, second in
                    if first.segment.position.midY == second.segment.position.midY {
                        return first.segment.position.midX < second.segment.position.midX
                    }
                    return first.segment.position.midY < second.segment.position.midY
                }

                ForEach(sortedSegments, id: \.segment.id) { segment in
                    let rect = CGRect(
                        x: segment.segment.position.minX * geometry.size.width,
                        y: segment.segment.position.minY * geometry.size.height,
                        width: segment.segment.position.width * geometry.size.width,
                        height: segment.segment.position.height * geometry.size.height
                    )

                    Text(segment.text)
                        .font(self.style.font)
                        .foregroundColor(self.style.textColor)
                        .padding(self.style.padding)
                        .background(self.style.backgroundColor)
                        .cornerRadius(self.style.cornerRadius)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .minimumScaleFactor(0.1) // Allow text to scale down to fit
                        .lineLimit(1) // Force single line
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
