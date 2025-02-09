import PhotosUI
import SwiftUI
import Translation

struct PhotoView: View {
    private let photoItem: PhotosPickerItem
    let sourceLanguage: Locale.Language

    @StateObject private var viewModel: PhotoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var imageSize: CGSize = .zero

    init(photoItem: PhotosPickerItem, sourceLanguage: Locale.Language) {
        self.photoItem = photoItem
        self.sourceLanguage = sourceLanguage
        _viewModel = StateObject(
            wrappedValue: PhotoViewModel(sourceLanguage: sourceLanguage)
        )
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .edgesIgnoringSafeArea(.all)

            if !viewModel.readyToDisplay {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                GeometryReader { geometry in
                    let size = calculatePhotoFrame(
                        photoSize: viewModel.processedPhoto.naturalSize ?? imageSize,
                        containerSize: geometry.size
                    )

                    // Container exactly matching photo frame
                    ZStack {
                        ZStack(alignment: .topLeading) {
                            if let image = viewModel.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size.width, height: size.height)
                            }

                            GeometryReader { _ in
                                viewModel.subtitleOverlay
                                    .frame(width: size.width, height: size.height)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            Task {
                await viewModel.cancelProcessing()
            }
        }
        .translationTask(
            TranslationSession.Configuration(
                source: sourceLanguage,
                target: viewModel.destinationLanguage
            ),
            action: { session in
                Task { @MainActor in
                    await viewModel.processPhoto(photoItem, translationSession: session)
                }
            }
        )
    }

    private func calculatePhotoFrame(photoSize: CGSize, containerSize: CGSize) -> CGSize {
        guard photoSize.width > 0 && photoSize.height > 0 else {
            return containerSize
        }

        let photoAspectRatio = photoSize.width / photoSize.height
        let screenAspectRatio = containerSize.width / containerSize.height

        if photoAspectRatio > screenAspectRatio {
            // Photo is wider than screen - fit to width
            return CGSize(
                width: containerSize.width,
                height: containerSize.width / photoAspectRatio
            )
        } else {
            // Photo is taller than screen - fit to height
            return CGSize(
                width: containerSize.height * photoAspectRatio,
                height: containerSize.height
            )
        }
    }
}
