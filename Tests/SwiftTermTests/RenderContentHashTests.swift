//
//  RenderContentHashTests.swift
//
//  BufferLine.renderContentHash() backs the Metal row draw-data cache
//  (#837): a rewrite that produces identical cells must keep the hash so
//  the renderer can reuse built rows; any draw-visible change must move it.
//

import Foundation
import Testing

@testable import SwiftTerm

final class RenderContentHashTests {
    private func makeCell(_ scalar: UnicodeScalar, style: CharacterStyle = .none) -> CharData {
        CharData(attribute: Attribute(fg: CharData.defaultAttr.fg,
                                      bg: CharData.defaultAttr.bg,
                                      style: style,
                                      underlineStyle: .none,
                                      underlineColor: nil),
                 scalar: scalar,
                 size: 1)
    }

    @Test func identicalRewriteKeepsHashWhileGenerationAdvances() {
        let line = BufferLine(cols: 4)
        line[0] = makeCell("a")
        let hash = line.renderContentHash()
        let generation = line.generation

        // The spinner case: rewriting the same cells bumps generation but
        // must not move the fingerprint.
        line[0] = makeCell("a")
        #expect(line.generation != generation)
        #expect(line.renderContentHash() == hash)
    }

    @Test func cellCodeChangeMovesHash() {
        let line = BufferLine(cols: 4)
        line[0] = makeCell("a")
        let hash = line.renderContentHash()
        line[0] = makeCell("b")
        #expect(line.renderContentHash() != hash)
    }

    @Test func attributeChangeMovesHash() {
        let line = BufferLine(cols: 4)
        line[0] = makeCell("a")
        let hash = line.renderContentHash()
        line[0] = makeCell("a", style: .bold)
        #expect(line.renderContentHash() != hash)
    }

    @Test func rewriteBackToSameCellsRestoresHash() {
        let line = BufferLine(cols: 4)
        line[0] = makeCell("a")
        let hash = line.renderContentHash()
        line[1] = makeCell("b")
        #expect(line.renderContentHash() != hash)
        line[1] = CharData(attribute: CharData.defaultAttr)
        #expect(line.renderContentHash() == hash)
    }

    @Test func renderModeChangeMovesHash() {
        let line = BufferLine(cols: 4)
        let hash = line.renderContentHash()
        line.renderMode = .doubledTop
        #expect(line.renderContentHash() != hash)
    }

    @Test func fillWithDifferentAttributeMovesHash() {
        let line = BufferLine(cols: 4)
        let hash = line.renderContentHash()
        let red = Attribute(fg: CharData.defaultAttr.fg,
                            bg: .ansi256(code: 1),
                            style: .none,
                            underlineStyle: .none,
                            underlineColor: nil)
        line.fill(with: CharData(attribute: red, code: 32, size: 1))
        #expect(line.renderContentHash() != hash)
    }
}
