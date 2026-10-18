@testable import Satin
import Metal
import XCTest

/// `RenderCollection` keeps collection order, sorts each layer once per pass on the first sorted
/// read, lists only layers holding renderables this pass, and keeps its storage across passes.
final class RenderCollectionTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func mesh(_ label: String, renderOrder: Int = 0, layer: RenderLayer = .opaque) -> Mesh {
        Mesh(context: context, label: label, geometry: Geometry(context: context), material: BasicColorMaterial(context: context), renderOrder: renderOrder, renderLayer: layer)
    }

    private func collect(_ renderable: Renderable, into collection: RenderCollection) {
        collection.collect(object: renderable, renderable: renderable, light: nil, environment: nil)
    }

    func testUnsortedReadsKeepCollectionOrderAndSortedReadsSort() {
        let collection = RenderCollection()
        let late = mesh("late", renderOrder: 2)
        let early = mesh("early", renderOrder: 0)
        collect(late, into: collection)
        collect(early, into: collection)

        XCTAssertEqual(collection.renderables(renderLayer: 0, sorted: false).map(\.label), ["late", "early"])
        XCTAssertEqual(collection.renderables(renderLayer: 0, sorted: true).map(\.label), ["early", "late"])
    }

    func testTheSortReflectsRenderOrderBeforeTheFirstSortedReadAndIsReusedAfter() {
        let collection = RenderCollection()
        let first = mesh("first", renderOrder: 0)
        let second = mesh("second", renderOrder: 1)
        collect(first, into: collection)
        collect(second, into: collection)

        first.renderOrder = 5
        XCTAssertEqual(collection.renderables(renderLayer: 0, sorted: true).map(\.label), ["second", "first"])

        first.renderOrder = -5
        XCTAssertEqual(collection.renderables(renderLayer: 0, sorted: true).map(\.label), ["second", "first"], "cached for the rest of the pass")

        collection.reset()
        collect(first, into: collection)
        collect(second, into: collection)
        XCTAssertEqual(collection.renderables(renderLayer: 0, sorted: true).map(\.label), ["first", "second"], "the next pass sorts again")
    }

    func testActiveLayersListOnlyLayersCollectedThisPass() {
        let collection = RenderCollection()
        collect(mesh("overlay", layer: .overlay), into: collection)
        collect(mesh("opaque", layer: .opaque), into: collection)
        XCTAssertEqual(collection.activeLayers, [RenderLayer.opaque.rawValue, RenderLayer.overlay.rawValue])
        XCTAssertFalse(collection.isEmpty)

        collection.reset()
        collect(mesh("transparent", layer: .transparent), into: collection)
        XCTAssertEqual(collection.activeLayers, [RenderLayer.transparent.rawValue], "layers emptied since the last pass are gone")
        XCTAssertTrue(collection.renderables(renderLayer: RenderLayer.opaque.rawValue, sorted: false).isEmpty)

        collection.reset()
        XCTAssertTrue(collection.isEmpty)
        XCTAssertTrue(collection.objects.isEmpty)
    }

    func testALayerWithNothingCollectedGivesAnEmptyList() {
        let collection = RenderCollection()
        XCTAssertTrue(collection.renderables(renderLayer: 7, sorted: true).isEmpty)
    }
}
