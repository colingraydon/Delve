import XCTest
@testable import Delve

final class FileNodeTests: XCTestCase {
    private func makeNode(_ name: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: "/\(name)"), name: name,
                 isDirectory: true, isPackage: false, ownSize: 0)
    }

    private func link(_ parent: FileNode, _ child: FileNode) {
        child.parent = parent
        parent.children.append(child)
    }

    func testPathFromRootForRootIsJustItself() {
        let root = makeNode("root")
        XCTAssertEqual(root.pathFromRoot.map(\.name), ["root"])
    }

    func testPathFromRootWalksAncestors() {
        let root = makeNode("root")
        let mid = makeNode("Users")
        let leaf = makeNode("colin")
        link(root, mid)
        link(mid, leaf)

        XCTAssertEqual(leaf.pathFromRoot.map(\.name), ["root", "Users", "colin"])
    }

    func testPathFromRootOrderIsRootFirst() {
        let root = makeNode("a")
        let child = makeNode("b")
        link(root, child)

        let path = child.pathFromRoot
        XCTAssertEqual(path.first?.name, "a")
        XCTAssertEqual(path.last?.name, "b")
    }

    func testRemoveFromParentDetachesAndSubtractsSizesUpTheChain() {
        let root = makeNode("root")
        let mid = makeNode("mid")
        let doomed = makeNode("doomed")
        let sibling = makeNode("sibling")
        link(root, mid)
        link(mid, doomed)
        link(mid, sibling)

        doomed.totalSize = 100
        sibling.totalSize = 30
        mid.totalSize = 130
        root.totalSize = 130

        doomed.removeFromParent()

        XCTAssertNil(doomed.parent)
        XCTAssertEqual(mid.children.map(\.name), ["sibling"])
        XCTAssertEqual(mid.totalSize, 30)
        XCTAssertEqual(root.totalSize, 30)
    }

    func testRemoveFromParentOnRootIsANoOp() {
        let root = makeNode("root")
        root.totalSize = 50
        root.removeFromParent()
        XCTAssertEqual(root.totalSize, 50)
    }

    func testIsDescendantWalksThePastParentChain() {
        let root = makeNode("root")
        let mid = makeNode("mid")
        let leaf = makeNode("leaf")
        link(root, mid)
        link(mid, leaf)

        XCTAssertTrue(leaf.isDescendant(of: root))
        XCTAssertTrue(leaf.isDescendant(of: mid))
        XCTAssertTrue(mid.isDescendant(of: root))
    }

    func testIsDescendantIsStrictAndDirectional() {
        let root = makeNode("root")
        let child = makeNode("child")
        let other = makeNode("other")
        link(root, child)

        // A node is not its own descendant, and the relationship is one-way.
        XCTAssertFalse(child.isDescendant(of: child))
        XCTAssertFalse(root.isDescendant(of: child))
        // Unrelated nodes in different trees.
        XCTAssertFalse(child.isDescendant(of: other))
    }
}
