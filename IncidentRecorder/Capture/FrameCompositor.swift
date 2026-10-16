import CoreImage
import CoreVideo
import ImageIO
import Metal
import UIKit

/// Compone cada cuadro del video final: cámara trasera a pantalla completa, cámara
/// frontal en un recuadro arriba a la derecha y los textos (hora/coordenadas) arriba
/// a la izquierda. Se usa siempre desde la misma cola.
final class FrameCompositor {
    let outputSize: CGSize

    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let overlay = OverlayRenderer()

    init(outputSize: CGSize) {
        self.outputSize = outputSize
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    func render(back: CVPixelBuffer, front: CVPixelBuffer?, overlayLines: [String], pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let canvas = CGRect(origin: .zero, size: outputSize)
        var image = Self.aspectFill(Self.upright(CIImage(cvPixelBuffer: back)), in: canvas)

        if let front {
            image = pictureInPicture(Self.upright(CIImage(cvPixelBuffer: front))).composited(over: image)
        }
        if let text = overlay.image(lines: overlayLines, canvas: outputSize) {
            image = text.composited(over: image)
        }

        var output: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard status == kCVReturnSuccess, let output else { return nil }
        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: colorSpace)
        return output
    }

    /// Si la conexión no pudo rotar el cuadro, lo giramos aquí para tener video vertical.
    private static func upright(_ image: CIImage) -> CIImage {
        image.extent.width > image.extent.height ? image.oriented(.right) : image
    }

    private static func aspectFill(_ image: CIImage, in rect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let dx = rect.midX - scaledExtent.midX
        let dy = rect.midY - scaledExtent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
    }

    private func pictureInPicture(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let width = (outputSize.width * 0.30).rounded()
        let scale = width / extent.width
        let height = (extent.height * scale).rounded()
        let margin = (outputSize.width * 0.03).rounded()
        // Core Image tiene el origen abajo a la izquierda.
        let frame = CGRect(
            x: outputSize.width - margin - width,
            y: outputSize.height - margin - height,
            width: width,
            height: height
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let placed = scaled
            .transformed(by: CGAffineTransform(translationX: frame.minX - scaled.extent.minX, y: frame.minY - scaled.extent.minY))
            .cropped(to: frame)
        let border = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            .cropped(to: frame.insetBy(dx: -4, dy: -4))
        return placed.composited(over: border)
    }
}

/// Dibuja los textos sobre el video. Solo vuelve a dibujar cuando el texto cambia
/// (una vez por segundo), no en cada cuadro.
final class OverlayRenderer {
    private var cachedKey: String?
    private var cachedCanvas: CGSize = .zero
    private var cachedImage: CIImage?

    func image(lines: [String], canvas: CGSize) -> CIImage? {
        guard !lines.isEmpty else { return nil }
        let key = lines.joined(separator: "\n")
        if key == cachedKey, canvas == cachedCanvas {
            return cachedImage
        }

        let fontSize = (canvas.width * 0.034).rounded()
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .shadow: shadow,
        ]
        let padding = (fontSize * 0.45).rounded()
        let lineHeight = ceil(font.lineHeight)
        let textWidth = lines.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        let boxSize = CGSize(
            width: textWidth + padding * 2,
            height: lineHeight * CGFloat(lines.count) + padding * 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: boxSize, format: format).image { _ in
            UIColor(white: 0, alpha: 0.5).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: boxSize), cornerRadius: fontSize * 0.3).fill()
            for (index, line) in lines.enumerated() {
                let origin = CGPoint(x: padding, y: padding + CGFloat(index) * lineHeight)
                (line as NSString).draw(at: origin, withAttributes: attributes)
            }
        }
        guard let cgImage = rendered.cgImage else { return nil }

        let margin = (canvas.width * 0.03).rounded()
        let image = CIImage(cgImage: cgImage).transformed(
            by: CGAffineTransform(translationX: margin, y: canvas.height - margin - boxSize.height)
        )
        cachedKey = key
        cachedCanvas = canvas
        cachedImage = image
        return image
    }
}
