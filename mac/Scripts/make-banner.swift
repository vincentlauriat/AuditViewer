#!/usr/bin/env swift
//
// make-banner.swift
//
// Génère la bannière sociale du dépôt (GitHub social preview / og:image),
// 1280 × 640. Fond dégradé sombre + violet, titre, tagline, et l'icône de l'app.
//
// Usage : ./Scripts/make-banner.swift <output.png> [chemin/AppIcon.icns]

import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-banner.swift <output.png> [AppIcon.icns]\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: args[1])
let iconPath = args.count >= 3 ? args[2] : nil

let W: CGFloat = 1280, H: CGFloat = 640

// Rendu dans un bitmap de taille EXACTE (indépendant de la densité de l'écran,
// sinon un écran Retina produirait un PNG 2×, trop lourd pour le social preview).
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Fond dégradé diagonal (slate-900 → violet-700)
let c1 = NSColor(srgbRed: 0.059, green: 0.090, blue: 0.165, alpha: 1) // #0f172a
let c2 = NSColor(srgbRed: 0.298, green: 0.180, blue: 0.667, alpha: 1) // #4c2eaa
NSGradient(starting: c1, ending: c2)?.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 35)

// Halo violet diffus en haut-droite (accent)
let glow = NSColor(srgbRed: 0.486, green: 0.227, blue: 0.929, alpha: 0.45) // #7c3aed
NSGradient(starting: glow, ending: NSColor.clear)?.draw(
    in: NSRect(x: W * 0.30, y: H * 0.10, width: W * 1.1, height: H * 1.1),
    relativeCenterPosition: NSPoint(x: 0.55, y: 0.4))

// Icône de l'app (si fournie)
var textX: CGFloat = 96
if let iconPath, let icon = NSImage(contentsOfFile: iconPath) {
    let side: CGFloat = 232
    let iconRect = NSRect(x: 96, y: (H - side) / 2, width: side, height: side)
    icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    textX = iconRect.maxX + 64
}

let white = NSColor.white
let dim = NSColor(white: 1, alpha: 0.82)
let accent = NSColor(srgbRed: 0.80, green: 0.73, blue: 1.0, alpha: 1) // violet clair

// Dessine des lignes en partant d'une distance `topY` depuis le HAUT de l'image.
func drawLines(_ lines: [String], font: NSFont, color: NSColor, x: CGFloat, topY: CGFloat, gap: CGFloat = 10) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let lineH = font.ascender - font.descender + font.leading
    var top = topY
    for line in lines {
        let yBottom = H - top - lineH                 // coin bas-gauche en coordonnées AppKit
        (line as NSString).draw(at: NSPoint(x: x, y: yBottom), withAttributes: attrs)
        top += lineH + gap
    }
}

drawLines(["AuditViewer"],
          font: .systemFont(ofSize: 92, weight: .bold), color: white, x: textX, topY: 150)
drawLines(["Turn any company, product or market into a",
           "complete strategic dossier — in minutes."],
          font: .systemFont(ofSize: 33, weight: .medium), color: dim, x: textX, topY: 300, gap: 8)
drawLines(["AI audit skill  ·  web viewer  ·  native macOS app"],
          font: .systemFont(ofSize: 24, weight: .semibold), color: white, x: textX, topY: 452)
drawLines(["Works with Claude  &  Gemini"],
          font: .systemFont(ofSize: 24, weight: .bold), color: accent, x: textX, topY: 498)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try png.write(to: output)
print("✓ wrote \(output.path) (\(Int(W))x\(Int(H)))")
