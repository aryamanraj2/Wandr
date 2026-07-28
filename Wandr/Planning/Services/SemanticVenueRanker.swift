//
//  SemanticVenueRanker.swift
//  Wandr
//
//  Ranking venues by what a stop is *for*, rather than by which words someone
//  remembered to put in a list.
//
//  ## Why this exists
//
//  Wandr used to decide what a request meant with a 63-word table: `"drinks"` and
//  `"bar"` mapped to nightlife, `"shopping"` and `"arcade"` to discover. It works
//  exactly as far as the list goes and fails silently past it — "ramen", "brewery",
//  "escape room", "listening bar", "qawwali" are all things a host would plausibly
//  ask for and none of them were in it. Every miss became a new entry, and the list
//  only ever grew.
//
//  The replacement is not a longer list. A date, five colleagues after work, and a
//  photography walk are three different queries over the *same* venues —
//
//      "worth lingering in, quiet enough to talk"
//      "seats a group, bookable, not too loud"
//      "visually interesting, open, walkable, good light late afternoon"
//
//  — and none of them needs a `.photowalk` case, because nothing here is enumerated
//  on either side. The model writes the query from what the host said; this scores it
//  against the words the dataset already carries.
//
//  ## What it is not
//
//  A ranking signal, never a filter. Cosine over short taglines separates well enough
//  to order a deck and nowhere near well enough to exclude from one — measured margins
//  are a few hundredths, so a threshold here would drop good venues on noise. Nothing
//  in this file can empty a deck, which is also why the vibe it encodes never needs a
//  rung on the constraint ladder: a score cannot dead-end.
//

import Foundation
import NaturalLanguage

/// Orders venues by how well their own description answers a query.
///
/// An `actor` because `NLContextualEmbedding.load()` pulls a model into memory and
/// must happen once, not per slot.
actor SemanticVenueRanker {

    /// The loaded embedding, or `nil` when the assets are not on this device.
    ///
    /// Not an error case. `hasAvailableAssets` is false on a device that has never
    /// downloaded them, and the honest response is to rank the way Wandr always did
    /// rather than to fail a plan over a ranking refinement.
    private var embedding: NLContextualEmbedding?
    private var loadAttempted = false

    /// Vectors are cached by the exact text scored, because the dataset is fixed and
    /// the same venue is scored once per slot it competes for.
    private var cache: [String: [Double]] = [:]

    init() {}

    // MARK: - Ranking

    /// Indices of `venues`, best match first, or `nil` when semantic ranking is
    /// unavailable or the query says nothing.
    ///
    /// `nil` rather than the unchanged order, so the caller can tell "this ranking is
    /// the provider's" from "this ranking is the query's" — they degrade to the same
    /// deck but they are not the same claim, and the log records which happened.
    func ranking(of venues: [GroundedVenue], matching query: String) async -> [Int]? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, venues.count > 1, let embedding = await loaded() else { return nil }
        guard let queryVector = vector(for: query, using: embedding) else { return nil }

        let scored: [(index: Int, score: Double)] = venues.indices.compactMap { index in
            guard let venueVector = vector(for: Self.text(of: venues[index]), using: embedding)
            else { return nil }
            return (index, Self.cosine(queryVector, venueVector))
        }
        guard scored.count == venues.count else { return nil }

        // Ties break on the provider's own order, so a run is reproducible: cosine over
        // near-identical taglines can genuinely tie, and `sorted` is not stable.
        return scored
            .sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
            .map(\.index)
    }

    /// The text a venue is matched on.
    ///
    /// Name, tagline and vibe tags — everything the dataset states in prose. Area is
    /// excluded deliberately: it is already a hard filter upstream, and leaving it in
    /// would let "Khan Market" in a query outrank what the host actually wanted.
    /// Category is excluded for the same reason — the slot already fixed it, so
    /// including it would score every candidate identically and dilute the rest.
    static func text(of venue: GroundedVenue) -> String {
        ([venue.name, venue.tagline] + venue.vibeTags).joined(separator: ". ")
    }

    // MARK: - Embedding

    private func loaded() async -> NLContextualEmbedding? {
        if loadAttempted { return embedding }
        loadAttempted = true

        guard let candidate = NLContextualEmbedding(language: .english) else { return nil }
        // Assets ship separately and may simply not be present. `load()` throws rather
        // than downloading, so this is a check, not a fetch.
        guard candidate.hasAvailableAssets, (try? candidate.load()) != nil else { return nil }

        embedding = candidate
        return embedding
    }

    /// One mean-pooled vector for a whole string.
    ///
    /// Mean-pooled rather than first-token: these are fragments, not sentences with a
    /// summary position, and averaging is what makes a two-word vibe tag contribute at
    /// all.
    ///
    /// - Note: deliberately **not** centred on the corpus mean. Subtracting the
    ///   centroid is the textbook fix for embedding anisotropy and it widened the score
    ///   spread here by roughly six times — while inverting the ordering, because with
    ///   a corpus this small the centroid is dominated by a handful of documents and
    ///   the result measures distance-from-typical rather than relevance. Measured
    ///   top-1 accuracy: raw 4/5, centred 1/5. Wider spread, worse answers.
    private func vector(for text: String, using embedding: NLContextualEmbedding) -> [Double]? {
        if let cached = cache[text] { return cached }
        guard let result = try? embedding.embeddingResult(for: text, language: .english)
        else { return nil }

        var total: [Double] = []
        var tokens = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            total = total.isEmpty ? vector : zip(total, vector).map(+)
            tokens += 1
            return true
        }
        guard tokens > 0, !total.isEmpty else { return nil }

        let pooled = total.map { $0 / Double(tokens) }
        cache[text] = pooled
        return pooled
    }

    static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot = zip(lhs, rhs).map(*).reduce(0, +)
        let left = lhs.map { $0 * $0 }.reduce(0, +).squareRoot()
        let right = rhs.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard left > 0, right > 0 else { return 0 }
        return dot / (left * right)
    }
}
