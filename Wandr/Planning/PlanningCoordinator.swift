//
//  PlanningCoordinator.swift
//  Wandr
//
//  The MainActor bridge between the confirmed group summary and the swipe UI.
//
//  `RootView` hands it the reviewed `ChatSummaryPayload`; it runs the grounded
//  pipeline (deterministic JSON→brief, dataset research, on-device model curation,
//  deterministic validation) off the main actor, then publishes one of three
//  phases the UI renders: planning, ready (decks + banner), or a failure the host
//  can act on. Nothing here decides *what* to show — the model and validator do —
//  it only sequences the async work and maps the result for display.
//

import Foundation
import Observation

@MainActor
@Observable
final class PlanningCoordinator {

    /// What the UI should show right now.
    enum Phase {
        case idle
        /// The pipeline is running — research + on-device model curation.
        case planning
        /// A validated plan, mapped to swipe decks.
        case ready(output: GroundedPlanMapper.Output, groupSize: Int?)
        /// A recoverable failure with a host-readable reason and a retry action.
        case failed(PlanningFailure)
    }

    private(set) var phase: Phase = .idle

    /// Runs one plan for a confirmed summary and publishes the outcome.
    ///
    /// Never throws: every failure becomes a `.failed` phase carrying a
    /// `PlanningFailure`, so the UI always has a message and a next step.
    func run(payload: ChatSummaryPayload) async {
        phase = .planning

        do {
            // The dataset is the one piece of local I/O the core permits.
            let researcher = try DistrictVenueProvider()

            let service = TravelPlanningService(
                extractor: ChatSummaryBriefExtractor(),
                researcher: researcher,
                curator: FoundationModelsCurator()
            )

            // The confirmed summary travels as its own JSON — a structured summary,
            // never the raw chat — which the extractor decodes straight back.
            let input = PlanningInput(text: Self.json(from: payload))
            let run = try await service.plan(input)

            switch run.state {
            case .ready:
                guard let plan = run.plan else {
                    phase = .failed(PlanningFailure(.structuredOutputDecodingFailed))
                    return
                }
                // The full dataset resolves every plan venue ID (a plan's IDs are a
                // subset of it), so it is a safe evidence source for display.
                let output = GroundedPlanMapper.map(plan: plan, evidence: researcher.allVenues)
                guard !output.decks.isEmpty else {
                    phase = .failed(PlanningFailure(.insufficientEvidence(details: [])))
                    return
                }
                // Preserve "unspecified" group size so the poll can fall back to the
                // slate's implied size rather than a defaulted head-count.
                phase = .ready(output: output, groupSize: payload.groupSize)

            case .failed, .needsDetails:
                phase = .failed(run.failure ?? PlanningFailure(.structuredOutputDecodingFailed))

            default:
                phase = .failed(PlanningFailure(.structuredOutputDecodingFailed))
            }

        } catch let failure as PlanningFailure {
            phase = .failed(failure)
        } catch {
            // DistrictVenueProvider packaging faults and anything unexpected land here.
            phase = .failed(PlanningFailure(.structuredOutputDecodingFailed))
        }
    }

    /// Encodes the reviewed summary as compact JSON for the extractor.
    private static func json(from payload: ChatSummaryPayload) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
