//
//  GlyphFallback.swift
//
//  Host-supplied glyph fallback for symbol codepoints (for example Nerd Font
//  icons) that the selected terminal font does not contain. Minimal backport
//  of the upstream API to the 1.20 renderer: the provider claims an exact
//  scalar set and supplies the fallback face; the line builder isolates
//  claimed cells into their own segment and substitutes the font attribute.
//
#if !SWIFTTERM_EMBEDDED
#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics
import CoreText

/// A host-supplied source of fallback glyphs for known symbol codepoints.
///
/// Set an implementation on `TerminalView.glyphFallbackProvider` to enable
/// the feature; the default of `nil` leaves rendering unchanged. The provider
/// is consulted only for scalars it claims via ``providesFallback(for:)`` and
/// only when the requested terminal face lacks the glyph, so a user-selected
/// patched font always keeps priority.
///
/// Implementations must be thread-safe. ``fallbackFont(forPointSize:)`` must
/// return the same `CTFont` instance for repeated calls at one size —
/// renderer caches key on font identity, and a fresh instance per call would
/// defeat them and grow them without bound.
public protocol TerminalGlyphFallbackProvider: AnyObject, Sendable {
    /// Whether the provider can supply a glyph for `scalar`. Candidacy must
    /// be an exact set: claiming a broad private-use range would replace an
    /// application's unrelated glyphs.
    func providesFallback (for scalar: Unicode.Scalar) -> Bool

    /// The fallback face at `size` points, or `nil` when it is unavailable
    /// (for example, when font registration failed). Memoize per size and
    /// return a stable instance.
    func fallbackFont (forPointSize size: CGFloat) -> CTFont?

    /// Bump this when the provider's data or font changes. It is hashed into
    /// the render cache identities together with the provider's object
    /// identity, so stale glyphs cannot survive a change.
    var generation: UInt64 { get }
}

/// The scalar the provider is asked about: the cluster's only scalar, or its
/// first when the only other scalar is a variation selector. Any other
/// multi-scalar cluster is never a fallback candidate.
func glyphFallbackBaseScalar (of character: Character) -> Unicode.Scalar? {
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return nil }
    if scalars.count == 1 { return first }
    if scalars.count == 2 && UnicodeUtil.isVariationSelector(scalars.last!.value) {
        return first
    }
    return nil
}

/// Per-(face, scalar) glyph coverage for the fallback check. The cmap probe
/// is one `CTFontCopyCharacterSet` membership test; buildAttributedString
/// calls it once per cell, so results are cached like `resolvedFont`.
private struct GlyphCoverageKey: Hashable {
    let baseFont: ObjectIdentifier
    let scalar: UInt32
}
private var glyphCoverageCache: [GlyphCoverageKey: Bool] = [:]

/// Whether `base` can shape `scalar`. Main-thread only, like the build path.
func fontCoversScalar (_ base: TTFont, _ scalar: Unicode.Scalar) -> Bool {
    let key = GlyphCoverageKey(baseFont: ObjectIdentifier(base), scalar: scalar.value)
    if let cached = glyphCoverageCache[key] {
        return cached
    }
    if glyphCoverageCache.count >= 4096 {
        glyphCoverageCache.removeAll(keepingCapacity: true)
    }
    let charset = CTFontCopyCharacterSet(base as CTFont)
    let covered = CFCharacterSetIsLongCharacterMember(charset, scalar.value)
    glyphCoverageCache[key] = covered
    return covered
}

extension TerminalView {
    /// The provider's face for `character`, or `nil` when the cell takes the
    /// normal path: no provider, the cluster is not a claimable scalar, the
    /// provider declines it, the active face already covers it, or the
    /// provider has no font at the size.
    func claimedFallbackFont (for character: Character,
                              attributes: [NSAttributedString.Key: Any]) -> TTFont? {
        guard let provider = glyphFallbackProvider,
              let scalar = glyphFallbackBaseScalar(of: character),
              provider.providesFallback(for: scalar) else {
            return nil
        }
        let baseFont = (attributes[.font] as? TTFont) ?? fontSet.normal
        guard !fontCoversScalar(baseFont, scalar),
              let fallback = provider.fallbackFont(forPointSize: baseFont.pointSize) else {
            return nil
        }
        return fallback as TTFont
    }
}

#endif
#endif
