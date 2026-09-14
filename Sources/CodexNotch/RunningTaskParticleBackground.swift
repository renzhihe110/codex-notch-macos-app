import SwiftUI

// 使用单个时间轴和 Canvas 绘制五种运行态效果，避免为每颗粒子创建独立 SwiftUI 视图。
struct RunningTaskParticleBackground: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let effect: RunningParticleEffect

    private let amber = Color(red: 0.941, green: 0.725, blue: 0.325)
    private let cyan = Color(red: 0.404, green: 0.847, blue: 1.000)
    private let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)

    // 原彗星矩阵沿用固定粒子参数，确保密度、拖尾长度和刷新后的分布与旧版一致。
    private static let cometParticles: [CometParticle] = [
        CometParticle(verticalPosition: 0.16, delay: 0.00, duration: 2.50, trailLength: 24, thickness: 1.4, isEmerald: false),
        CometParticle(verticalPosition: 0.31, delay: 0.23, duration: 2.50, trailLength: 18, thickness: 1.2, isEmerald: false),
        CometParticle(verticalPosition: 0.47, delay: 0.46, duration: 2.50, trailLength: 28, thickness: 1.5, isEmerald: true),
        CometParticle(verticalPosition: 0.68, delay: 0.69, duration: 2.50, trailLength: 20, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.82, delay: 0.92, duration: 2.50, trailLength: 26, thickness: 1.4, isEmerald: false),
        CometParticle(verticalPosition: 0.24, delay: 1.15, duration: 2.50, trailLength: 16, thickness: 1.1, isEmerald: true),
        CometParticle(verticalPosition: 0.57, delay: 1.38, duration: 2.50, trailLength: 22, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.75, delay: 1.61, duration: 2.50, trailLength: 30, thickness: 1.5, isEmerald: false),
        CometParticle(verticalPosition: 0.39, delay: 1.84, duration: 2.50, trailLength: 19, thickness: 1.2, isEmerald: true),
        CometParticle(verticalPosition: 0.90, delay: 2.07, duration: 2.50, trailLength: 24, thickness: 1.3, isEmerald: false),
        CometParticle(verticalPosition: 0.10, delay: 2.30, duration: 2.50, trailLength: 21, thickness: 1.2, isEmerald: false)
    ]

    @ViewBuilder var body: some View {
        if accessibilityReduceMotion {
            particleLayer(elapsed: effect == .comet ? 0.92 : 3.6)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                particleLayer(elapsed: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    // Canvas 统一启用 screen 混合；极光使用四倍时间轴，轨道和星火使用两倍时间轴。
    private func particleLayer(elapsed: TimeInterval) -> some View {
        Canvas { context, size in
            var particleContext = context
            particleContext.blendMode = .screen
            switch effect {
            case .comet:
                drawComet(in: context, size: size, elapsed: elapsed)
            case .silk:
                drawSilk(in: particleContext, size: size, elapsed: elapsed)
            case .aurora:
                drawAurora(in: particleContext, size: size, elapsed: elapsed * 4)
            case .orbit:
                drawOrbit(in: particleContext, size: size, elapsed: elapsed * 2)
            case .edge:
                drawEdge(in: particleContext, size: size, elapsed: elapsed * 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // 彗星矩阵原样保留扫描光带、双色拖尾和粒子头，作为速度感最强的经典效果。
    private func drawComet(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let scanProgress = CGFloat(elapsed.truncatingRemainder(dividingBy: 2.5) / 2.5)
        let scanWidth = max(48, size.width * 0.28)
        let scanX = -scanWidth + (size.width + scanWidth * 2) * scanProgress
        var scanPath = Path()
        scanPath.move(to: CGPoint(x: scanX + scanWidth * 0.18, y: 0))
        scanPath.addLine(to: CGPoint(x: scanX + scanWidth, y: 0))
        scanPath.addLine(to: CGPoint(x: scanX + scanWidth * 0.82, y: size.height))
        scanPath.addLine(to: CGPoint(x: scanX, y: size.height))
        scanPath.closeSubpath()
        context.fill(scanPath, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: amber.opacity(0.04), location: 0.24), .init(color: amber.opacity(0.16), location: 0.64), .init(color: .clear, location: 1)]), startPoint: CGPoint(x: scanX, y: size.height / 2), endPoint: CGPoint(x: scanX + scanWidth, y: size.height / 2)))

        for particle in Self.cometParticles {
            let progress = CGFloat((elapsed + particle.delay).truncatingRemainder(dividingBy: particle.duration) / particle.duration)
            let headX = -particle.trailLength + (size.width + particle.trailLength * 2) * progress
            let drift = CGFloat(sin((elapsed + particle.delay) * 1.6)) * 1.6 + (0.5 - progress) * 8
            let headY = particle.verticalPosition * size.height + drift
            let fadeIn = min(1, progress / 0.12)
            let fadeOut = min(1, (1 - progress) / 0.18)
            let opacity = max(0, min(fadeIn, fadeOut))
            let color = particle.isEmerald ? emerald : amber
            let trailStart = CGPoint(x: headX - particle.trailLength, y: headY)
            let trailEnd = CGPoint(x: headX, y: headY)
            var trailPath = Path()
            trailPath.move(to: trailStart)
            trailPath.addLine(to: trailEnd)

            var glowContext = context
            glowContext.opacity = Double(opacity * 0.14)
            glowContext.stroke(trailPath, with: .color(color), style: StrokeStyle(lineWidth: particle.thickness + 2, lineCap: .round))

            var trailContext = context
            trailContext.opacity = Double(opacity)
            trailContext.stroke(trailPath, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.34), location: 0.52), .init(color: color, location: 1)]), startPoint: trailStart, endPoint: trailEnd), style: StrokeStyle(lineWidth: particle.thickness, lineCap: .round))
            trailContext.fill(Path(ellipseIn: CGRect(x: headX - 1.3, y: headY - 1.3, width: 2.6, height: 2.6)), with: .color(color))
        }
    }

    // 金线流光以四条低振幅曲线表达处理方向，亮点只承担节拍提示。
    private func drawSilk(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let rows: [CGFloat] = [0.23, 0.39, 0.58, 0.76]
        for (index, row) in rows.enumerated() {
            let phase = elapsed * (0.22 + Double(index) * 0.018) + Double(index) * 0.21
            let head = unitProgress(phase)
            let color = index == 2 ? cyan : amber
            let amplitude = 1.5 + CGFloat(index) * 0.34
            var path = Path()
            for step in 0...40 {
                let stepProgress = CGFloat(step) / 40
                let envelope = CGFloat(sin(Double.pi * Double(stepProgress)))
                let y = size.height * row + CGFloat(sin(Double(step) * 0.32 + phase * Double.pi * 2)) * amplitude * envelope
                let point = CGPoint(x: size.width * stepProgress, y: y)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let headX = size.width * head
            let headY = size.height * row + CGFloat(sin(Double(head * 40) * 0.32 + phase * Double.pi * 2)) * amplitude * CGFloat(sin(Double.pi * Double(head)))
            let gradient = Gradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.08), location: 0.42), .init(color: color.opacity(0.42), location: 0.62), .init(color: .clear, location: 1)])
            context.stroke(path, with: .linearGradient(gradient, startPoint: CGPoint(x: headX - size.width * 0.22, y: headY), endPoint: CGPoint(x: headX + size.width * 0.16, y: headY)), style: StrokeStyle(lineWidth: index == 2 ? 1.05 : 0.72, lineCap: .round, lineJoin: .round))
            drawGlowDot(in: context, center: CGPoint(x: headX, y: headY), radius: index == 2 ? 1.15 : 0.82, color: color, opacity: 0.76)
        }
    }

    // 极光微尘用两层冷暖柔光缓慢呼吸，并以十二颗固定微尘补充深度。
    private func drawAurora(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let centers = [
            (CGPoint(x: size.width * (0.25 + CGFloat(sin(elapsed * 0.17)) * 0.08), y: size.height * 0.72), amber),
            (CGPoint(x: size.width * (0.72 + CGFloat(cos(elapsed * 0.13)) * 0.09), y: size.height * 0.24), cyan)
        ]
        var cardPath = Path()
        cardPath.addRect(CGRect(origin: .zero, size: size))
        for (center, color) in centers {
            let gradient = Gradient(stops: [.init(color: color.opacity(0.11), location: 0), .init(color: color.opacity(0.038), location: 0.45), .init(color: .clear, location: 1)])
            context.fill(cardPath, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: max(40, size.width * 0.25)))
        }
        for index in 0..<12 {
            let progress = unitProgress(Double(seed(index, salt: 0)) + elapsed * Double(0.012 + seed(index, salt: 1) * 0.014))
            let y = (seed(index, salt: 2) * 0.82 + 0.09 + CGFloat(sin(elapsed * 0.7 + Double(index))) * 0.025) * size.height
            let pulse = 0.24 + CGFloat(sin(elapsed * 1.4 + Double(seed(index, salt: 3)) * 8)) * 0.12
            let color = seed(index, salt: 4) > 0.72 ? cyan : amber
            drawGlowDot(in: context, center: CGPoint(x: progress * size.width, y: y), radius: 0.55 + seed(index, salt: 0) * 0.52, color: color, opacity: pulse)
        }
    }

    // 磁场轨道让九颗粒子沿三条隐形缓弧穿行，并仅在头部附近保留短轨迹。
    private func drawOrbit(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let tracks: [CGFloat] = [0.25, 0.50, 0.75]
        for (trackIndex, row) in tracks.enumerated() {
            for particleIndex in 0..<3 {
                let seedIndex = trackIndex * 3 + particleIndex
                let speed = 0.075 + Double(trackIndex) * 0.009 + Double(particleIndex) * 0.006
                let progress = unitProgress(Double(seed(seedIndex, salt: 5)) + elapsed * speed)
                let color = trackIndex == 1 && particleIndex == 1 ? cyan : amber
                func point(offset: CGFloat) -> CGPoint {
                    let value = progress - offset
                    let y = size.height * row + CGFloat(sin(Double(value) * Double.pi * 2 + Double(trackIndex) * 1.7)) * (2.4 + CGFloat(trackIndex) * 0.5)
                    return CGPoint(x: value * size.width, y: y)
                }
                var trailPath = Path()
                for step in stride(from: 7, through: 0, by: -1) {
                    let point = point(offset: CGFloat(step) * 0.012)
                    if step == 7 { trailPath.move(to: point) } else { trailPath.addLine(to: point) }
                }
                let head = point(offset: 0)
                let gradient = Gradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.46), location: 1)])
                context.stroke(trailPath, with: .linearGradient(gradient, startPoint: CGPoint(x: head.x - size.width * 0.09, y: head.y), endPoint: head), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                drawGlowDot(in: context, center: head, radius: 0.86, color: color, opacity: 0.72)
            }
        }
    }

    // 边缘星火把十四颗短拖尾限制在上下边缘，中央文字区始终保持安静。
    private func drawEdge(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        for index in 0..<14 {
            let speed = 0.035 + Double(seed(index, salt: 0)) * 0.055
            let progress = unitProgress(Double(seed(index, salt: 1)) + elapsed * speed)
            let isTop = seed(index, salt: 2) > 0.5
            let x = progress * (size.width + 30) - 15
            let inset = 2.2 + seed(index, salt: 3) * 6.5
            let y = isTop ? inset : size.height - inset
            let color = seed(index, salt: 4) > 0.82 ? cyan : amber
            let length = 7 + seed(index, salt: 0) * 13
            let start = CGPoint(x: x - length, y: y + (isTop ? 1.5 : -1.5))
            let end = CGPoint(x: x, y: y)
            var trailPath = Path()
            trailPath.move(to: start)
            trailPath.addLine(to: end)
            let gradient = Gradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.5), location: 1)])
            context.stroke(trailPath, with: .linearGradient(gradient, startPoint: start, endPoint: end), style: StrokeStyle(lineWidth: 0.55 + seed(index, salt: 3) * 0.42, lineCap: .round))
            drawGlowDot(in: context, center: end, radius: 0.58 + seed(index, salt: 0) * 0.38, color: color, opacity: 0.66)
        }
        var edgePath = Path()
        edgePath.move(to: CGPoint(x: 0, y: 0.5))
        edgePath.addLine(to: CGPoint(x: size.width, y: 0.5))
        edgePath.move(to: CGPoint(x: 0, y: size.height - 0.5))
        edgePath.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        let gradient = Gradient(stops: [.init(color: .clear, location: 0), .init(color: amber.opacity(0.12), location: 0.48), .init(color: .clear, location: 1)])
        context.stroke(edgePath, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 0.55)
    }

    // 光点使用两层圆形模拟柔光，避免昂贵模糊滤镜影响多个运行任务同时刷新。
    private func drawGlowDot(in context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, opacity: CGFloat) {
        var glowContext = context
        glowContext.opacity = Double(opacity * 0.22)
        glowContext.fill(Path(ellipseIn: CGRect(x: center.x - radius * 4, y: center.y - radius * 4, width: radius * 8, height: radius * 8)), with: .color(color))
        var dotContext = context
        dotContext.opacity = Double(min(1, opacity * 1.4))
        dotContext.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    // 简单整数混合为每颗粒子生成稳定参数，避免刷新时重新随机分布。
    private func seed(_ index: Int, salt: Int) -> CGFloat {
        let mixed = UInt64(index + 1) * 1_103_515_245 + UInt64(salt + 1) * 12_345
        return CGFloat(mixed % 1_009) / 1_009
    }

    // 所有循环动画共用 0 到 1 的正向进度归一化。
    private func unitProgress(_ value: Double) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return CGFloat(remainder < 0 ? remainder + 1 : remainder)
    }
}

// 彗星参数只描述旧版固定粒子的轨迹和样式，不参与其他四种效果。
private struct CometParticle {
    let verticalPosition: CGFloat
    let delay: TimeInterval
    let duration: TimeInterval
    let trailLength: CGFloat
    let thickness: CGFloat
    let isEmerald: Bool
}
