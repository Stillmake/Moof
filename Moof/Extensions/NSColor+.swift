import AppKit

extension NSColor {
    /// Construct a color from a three- or six-digit hex string.
    nonisolated convenience init(hex string: String) {
        var hex =
            string.hasPrefix("#")
            ? String(string.dropFirst())
            : string
        guard hex.count == 3 || hex.count == 6 else {
            assertionFailure("Invalid hex color length: \(string)")
            self.init(white: 1.0, alpha: 0.0)
            return
        }
        if hex.count == 3 {
            for (index, char) in hex.enumerated() {
                hex.insert(char, at: hex.index(hex.startIndex, offsetBy: index * 2))
            }
        }

        guard let intCode = Int(hex, radix: 16) else {
            assertionFailure("Invalid hex color: \(string)")
            self.init(white: 1.0, alpha: 0.0)
            return
        }

        self.init(
            red: CGFloat((intCode >> 16) & 0xFF) / 255.0,
            green: CGFloat((intCode >> 8) & 0xFF) / 255.0,
            blue: CGFloat(intCode & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var isDark: Bool {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let linearRed = red <= 0.04045 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4)
        let linearGreen = green <= 0.04045 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4)
        let linearBlue = blue <= 0.04045 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4)
        let relativeLuminance = 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
        let blackContrast = (relativeLuminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (relativeLuminance + 0.05)
        return whiteContrast > blackContrast
    }
}
