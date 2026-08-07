import CoreImage.CIFilterBuiltins
import AppKit
import SwiftUI

// Renders the LAN pairing URL as a QR code for the iOS companion app.
struct QRCodeView: View {
    let text: String
    let size: CGFloat
    // 监听共享字体偏好，保证二维码异常文案与应用其他文字一致。
    @ObservedObject private var fontSettings = FontSettings.shared

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = qrImage() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(text.isEmpty ? "二维码生成失败" : text)
                    .font(fontSettings.font(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: size, height: size)
            }
        }
    }

    // Converts the UTF-8 pairing URL into a high-contrast NSImage suitable for scanning.
    private func qrImage() -> NSImage? {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return nil }
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
