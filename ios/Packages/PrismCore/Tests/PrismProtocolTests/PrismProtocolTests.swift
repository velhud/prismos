import Foundation
import XCTest
import PrismProtocol

final class PrismProtocolTests: XCTestCase {
    func testEncodeDecodeHeaderUsesDocumentedThirteenByteLayout() throws {
        let header = PrismFrameHeader(
            kind: .draw,
            flags: [.start, .end],
            messageID: 0x1234,
            sequence: 0x0002,
            totalLength: 0x01020304
        )

        let encoded = PrismProtocolCodec.encode(header)

        XCTAssertEqual(encoded.count, 13)
        XCTAssertEqual([UInt8](encoded), [
            0x50, 0x4D, 0x01, 0x05, 0x03,
            0x34, 0x12,
            0x02, 0x00,
            0x04, 0x03, 0x02, 0x01
        ])
        XCTAssertEqual(try PrismProtocolCodec.decodeHeader(from: encoded), header)
    }

    func testRejectsBadMagicAndVersion() {
        var badMagic = Data([0x00, 0x4D, 0x01, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try PrismProtocolCodec.decodeHeader(from: badMagic)) { error in
            XCTAssertEqual(error as? PrismProtocolError, .badMagic)
        }

        badMagic[0] = 0x50
        badMagic[2] = 0x02
        XCTAssertThrowsError(try PrismProtocolCodec.decodeHeader(from: badMagic)) { error in
            XCTAssertEqual(error as? PrismProtocolError, .unsupportedVersion(0x02))
        }
    }

    func testSplitsAndReassemblesKnownLengthPayload() throws {
        let payload = Data("abcdefghi".utf8)
        let frames = try PrismFrameSplitter().split(
            kind: .controlJSON,
            payload: payload,
            messageID: 7,
            maxWriteLength: PrismProtocolConstants.headerByteCount + 3
        )

        XCTAssertEqual(frames.map(\.header.sequence), [0, 1, 2])
        XCTAssertTrue(frames[0].header.flags.contains(.start))
        XCTAssertTrue(frames[2].header.flags.contains(.end))

        let reassembler = PrismFrameReassembler()
        XCTAssertNil(try reassembler.ingest(frames[0], now: 0))
        XCTAssertNil(try reassembler.ingest(frames[1], now: 0))
        let message = try reassembler.ingest(frames[2], now: 0)
        XCTAssertEqual(message?.kind, .controlJSON)
        XCTAssertEqual(message?.messageID, 7)
        XCTAssertEqual(message?.payload, payload)
    }

    func testRejectsSequenceGap() throws {
        let payload = Data("abcdef".utf8)
        var frames = try PrismFrameSplitter().split(
            kind: .controlJSON,
            payload: payload,
            messageID: 8,
            maxWriteLength: PrismProtocolConstants.headerByteCount + 3
        )
        frames[1].header.sequence = 3

        let reassembler = PrismFrameReassembler()
        XCTAssertNil(try reassembler.ingest(frames[0], now: 0))
        XCTAssertThrowsError(try reassembler.ingest(frames[1], now: 0)) { error in
            XCTAssertEqual(error as? PrismProtocolError, .sequenceGap(expected: 1, actual: 3))
        }
    }

    func testRejectsOversizedKnownLengthBeforePayloadAllocation() {
        let header = PrismFrameHeader(
            kind: .controlJSON,
            flags: .start,
            messageID: 9,
            sequence: 0,
            totalLength: UInt32(PrismProtocolConstants.maxControlJSONBytes + 1)
        )
        let frame = PrismFrame(header: header, payloadFragment: Data("{} \n".utf8))

        XCTAssertThrowsError(try PrismFrameReassembler().ingest(frame, now: 0)) { error in
            XCTAssertEqual(
                error as? PrismProtocolError,
                .totalLengthExceedsLimit(
                    kind: .controlJSON,
                    total: UInt32(PrismProtocolConstants.maxControlJSONBytes + 1),
                    limit: PrismProtocolConstants.maxControlJSONBytes
                )
            )
        }
    }

    func testReassemblesUnknownLengthAudioAndImageStreams() throws {
        let audio = try PrismFrameSplitter().split(
            kind: .streamAudio,
            payload: Data([0x01, 0x02, 0xFF, 0x80]),
            messageID: 10,
            maxWriteLength: PrismProtocolConstants.headerByteCount + 2,
            knownLength: false
        )
        let image = try PrismFrameSplitter().split(
            kind: .streamImage,
            payload: Data("jpeg".utf8),
            messageID: 11,
            maxWriteLength: PrismProtocolConstants.headerByteCount + 3,
            knownLength: false
        )

        XCTAssertTrue(audio.allSatisfy { $0.header.totalLength == PrismProtocolConstants.totalLengthUnknown })
        XCTAssertEqual(try reassemble(audio), Data([0x01, 0x02, 0xFF, 0x80]))
        XCTAssertEqual(try reassemble(image), Data("jpeg".utf8))
    }

    func testRejectsOversizedUnknownLengthStream() throws {
        let start = PrismFrame(
            header: PrismFrameHeader(
                kind: .streamAudio,
                flags: .start,
                messageID: 12,
                sequence: 0,
                totalLength: PrismProtocolConstants.totalLengthUnknown
            ),
            payloadFragment: Data(repeating: 0, count: PrismProtocolConstants.maxAudioStreamBytes)
        )
        let end = PrismFrame(
            header: PrismFrameHeader(
                kind: .streamAudio,
                flags: .end,
                messageID: 12,
                sequence: 1,
                totalLength: PrismProtocolConstants.totalLengthUnknown
            ),
            payloadFragment: Data([1])
        )

        let reassembler = PrismFrameReassembler()
        XCTAssertNil(try reassembler.ingest(start, now: 0))
        XCTAssertThrowsError(try reassembler.ingest(end, now: 0)) { error in
            XCTAssertEqual(
                error as? PrismProtocolError,
                .totalLengthExceedsLimit(
                    kind: .streamAudio,
                    total: UInt32(PrismProtocolConstants.maxAudioStreamBytes + 1),
                    limit: PrismProtocolConstants.maxAudioStreamBytes
                )
            )
        }
    }

    func testTimesOutIncompleteStream() throws {
        let start = PrismFrame(
            header: PrismFrameHeader(
                kind: .streamImage,
                flags: .start,
                messageID: 13,
                sequence: 0,
                totalLength: PrismProtocolConstants.totalLengthUnknown
            ),
            payloadFragment: Data("abc".utf8)
        )
        let end = PrismFrame(
            header: PrismFrameHeader(
                kind: .streamImage,
                flags: .end,
                messageID: 13,
                sequence: 1,
                totalLength: PrismProtocolConstants.totalLengthUnknown
            ),
            payloadFragment: Data("def".utf8)
        )

        let reassembler = PrismFrameReassembler(timeout: 1)
        XCTAssertNil(try reassembler.ingest(start, now: 0))
        XCTAssertThrowsError(try reassembler.ingest(end, now: 2)) { error in
            XCTAssertEqual(error as? PrismProtocolError, .timedOut)
        }
    }

    func testOutboundGateAllowsOnlyOneActiveDownlinkMessage() {
        var gate = PrismOutboundGate()

        XCTAssertTrue(gate.begin(messageID: 1))
        XCTAssertFalse(gate.begin(messageID: 2))
        gate.finish(messageID: 2)
        XCTAssertTrue(gate.hasActiveMessage)
        gate.finish(messageID: 1)
        XCTAssertFalse(gate.hasActiveMessage)
        XCTAssertTrue(gate.begin(messageID: 2))
    }

    private func reassemble(_ frames: [PrismFrame]) throws -> Data? {
        let reassembler = PrismFrameReassembler()
        var complete: PrismCompleteMessage?
        for frame in frames {
            complete = try reassembler.ingest(frame, now: 0)
        }
        return complete?.payload
    }
}
