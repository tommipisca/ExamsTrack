import Foundation
import Testing
@testable import ExamsCore

@Suite struct DataFileLocationTests {
    let group: URL
    let documents: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        group = root.appendingPathComponent("group")
        documents = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    @Test func usesGroupWhenAvailable() {
        let url = AppGroup.resolveDataFileURL(groupContainer: group, documents: documents)
        #expect(url == group.appendingPathComponent("exams.json"))
    }

    @Test func fallsBackToDocuments() {
        let url = AppGroup.resolveDataFileURL(groupContainer: nil, documents: documents)
        #expect(url == documents.appendingPathComponent("exams.json"))
    }

    @Test func movesDocumentsFileIntoGroup() throws {
        try Data("dati".utf8).write(to: documents.appendingPathComponent("exams.json"))
        let url = AppGroup.resolveDataFileURL(groupContainer: group, documents: documents)
        #expect(try String(contentsOf: url, encoding: .utf8) == "dati")
        #expect(!FileManager.default.fileExists(atPath: documents.appendingPathComponent("exams.json").path))
    }

    @Test func keepsExistingGroupFile() throws {
        try Data("vecchi".utf8).write(to: documents.appendingPathComponent("exams.json"))
        try Data("gruppo".utf8).write(to: group.appendingPathComponent("exams.json"))
        let url = AppGroup.resolveDataFileURL(groupContainer: group, documents: documents)
        #expect(try String(contentsOf: url, encoding: .utf8) == "gruppo")
    }
}

/// xtool con account gratuito riscrive bundle ID e gruppi aggiungendo il prefisso `XTL-<id>.`.
@Suite struct GroupIdentifierTests {
    @Test func appBundleIDWithXtoolPrefix() {
        #expect(AppGroup.groupIdentifier(forBundleID: "XTL-ABCD1234.com.Tommaso.ExamsTrack")
            == "group.XTL-ABCD1234.com.Tommaso.ExamsTrack")
    }

    @Test func widgetBundleIDSharesAppGroup() {
        #expect(AppGroup.groupIdentifier(forBundleID: "XTL-ABCD1234.com.Tommaso.ExamsTrack.Widget")
            == "group.XTL-ABCD1234.com.Tommaso.ExamsTrack")
    }

    @Test func plainBundleID() {
        #expect(AppGroup.groupIdentifier(forBundleID: "com.Tommaso.ExamsTrack") == "group.com.Tommaso.ExamsTrack")
    }

    @Test func missingBundleIDUsesDefault() {
        #expect(AppGroup.groupIdentifier(forBundleID: nil) == "group.com.Tommaso.ExamsTrack")
    }
}
