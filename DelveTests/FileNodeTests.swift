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
}
