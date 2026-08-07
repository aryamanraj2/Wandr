// WandrMasthead.swift Wandr The top of every screen that isn't a list. One statement at poster scale, one supporting line under it, and real air beneath both — so a page has an obvious subject before any of its content is read.

import SwiftUI

/// The masthead each intake, capture, and progress screen opens with.
///
/// These screens used to each roll their own header — `wandrDisplay(30)` here, `(34)` there,
/// `(36)` on the third, one of them centred, one with a hard `\n` in the string — so five pages that
/// are one flow looked like five pages from three apps. This is that header, once.
///
/// The scale is deliberately larger than the old display ramp. At `wandrDisplay(34)` the title was
/// the same order of size as the body copy under it and the buttons beside it, which is what made
/// these screens read as forms: nothing on them was the subject. A poster-scale line settles that
/// question before you read a word, and lets everything else drop to a genuinely quiet weight.
struct WandrMasthead: View {

    let title: String

    /// The line under the title. Optional because some screens have nothing to add and a masthead
    /// with an empty subtitle slot is worse than one without.
    var deck: String?

    /// Overridable for the rare screen that needs a different weight of statement — the loading
    /// view's single word carries more size than a three-line title can.
    var size: CGFloat = 46

    /// Sends a highlight through the title while the screen is waiting on something. Only the title
    /// — running it through the deck as well would put moving light behind a paragraph someone is
    /// trying to read.
    var shimmering: Bool = false

    /// The poster is a fixed point size, which means it does *not* grow with Dynamic Type on its
    /// own — and a 46pt title above body copy set at AX5 is a title smaller than its own subtitle.
    /// So it scales, off the `largeTitle` ramp, and then stops: measured at the accessibility sizes,
    /// past about a third again its base size a three-line masthead eats half the viewport before
    /// the content it heads has started. Clamped rather than switched to a smaller font, so the
    /// hierarchy holds at every size instead of inverting at one.
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1

    private var scaledSize: CGFloat { size * min(typeScale, 1.3) }

    /// Tracking is a proportion of the size, not a constant. The same -1.6 that closes up a 46pt
    /// line would visibly collide the letters of a 30pt one.
    private var scaledTracking: CGFloat { Metrics.posterTracking * (scaledSize / 46) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.wandrPoster(scaledSize))
                // Tracking and leading are style-specific, never global: these two values are what
                // separate a masthead from merely large text, and either of them applied to body
                // copy would tighten it past comfortable reading.
                .tracking(scaledTracking)
                .lineSpacing(Metrics.posterLeading)
                .foregroundStyle(Wandr.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wandrTypeShimmer(shimmering)
                .accessibilityAddTraits(.isHeader)

            if let deck {
                Text(deck)
                    .font(.body)
                    .foregroundStyle(Wandr.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Two lines") {
    VStack(alignment: .leading) {
        WandrMasthead(
            title: "Ready when the group chat is",
            deck: "Ask Siri to send a summary of your group chat here. Wandr plans from that summary — and only that summary."
        )
        Spacer()
    }
    .padding(.horizontal, Metrics.gutter)
    .padding(.top, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Wandr.pageBackground)
}

#Preview("One word") {
    WandrMasthead(title: "Planning", size: 52)
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
}
