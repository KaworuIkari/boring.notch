//
//  ClaudePetView.swift
//  boringNotch
//
//  A pixel-art creature that lives in the notch and reacts to Claude Code.
//
//  The character is a text grid: one line per row of pixels, one letter per pixel.
//  Edit `PetSprite.base` to redraw it. Letters map to colours in `PetSprite.palette`:
//
//      .  transparent      O  body           H  highlight (top)
//      S  shadow (bottom)  D  dark (eyes and mouth)
//
//  Features are stamped onto that grid per mood, so the body is drawn once and the
//  eyes and mouth change. Motion is whole-pixel only: a pixel character that slides
//  by half a pixel stops looking like pixel art.
//

import AppKit
import SwiftUI

extension Color {
    /// The pet's colour. Change this to recolour the whole character.
    static let claudePet = Color(red: 0.85, green: 0.47, blue: 0.34)

    /// Mixes towards another colour. Used for the pet's highlight and shadow rows.
    func blended(with other: Color, amount: Double) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB)
        else { return self }
        return Color(
            .sRGB,
            red: a.redComponent + (b.redComponent - a.redComponent) * amount,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount,
            opacity: 1
        )
    }
}

// MARK: - The sprite

enum PetSprite {
    /// The character, 12 x 12 pixels. Every line must be exactly 12 characters long.
    static let base = [
        ".OO......OO.",
        ".OO......OO.",
        "..HHHHHHHH..",
        ".HHHHHHHHHH.",
        "OOOOOOOOOOOO",
        "OOOOOOOOOOOO",
        "OOOOOOOOOOOO",
        ".OOOOOOOOOO.",
        "..OOOOOOOO..",
        "..SSSSSSSS..",
        "...SSSSSS...",
        "............"
    ]

    static let size = 12

    enum Eyes {
        case open, blink, closed, happy, wide
    }

    enum Mouth {
        case line, open, wideOpen, smile
    }

    static func palette(tint: Color) -> [Character: Color] {
        [
            "O": tint,
            "H": tint.blended(with: .white, amount: 0.22),
            "S": tint.blended(with: .black, amount: 0.3),
            "D": Color(red: 0.13, green: 0.09, blue: 0.08)
        ]
    }

    /// Stamps eyes and mouth onto the body. `gaze` shifts the eyes left or right by whole pixels.
    static func frame(eyes: Eyes, mouth: Mouth, gaze: Int = 0) -> [[Character]] {
        var grid = base.map(Array.init)

        func set(_ row: Int, _ column: Int, _ character: Character = "D") {
            let column = column + gaze
            guard grid.indices.contains(row), grid[row].indices.contains(column) else { return }
            // Never draw a feature outside the body.
            guard grid[row][column] != "." else { return }
            grid[row][column] = character
        }

        // Eyes sit two pixels wide, with a three-pixel gap between them.
        for eyeLeft in [3, 7] {
            switch eyes {
            case .open:
                set(5, eyeLeft); set(5, eyeLeft + 1)
                set(6, eyeLeft); set(6, eyeLeft + 1)
            case .blink, .closed:
                set(6, eyeLeft); set(6, eyeLeft + 1)
            case .wide:
                set(4, eyeLeft); set(4, eyeLeft + 1)
                set(5, eyeLeft); set(5, eyeLeft + 1)
                set(6, eyeLeft); set(6, eyeLeft + 1)
            case .happy:
                // An upward arc: ^
                set(5, eyeLeft); set(5, eyeLeft + 1)
                set(6, eyeLeft - 1); set(6, eyeLeft + 2)
            }
        }

        switch mouth {
        case .line:
            set(7, 5); set(7, 6)
        case .open:
            set(7, 5); set(7, 6)
            set(8, 5); set(8, 6)
        case .wideOpen:
            set(7, 4); set(7, 5); set(7, 6); set(7, 7)
            set(8, 4); set(8, 5); set(8, 6); set(8, 7)
        case .smile:
            set(7, 3); set(8, 4); set(8, 5); set(8, 6); set(8, 7); set(7, 8)
        }

        return grid
    }
}

// MARK: - Rendering

/// Draws a character grid as crisp squares, snapped to whole device pixels.
struct PixelCanvas: View {
    let grid: [[Character]]
    let palette: [Character: Color]
    /// Vertical offset in sprite pixels, negative is up.
    var pixelOffsetY: Int = 0

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let rows = grid.count
            let columns = grid.first?.count ?? 0
            guard rows > 0, columns > 0 else { return }

            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            let originX = (size.width - cell * CGFloat(columns)) / 2
            let originY = (size.height - cell * CGFloat(rows)) / 2 + cell * CGFloat(pixelOffsetY)

            for (y, row) in grid.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = palette[character] else { continue }
                    // Round both edges so neighbouring pixels meet with no seam.
                    let left = (originX + CGFloat(x) * cell).rounded()
                    let top = (originY + CGFloat(y) * cell).rounded()
                    let right = (originX + CGFloat(x + 1) * cell).rounded()
                    let bottom = (originY + CGFloat(y + 1) * cell).rounded()
                    context.fill(
                        Path(CGRect(x: left, y: top, width: right - left, height: bottom - top)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

struct ClaudePetView: View {
    let activity: ClaudeCodeActivity
    var tint: Color = .claudePet

    /// Pixel art animates in steps, not curves: a handful of frames a second reads better.
    private var framesPerSecond: Double {
        switch activity {
        case .idle: return 2
        case .working: return 6
        case .waiting: return 8
        case .done: return 5
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / framesPerSecond)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate * framesPerSecond)
            PixelCanvas(
                grid: grid(step: step),
                palette: PetSprite.palette(tint: tint),
                pixelOffsetY: hop(step: step)
            )
            .shadow(color: activity == .waiting ? tint.opacity(0.8) : .clear, radius: 4)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(accessibilityText)
    }

    private func grid(step: Int) -> [[Character]] {
        switch activity {
        case .idle:
            // Asleep, with a slow blink of the closed lids every few seconds.
            return PetSprite.frame(eyes: .closed, mouth: .line)
        case .working:
            // Eyes scan left, centre, right, centre while the mouth works.
            let gaze = [-1, 0, 1, 0][step % 4]
            let blinking = step % 24 == 0
            return PetSprite.frame(
                eyes: blinking ? .blink : .open,
                mouth: step % 2 == 0 ? .open : .line,
                gaze: gaze
            )
        case .waiting:
            return PetSprite.frame(eyes: .wide, mouth: .wideOpen)
        case .done:
            return PetSprite.frame(eyes: .happy, mouth: .smile)
        }
    }

    /// Whole-pixel bounce.
    private func hop(step: Int) -> Int {
        switch activity {
        case .idle: return step % 8 == 0 ? 1 : 0     // a slow breath
        case .working: return step % 2 == 0 ? 0 : -1 // busy bobbing
        case .waiting: return [0, -1, -2, -1][step % 4]
        case .done: return [0, -2, -1, 0][step % 4]
        }
    }

    private var accessibilityText: String {
        switch activity {
        case .idle: return "Claude pet sleeping"
        case .working: return "Claude is working"
        case .waiting: return "Claude needs your attention"
        case .done: return "Claude finished"
        }
    }
}

// MARK: - The badge on the other side of the notch

/// Sits opposite the pet: pixel dots while working, a mark when Claude needs you, a tick when done.
struct ClaudePetStatusBadge: View {
    let activity: ClaudeCodeActivity
    var tint: Color = .claudePet

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 6)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate * 6)
            switch activity {
            case .working:
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(tint)
                            .frame(width: 3, height: 3)
                            .opacity(index == step % 3 ? 1 : 0.25)
                    }
                }
            case .waiting:
                PixelCanvas(grid: PixelGlyph.exclamation, palette: [
                    "D": step % 2 == 0 ? Color.orange : Color.orange.opacity(0.35)
                ])
                .frame(width: 12, height: 14)
            case .done:
                PixelCanvas(grid: PixelGlyph.tick, palette: ["D": Color.green])
                    .frame(width: 14, height: 12)
            case .idle:
                PixelCanvas(grid: PixelGlyph.zzz, palette: ["D": Color.gray.opacity(0.7)])
                    .frame(width: 14, height: 12)
            }
        }
    }
}

private enum PixelGlyph {
    static let exclamation = grid([
        ".DD.",
        ".DD.",
        ".DD.",
        ".DD.",
        "....",
        ".DD.",
    ])

    static let tick = grid([
        "......D",
        ".....D.",
        "D...D..",
        ".D.D...",
        "..D....",
    ])

    static let zzz = grid([
        "..DDD",
        "...D.",
        "..D..",
        "..DDD",
        ".....",
        "DDD..",
        ".D...",
        "DDD..",
    ])

    private static func grid(_ rows: [String]) -> [[Character]] { rows.map(Array.init) }
}

#Preview {
    HStack(spacing: 20) {
        ForEach(ClaudeCodeActivity.allCases, id: \.self) { activity in
            VStack(spacing: 10) {
                ClaudePetView(activity: activity)
                    .frame(width: 48, height: 48)
                ClaudePetStatusBadge(activity: activity)
                    .frame(height: 16)
                Text(activity.rawValue).font(.caption2).foregroundStyle(.gray)
            }
        }
    }
    .padding(24)
    .background(.black)
}
