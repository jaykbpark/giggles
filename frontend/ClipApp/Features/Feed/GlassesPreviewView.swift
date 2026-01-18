import SwiftUI
import Combine
import CoreVideo

/// Live preview of the video feed from connected Meta glasses.
/// Subscribes to MetaGlassesManager.videoFramePublisher and renders frames in real-time.
struct GlassesPreviewView: View {
    @StateObject private var viewModel = GlassesPreviewViewModel()
    
    var body: some View {
        Group {
            if let image = viewModel.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder when no frames available
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Waiting for feed...")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
            }
        }
        .frame(width: 120, height: 68) // 16:9 aspect ratio
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - View Model

@MainActor
final class GlassesPreviewViewModel: ObservableObject {
    @Published private(set) var currentImage: UIImage?
    
    private let glassesManager = MetaGlassesManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Reuse CIContext for GPU-accelerated performance
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    init() {
        setupSubscription()
    }
    
    private func setupSubscription() {
        print("📹 [GlassesPreview] Setting up video frame subscription...")
        print("📹 [GlassesPreview] Video streaming: \(glassesManager.isVideoStreaming)")
        
        glassesManager.videoFramePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pixelBuffer in
                guard let self = self else { return }
                if self.currentImage == nil {
                    print("📹 [GlassesPreview] Received first video frame!")
                }
                self.processFrame(pixelBuffer)
            }
            .store(in: &cancellables)
    }
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Convert CVPixelBuffer to UIImage via CIImage (GPU-accelerated)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            currentImage = UIImage(cgImage: cgImage)
        } else {
            print("⚠️ [GlassesPreview] Failed to create CGImage from pixel buffer")
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            HStack {
                Spacer()
                GlassesPreviewView()
                    .padding(.top, 70)
                    .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}
