// VenuePhoto.swift Wandr Bundled venue photography, keyed by `imageSeed`.
//
// ## Why this is synchronous
//
// `CandidateBackdrop` is drawn by the deck card *and* by the expanded hero — the same
// view, deliberately, so that `.navigationTransition(.zoom)` reads as one object growing
// rather than a cross-fade. Two lookups that disagree for even one frame would show the
// seam that sharing the view exists to prevent. A bundled asset resolves instantly and
// identically in both, which is also why an `AsyncImage` fetch would be the wrong shape
// here even against a perfect network — the demo cannot afford a card that is a gradient
// on the way in and a photograph on the way out.
//
// ## Coverage is partial on purpose
//
// Only the venues that have been photographed carry an asset. Everything else returns
// `nil` and falls back to the procedural gradient that has always been there, so a seed
// with no photograph is a normal card rather than a blank one.

import SwiftUI
import UIKit

@MainActor
enum VenuePhoto {

    /// `imageSeed` 0 means "no venue" — the demo fixtures that were never tied to a row in
    /// the dataset use it, and it must never resolve to someone else's photograph.
    static let noPhoto = 0

    /// Full-bleed card and hero imagery. Square masters: the card is portrait (~0.90) and
    /// the hero is landscape (~1.12), so anything else crops badly in one of the two.
    static func image(seed: Int) -> Image? {
        guard let asset = name(seed, suffix: "") else { return nil }
        return Image(asset)
    }

    /// Small square imagery for list rows — shortlist, poll options, itinerary stops.
    /// Falls back to the full-size asset when a thumbnail variant was never generated.
    static func thumbnail(seed: Int) -> Image? {
        if let thumb = name(seed, suffix: "-thumb") { return Image(thumb) }
        return image(seed: seed)
    }

    /// Whether any photography exists for this venue, without building an `Image`.
    static func exists(seed: Int) -> Bool {
        name(seed, suffix: "") != nil
    }

    // MARK: - Lookup

    /// `UIImage(named:)` hits the catalog and decodes; memoising keeps the deck card and
    /// the hero on one answer and keeps a scrolling list of rows off the decoder.
    private static var cache: [String: Bool] = [:]

    private static func name(_ seed: Int, suffix: String) -> String? {
        guard seed != noPhoto else { return nil }
        let candidate = "venue-\(seed)\(suffix)"

        if let known = cache[candidate] {
            return known ? candidate : nil
        }

        let found = UIImage(named: candidate) != nil
        cache[candidate] = found
        return found ? candidate : nil
    }
}

// MARK: - Row thumbnail

/// The venue's photograph at list-row size, falling back to the accent-filled category
/// glyph that every one of these rows drew before there were photographs. Shared by the
/// shortlist, the poll options, the timeline and the itinerary so that a stop looks like
/// the same object at every point it is seen — which is the whole reason the deck card and
/// the hero share a view too.
///
/// Takes an accent and a symbol rather than a `StopCategory` because a `PollOption` has
/// been flattened away from its candidate and only knows its slot's accent.
struct VenueThumbnail: View {
    let seed: Int
    let accent: Color
    let symbol: String
    var size: CGFloat = 38
    var corner: CGFloat = 9

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        return shape
            .fill(accent)
            .frame(width: size, height: size)
            .overlay {
                if let photo = VenuePhoto.thumbnail(seed: seed) {
                    photo
                        .resizable()
                        .scaledToFill()
                        .saturation(0.94)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Wandr.cream)
                }
            }
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}
