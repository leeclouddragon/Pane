import AppKit
import Foundation

@main
struct ExportAppIcon {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let outputPath = arguments.first ?? "./AppIcon-preview.png"
        let size = arguments.count > 1 ? CGFloat(Int(arguments[1]) ?? 1024) : 1024
        let outputURL = URL(fileURLWithPath: outputPath)
        let image = AppIconArtwork.makeImage(size: size)

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            fputs("failed to encode app icon\n", stderr)
            exit(1)
        }

        try data.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }
}
