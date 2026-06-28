#!/usr/bin/env swift
// Génère l'icône iOS (1024×1024, OPAQUE, sans alpha) à partir de l'icône macOS.
//
// iOS exige une icône pleine sans canal alpha (il applique lui-même le masque
// arrondi). L'icône macOS a une fine marge transparente : on la compose sur un
// dégradé indigo assorti au squircle, puis on exporte un PNG opaque.
//
// Usage : swift make-ios-icon.swift <source-1024.png> <dest.png>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-ios-icon.swift <src.png> <dst.png>\n".data(using: .utf8)!)
    exit(2)
}
let srcURL = URL(fileURLWithPath: args[1])
let dstURL = URL(fileURLWithPath: args[2])

guard let srcData = try? Data(contentsOf: srcURL),
      let imgSource = CGImageSourceCreateWithData(srcData as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(imgSource, 0, nil) else {
    FileHandle.standardError.write("Erreur : lecture image source impossible\n".data(using: .utf8)!)
    exit(1)
}

let side = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write("Erreur : contexte graphique\n".data(using: .utf8)!)
    exit(1)
}

// Dégradé vertical indigo assorti au squircle macOS (haut clair → bas foncé).
let top = CGColor(colorSpace: cs, components: [0.196, 0.173, 0.369, 1.0])!  // #322c5e
let bot = CGColor(colorSpace: cs, components: [0.137, 0.114, 0.251, 1.0])!  // #231d40
let gradient = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Icône source dessinée pleine taille (couvre tout sauf la fine marge → dégradé).
ctx.interpolationQuality = .high
ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(dstURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("Erreur : création image de sortie\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("Erreur : écriture PNG\n".data(using: .utf8)!)
    exit(1)
}
print("✓ icône iOS générée : \(dstURL.path)")
