// import.swift Wandr Turns a folder of hand-picked venue photographs into asset catalog
// entries the app can draw.
//
// Run:  swift Tools/VenuePhotoImport/import.swift <source-folder>
//
// ## Why square
//
// The same `CandidateCardFace` is drawn at two opposite shapes — the deck card is portrait
// (~353x390, 0.90) and the expanded hero is landscape (~393x350, 1.12). A portrait master
// crops badly in the hero, a landscape master crops badly on the card. A square master
// crops symmetrically off the top and bottom on one and off the sides on the other, and
// doubles as the list-row thumbnail. So every asset leaves here 1:1, whatever went in.
//
// ## Why the crop is biased upward
//
// The frosted caption panel covers the bottom ~45% of the card. A centred square crop
// pushes the subject straight under it. Cropping from 30% down the available slack keeps
// the subject in the top half, where it is actually visible.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// What a 3x hero actually consumes (393pt wide). Sources at least this big are downsized
/// to it; smaller ones are written at their own size rather than fake-upscaled, because
/// inventing pixels makes a file heavier without making the picture better.
let masterSide = 1200
/// Below this a photograph is too soft to carry a full-bleed card at any scale.
let minSide = 700
let thumbSide  = 200
let quality    = 0.82
/// 0 = flush top, 0.5 = centred. Below the halfway mark so the subject rides high.
let cropBias   = 0.30

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog  = repoRoot.appending(path: "Wandr/Assets.xcassets")

guard CommandLine.arguments.count > 1 else {
    print("usage: swift Tools/VenuePhotoImport/import.swift <source-folder>")
    print("       source images named venue-<seed>.<jpg|jpeg|png|heic>")
    exit(1)
}
let sourceDir = URL(fileURLWithPath: CommandLine.arguments[1])

// MARK: - Catalog helpers

let groupContents = #"{\#n  "info" : {\#n    "author" : "xcode",\#n    "version" : 1\#n  }\#n}\#n"#

func makeGroup(_ name: String) throws {
    let dir = catalog.appending(path: name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // No `provides-namespace`, so assets are addressed by bare name: `venue-185`.
    try groupContents.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

func writeImageSet(group: String, name: String, image: CGImage) throws {
    let dir = catalog.appending(path: "\(group)/\(name).imageset")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let file = dir.appending(path: "\(name).jpg")
    guard let dest = CGImageDestinationCreateWithURL(
        file as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw Failure("could not open \(file.lastPathComponent) for writing") }

    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw Failure("could not encode \(name)") }

    // A single unscaled universal entry — the master is already larger than any @3x use.
    let contents = """
    {
      "images" : [
        {
          "filename" : "\(name).jpg",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try contents.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - Image work

/// Loads with EXIF orientation already applied — a photo shot on a phone is otherwise
/// rotated the moment it is drawn into a context.
func load(_ url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw Failure("unreadable: \(url.lastPathComponent)")
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4000
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
        throw Failure("undecodable: \(url.lastPathComponent)")
    }
    return image
}

/// Centre horizontally, bias upward vertically, then square off.
func squareCrop(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let side = min(w, h)
    let x = (w - side) / 2
    // CGImage crop coordinates run from the top-left, so a smaller y keeps more of the top.
    let y = Int(Double(h - side) * cropBias)
    return image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) ?? image
}

func resize(_ image: CGImage, to side: Int) throws -> CGImage {
    guard let ctx = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw Failure("could not create a \(side)px context") }

    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let out = ctx.makeImage() else { throw Failure("could not render at \(side)px") }
    return out
}

// MARK: - Naming

/// A file may be named for its seed (`venue-189.jpg`) or simply for the venue
/// (`Perch Wine & Coffee Bar.jpg`, `big_chill.jpg`). The second is what a human actually
/// produces when saving pictures one at a time, so resolve it against the dataset rather
/// than asking anyone to look seeds up by hand.
struct Venue {
    let name: String
    let seed: Int
}

func loadVenues() throws -> [Venue] {
    let url = repoRoot.appending(path: "Wandr/Resources/district-venues-delhi.json")
    let raw = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
    guard let root = raw as? [String: Any], let rows = root["venues"] as? [[String: Any]] else {
        throw Failure("could not read the venue dataset")
    }
    return rows.compactMap {
        guard let n = $0["name"] as? String, let s = $0["imageSeed"] as? Int else { return nil }
        return Venue(name: n, seed: s)
    }
}

/// Case, spacing, punctuation and separators all vary between what a venue is called and
/// what a downloaded file ends up named. Comparing on letters and digits alone removes
/// every one of those differences at once.
func normalise(_ s: String) -> String {
    s.lowercased().unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .reduce(into: "") { $0.unicodeScalars.append($1) }
}

/// Exact match wins. Failing that a prefix in either direction is accepted — "big_chill"
/// for "Big Chill Cafe" — but only when exactly one venue matches, so a partial name can
/// never quietly attach a photograph to the wrong place.
func resolveSeed(stem: String, in venues: [Venue]) -> Result<Int, Failure> {
    if stem.hasPrefix("venue-"), let seed = Int(stem.dropFirst("venue-".count)) {
        return .success(seed)
    }

    let needle = normalise(stem)
    guard !needle.isEmpty else { return .failure(Failure("empty name")) }

    if let exact = venues.first(where: { normalise($0.name) == needle }) {
        return .success(exact.seed)
    }

    let partial = venues.filter {
        let hay = normalise($0.name)
        return hay.hasPrefix(needle) || needle.hasPrefix(hay)
    }
    switch partial.count {
    case 1:  return .success(partial[0].seed)
    case 0:  return .failure(Failure("no venue named anything like \"\(stem)\""))
    default: return .failure(Failure("\"\(stem)\" matches \(partial.count): \(partial.map(\.name).joined(separator: ", "))"))
    }
}

// MARK: - Run

let valid: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "webp", "avif"]
let files = (try? FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil))?
    .filter { valid.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

guard !files.isEmpty else {
    print("no images found in \(sourceDir.path)")
    print("name files for the venue (Perch Wine & Coffee Bar.jpg) or its seed (venue-189.jpg)")
    exit(1)
}

let venues = try loadVenues()
try makeGroup("VenuePhotos")
try makeGroup("VenueThumbs")

var done = 0
var skipped: [String] = []
var soft: [String] = []

for file in files {
    let stem = file.deletingPathExtension().lastPathComponent
    let seed: Int
    switch resolveSeed(stem: stem, in: venues) {
    case .success(let s): seed = s
    case .failure(let why):
        skipped.append("\(file.lastPathComponent) — \(why)")
        continue
    }
    let asset = "venue-\(seed)"
    let label = venues.first { $0.seed == seed }?.name ?? asset

    do {
        let square = squareCrop(try load(file))
        let shortest = min(square.width, square.height)
        if shortest < minSide {
            skipped.append("\(file.lastPathComponent) — only \(shortest)px square, need \(minSide)px")
            continue
        }
        let side = min(masterSide, shortest)
        if side < masterSide {
            soft.append("\(label) — \(side)px, soft on a 3x hero (wants \(masterSide)px)")
        }

        try writeImageSet(group: "VenuePhotos", name: asset, image: try resize(square, to: side))
        try writeImageSet(group: "VenueThumbs", name: "\(asset)-thumb", image: try resize(square, to: thumbSide))
        print("  \(asset)  \(label)  [\(square.width)px -> \(side)px]")
        done += 1
    } catch {
        skipped.append("\(file.lastPathComponent) — \(error)")
    }
}

print("\nimported \(done) venue photograph\(done == 1 ? "" : "s")")
if !soft.isEmpty {
    print("\nusable but under-resolution \(soft.count) — replace these if there is time:")
    for s in soft { print("  \(s)") }
}
if !skipped.isEmpty {
    print("\nskipped \(skipped.count):")
    for s in skipped { print("  \(s)") }
}
