import AVFoundation
import SwiftUI
import UIKit

/// Vista cuya capa es un `AVCaptureVideoPreviewLayer`.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }
}

/// Inserta en SwiftUI una `CameraPreviewView` creada por el motor de captura.
struct CameraPreview: UIViewRepresentable {
    let preview: CameraPreviewView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if preview.superview !== container {
            attach(to: container)
        }
    }

    private func attach(to container: UIView) {
        preview.removeFromSuperview()
        preview.frame = container.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(preview)
    }
}
