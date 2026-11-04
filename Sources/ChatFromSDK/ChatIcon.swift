import UIKit

/// The icons an owner picks from under Deploy, drawn as the widget draws them. WIDGET_ICONS in libs/widget-icons.ts is where they come from.
enum ChatIcon {
    struct Shape {
        let d: String
        var fill = false
    }

    static let defaultName = "chat"

    static let all: [String: [Shape]] = [
        "chat": [Shape(d: "M20.5 11.5a8.5 8.5 0 0 1-12.2 7.65L3.5 20.5l1.35-4.55A8.5 8.5 0 1 1 20.5 11.5Z")],
        "typing": [
            Shape(d: "M20.5 11.5a8.5 8.5 0 0 1-12.2 7.65L3.5 20.5l1.35-4.55A8.5 8.5 0 1 1 20.5 11.5Z"),
            Shape(d: "M8.1 11.5a1.1 1.1 0 1 0 2.2 0 1.1 1.1 0 0 0-2.2 0Z", fill: true),
            Shape(d: "M10.9 11.5a1.1 1.1 0 1 0 2.2 0 1.1 1.1 0 0 0-2.2 0Z", fill: true),
            Shape(d: "M13.7 11.5a1.1 1.1 0 1 0 2.2 0 1.1 1.1 0 0 0-2.2 0Z", fill: true),
        ],
        "message": [Shape(d: "M5 4.5h14A2 2 0 0 1 21 6.5v8.5a2 2 0 0 1-2 2h-8.5L6 20.5V17H5a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2Z"), Shape(d: "M7.5 9h9"), Shape(d: "M7.5 12.5h5.5")],
        "sparkle": [Shape(d: "M11 3.5l1.9 5.1 5.1 1.9-5.1 1.9L11 17.5l-1.9-5.1L4 10.5l5.1-1.9Z"), Shape(d: "M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7Z")],
        "bot": [Shape(d: "M8 8.5h8a3 3 0 0 1 3 3V16a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3v-4.5a3 3 0 0 1 3-3Z"), Shape(d: "M12 8.5V5.5"), Shape(d: "M12 5.5h.01"), Shape(d: "M9.5 13.5h.01"), Shape(d: "M14.5 13.5h.01"), Shape(d: "M2.5 13v2"), Shape(d: "M21.5 13v2")],
        "help": [Shape(d: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z"), Shape(d: "M9.6 9.3a2.5 2.5 0 0 1 4.85.85c0 1.65-2.45 2.25-2.45 3.85"), Shape(d: "M12 17.2h.01")],
        "support": [
            Shape(d: "M4.5 13.5V12a7.5 7.5 0 0 1 15 0v1.5"),
            Shape(d: "M4.5 13.5H7a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1H6a1.5 1.5 0 0 1-1.5-1.5Z"),
            Shape(d: "M19.5 13.5H17a1 1 0 0 0-1 1V17a1 1 0 0 0 1 1h1a1.5 1.5 0 0 0 1.5-1.5Z"),
            Shape(d: "M19.5 16.5V17a3 3 0 0 1-3 3H13"),
        ],
        "mail": [Shape(d: "M4.5 5.5h15a1.5 1.5 0 0 1 1.5 1.5v10a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17V7a1.5 1.5 0 0 1 1.5-1.5Z"), Shape(d: "m3.5 7 8.5 6 8.5-6")],
    ]

    /// A speech bubble with a plus, as the web chat's header has for a new conversation.
    static let newChat: [Shape] = [Shape(d: "M20 13.5a2 2 0 0 1-2 2H9l-4 3.5V6a2 2 0 0 1 2-2h11a2 2 0 0 1 2 2zM12.5 7v5.5M9.75 9.75h5.5")]

    /// An icon as a template image, so whatever shows it gives it its colour. A name this SDK does not know yet is the chat bubble.
    static func image(_ name: String, size: CGFloat) -> UIImage {
        image(shapes: all[name] ?? all[defaultName]!, size: size)
    }

    static func image(shapes: [Shape], size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: size / 24, y: size / 24)
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            for shape in shapes {
                cg.addPath(SVGPath.make(shape.d))
                cg.drawPath(using: shape.fill ? .fill : .stroke)
            }
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// The part of SVG's path language the icons use, so they stay the same strings as the widget's.
enum SVGPath {
    static func make(_ d: String) -> CGPath {
        var reader = Reader(d)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"

        while reader.skipSeparators() {
            if let next = reader.command() {
                command = next
            }
            let relative = command.isLowercase
            let origin = relative ? current : .zero
            switch command.uppercased() {
            case "M":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                start = current
                path.move(to: current)
                // Any more pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addLine(to: current)
            case "H":
                guard let x = reader.number() else { return path }
                current.x = origin.x + x
                path.addLine(to: current)
            case "V":
                guard let y = reader.number() else { return path }
                current.y = origin.y + y
                path.addLine(to: current)
            case "C":
                guard let x1 = reader.number(), let y1 = reader.number(), let x2 = reader.number(), let y2 = reader.number(), let x = reader.number(), let y = reader.number() else { return path }
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: end, control1: CGPoint(x: origin.x + x1, y: origin.y + y1), control2: CGPoint(x: origin.x + x2, y: origin.y + y2))
                current = end
            case "A":
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(), let large = reader.flag(), let sweep = reader.flag(), let x = reader.number(), let y = reader.number() else { return path }
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
                // A close takes no numbers, so the next thing has to be a command.
                if reader.startsWithNumber() { return path }
            default:
                return path
            }
        }
        return path
    }

    /// An SVG arc as cubic curves, by the conversion in the SVG spec's implementation notes (F.6.5).
    private static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let (cosPhi, sinPhi) = (cos(phi), sin(phi))
        let dx = (p0.x - p1.x) / 2
        let dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = (large == sweep ? -1 : 1) * sqrt(numerator / denominator)
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        let theta1 = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var delta = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - theta1
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var angle = theta1
        for _ in 0..<segments {
            let next = angle + step
            let point = { (a: CGFloat, ox: CGFloat, oy: CGFloat) -> CGPoint in
                let x = rx * (cos(a) + ox)
                let y = ry * (sin(a) + oy)
                return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
            }
            path.addCurve(
                to: point(next, 0, 0),
                control1: point(angle, -t * sin(angle), t * cos(angle)),
                control2: point(next, t * sin(next), -t * cos(next))
            )
            angle = next
        }
    }

    private struct Reader {
        private let chars: [Character]
        private var i = 0

        init(_ text: String) {
            chars = Array(text)
        }

        /// False at the end of the path.
        mutating func skipSeparators() -> Bool {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i].isNewline {
                i += 1
            }
            return i < chars.count
        }

        mutating func command() -> Character? {
            guard i < chars.count, chars[i].isLetter else { return nil }
            defer { i += 1 }
            return chars[i]
        }

        func startsWithNumber() -> Bool {
            var j = i
            while j < chars.count, chars[j] == " " || chars[j] == "," {
                j += 1
            }
            return j < chars.count && !chars[j].isLetter
        }

        /// A flag is one digit, and may run straight into what follows it.
        mutating func flag() -> Bool? {
            guard skipSeparators(), chars[i] == "0" || chars[i] == "1" else { return nil }
            defer { i += 1 }
            return chars[i] == "1"
        }

        /// One number. "1.8.7" is two numbers and "8.5-6" is two as well, as SVG writes them.
        mutating func number() -> CGFloat? {
            guard skipSeparators() else { return nil }
            var text = ""
            if chars[i] == "-" || chars[i] == "+" {
                text.append(chars[i])
                i += 1
            }
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c == "." {
                    if seenDot { break }
                    seenDot = true
                } else if !c.isNumber {
                    break
                }
                text.append(c)
                i += 1
            }
            return Double(text).map { CGFloat($0) }
        }
    }
}
