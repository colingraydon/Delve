import XCTest
@testable import Delve

final class TrashGuardTests: XCTestCase {
    private func protected(_ path: String) -> Bool {
        TrashGuard.isProtected(URL(fileURLWithPath: path))
    }

    private var home: String { TrashGuard.realHomeDirectory }

    func testRootIsProtected() {
        XCTAssertTrue(protected("/"))
    }

    func testSystemTreesAreProtectedIncludingContents() {
        XCTAssertTrue(protected("/System"))
        XCTAssertTrue(protected("/System/Library/CoreServices"))
        XCTAssertTrue(protected("/usr/bin"))
        XCTAssertTrue(protected("/Library/Extensions"))
        XCTAssertTrue(protected("/private/var/db"))
    }

    func testVolumeRootsAreProtectedButContentsAreNot() {
        XCTAssertTrue(protected("/Volumes/Backup"))
        XCTAssertFalse(protected("/Volumes/Backup/old-movies"))
    }

    func testHomeAndStandardFoldersAreProtected() {
        XCTAssertTrue(protected(home))
        XCTAssertTrue(protected(home + "/Documents"))
        XCTAssertTrue(protected(home + "/Desktop"))
        XCTAssertTrue(protected(home + "/Library"))
    }

    func testContentsOfStandardFoldersAreDeletable() {
        XCTAssertFalse(protected(home + "/Documents/old-report.pdf"))
        XCTAssertFalse(protected(home + "/Downloads/installer.dmg"))
        XCTAssertFalse(protected(home + "/Movies/raw-footage"))
    }

    func testUserLibraryTopLevelIsProtectedButDeeperIsNot() {
        XCTAssertTrue(protected(home + "/Library/Caches"))
        XCTAssertTrue(protected(home + "/Library/Application Support"))
        XCTAssertFalse(protected(home + "/Library/Caches/com.example.app"))
    }

    func testMediaLibraryPackagesAreProtected() {
        XCTAssertTrue(protected(home + "/Pictures/Photos Library.photoslibrary"))
        XCTAssertTrue(protected(home + "/Music/Music Library.musiclibrary"))
    }

    func testOrdinaryProjectFolderIsDeletable() {
        XCTAssertFalse(protected(home + "/Documents/GitHub/old-project"))
        XCTAssertFalse(protected("/Users/Shared/scratch"))
    }
}
