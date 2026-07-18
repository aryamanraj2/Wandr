//
//  PlanningAssembly.swift
//  Wandr
//
//  The live-pipeline front door. One composition helper that answers "give me the
//  real pipeline": real extractor, normalizer, MapKit-decorated provider, real
//  curator, validator, drafter, no-op store.
//
//  Its signature is Foundation-only; it reaches the FoundationModels/MapKit types
//  through same-module `AI/` and `Data/` dependencies, so no caller has to import
//  either framework to stand up a live run. It has exactly one UI caller — the
//  capture harness — which keeps the eventual UI-bridge step from reaching into
//  `AI/` internals.
//
//  The fakes are NOT wired here as a runtime fallback. Unavailability is a visible
//  `.failed` run with an honest retry action (the gate throws inside each adapter),
//  never a silent swap to canned extraction that would fabricate a working demo on
//  a device that doesn't have one.
//

import Foundation

nonisolated enum PlanningAssembly {

    /// Builds the live `TravelPlanningService`.
    ///
    /// - Throws: only `VenueDatasetError`, and only if the bundled dataset is missing
    ///   or won't decode — a build/packaging fault, surfaced at construction rather
    ///   than pretending to plan with no evidence. Model *availability* is not
    ///   checked here: that is each adapter's call-time job, so a run started while
    ///   Apple Intelligence is off becomes a `.failed` run, not a construction error.
    static func liveService(
        bundle: Bundle = .main,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> TravelPlanningService {

        let provider = try DistrictVenueProvider(bundle: bundle, retrievedAt: now())
        let researcher = MapKitVenueEnricher(base: provider, now: now)

        return TravelPlanningService(
            extractor: FoundationModelsBriefExtractor(),
            normalizer: BriefNormalizer(),
            researcher: researcher,
            curator: FoundationModelsItineraryCurator(),
            validator: FeasibilityValidator(),
            scheduler: ScheduleDrafter(),
            store: NoOpPlanningRunStore(),
            now: now
        )
    }
}
