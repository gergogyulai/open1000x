import Testing
@testable import MDRKit

@Suite struct FramingTests {
    @Test func encodesInitCommand() {
        let bytes = MDRFraming.encode(MDRFrame(type: 0x0C, seq: 0, payload: [0x00, 0x00]))
        #expect(bytes == [0x3E, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x0E, 0x3C])
    }

    @Test func escapesMarkerBytes() {
        let bytes = MDRFraming.encode(MDRFrame(type: 0x0C, seq: 0, payload: [0x3C, 0x3D, 0x3E]))
        #expect(bytes.dropFirst().dropLast().contains(0x3C) == false)
        #expect(bytes.dropFirst().dropLast().contains(0x3E) == false)
        var decoder = MDRFrameDecoder()
        #expect(decoder.feed(bytes) == [MDRFrame(type: 0x0C, seq: 0, payload: [0x3C, 0x3D, 0x3E])])
    }

    @Test func reassemblesSplitAndBackToBackFrames() {
        let a = MDRFraming.encode(MDRFrame(type: 0x01, seq: 1, payload: []))
        let b = MDRFraming.encode(MDRFrame(type: 0x0C, seq: 1, payload: [0x67, 0x17, 0x01, 0x01, 0x00, 0x00, 0x14]))
        let stream = a + b
        var decoder = MDRFrameDecoder()
        let first = decoder.feed(Array(stream[..<5]))
        let second = decoder.feed(Array(stream[5...]))
        #expect(first.isEmpty)
        #expect(second.count == 2)
        #expect(second[1].payload == [0x67, 0x17, 0x01, 0x01, 0x00, 0x00, 0x14])
    }

    @Test func rejectsBadChecksum() {
        var bytes = MDRFraming.encode(MDRFrame(type: 0x0C, seq: 0, payload: [0x22, 0x00]))
        bytes[bytes.count - 2] &+= 1
        var decoder = MDRFrameDecoder()
        #expect(decoder.feed(bytes).isEmpty)
    }
}

@Suite struct CommandTests {
    // Payloads verified against a WH-1000XM5 on firmware 2.4.1.
    @Test func noiseControl() {
        #expect(MDRCommand.setNoiseControl(mode: .ambient, ambientLevel: 10, focusOnVoice: false) == [0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0A])
        #expect(MDRCommand.setNoiseControl(mode: .noiseCancelling, ambientLevel: 20, focusOnVoice: false) == [0x68, 0x17, 0x01, 0x01, 0x00, 0x00, 0x14])
        #expect(MDRCommand.setNoiseControl(mode: .off, ambientLevel: 20, focusOnVoice: true, dragging: true) == [0x68, 0x17, 0x00, 0x00, 0x00, 0x01, 0x14])
    }

    @Test func equalizer() {
        #expect(MDRCommand.setEQPreset(EQPreset(rawValue: 0x10)) == [0x58, 0x00, 0x10, 0x00])
        #expect(MDRCommand.setEQBands(preset: .custom, bands: [8, -3, 3, 4, 0, 8]) == [0x58, 0x00, 0xA0, 0x06, 0x12, 0x07, 0x0D, 0x0E, 0x0A, 0x12])
    }

    @Test func curatedPresetsTargetManualSlot() {
        #expect(MDRCommand.setEQBands(preset: .custom, bands: CuratedEQPreset.punch.steps)
                == [0x58, 0x00, 0xA0, 0x06, 0x12, 0x08, 0x0D, 0x0E, 0x0A, 0x13])
        #expect(MDRCommand.setEQBands(preset: .custom, bands: CuratedEQPreset.clarity.steps)
                == [0x58, 0x00, 0xA0, 0x06, 0x04, 0x08, 0x0C, 0x0D, 0x0A, 0x11])
    }

    @Test func multipointAddressIsAscii() {
        let p = MDRCommand.switchSource(to: "a0-b1-c2-d3-e4-f5")
        #expect(p.prefix(2) == [0x3C, 0x01])
        #expect(String(decoding: p.dropFirst(2), as: UTF8.self) == "A0:B1:C2:D3:E4:F5")
    }
}

@MainActor
@Suite struct ParsingTests {
    private func model() -> Headphones {
        Headphones(device: .init())
    }

    private func t1(_ h: Headphones, _ hexString: String) {
        h.handle(.table1, hexString.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    private func t2(_ h: Headphones, _ hexString: String) {
        h.handle(.table2, hexString.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    @Test func parsesCapturedXM5Replies() {
        let h = model()
        t1(h, "01 00 03 00 20 16 00 00")
        #expect(h.hasTable2)
        t1(h, "23 00 62 00")
        #expect(h.battery == 98)
        t1(h, "67 17 01 01 01 01 0a")
        #expect(h.noiseMode == .ambient && h.ambientLevel == 10 && h.focusOnVoice)
        t1(h, "57 00 a0 06 12 07 0d 0e 0a 12")
        #expect(h.eqPreset == .custom && h.eqBands == [8, -3, 3, 4, 0, 8])
        t1(h, "51 00 06 15 0c 00 00 10 00 11 00 12 00 13 00 14 00 15 00 16 00 17 00 a0 00 a1 00 a2 00")
        #expect(h.eqPresets.count == 12 && h.eqPresets.last?.label == "Custom 2")
        t1(h, "fb 0c 00 01")
        #expect(h.speakToChatSensitivity == .auto && h.speakToChatTimeout == .standard)
        t1(h, "f1 0d 01 01 02 01 00 04 00 05 01 02 02 00 04 00 05 01 02")
        #expect(h.quickAccessDoubleTapOptions.map(\.rawValue) == [0, 5, 1, 2])
        t1(h, "d1 d1 00 01 13 54 4f 55 43 48 5f 50 41 4e 45 4c 5f 53 45 54 54 49 4e 47 00")
        t1(h, "d7 d1 00 00")
        #expect(h.generalSettings.first?.title == "Touch sensor control panel" && h.generalSettings.first?.isOn == true)
        t1(h, "f1 04 01 04 30 31 32 ff")
        #expect(h.voiceAssistantOptions == [.deviceDefault, .googleAssistant, .alexa, .none])
    }

    @Test func manualMatchingACuratedCurveStaysManual() {
        let h = model()
        let punchReply = "57 00 a0 06 12 08 0d 0e 0a 13"
        h.apply(.punch)
        t1(h, punchReply)
        #expect(h.activeCuratedEQ == .punch && h.eqPresetName == "Punch")

        // Choosing Manual keeps the same curve on the headset but is a different choice.
        h.setEQPreset(.custom)
        t1(h, punchReply)
        #expect(h.activeCuratedEQ == nil && h.eqPresetName == "Manual")

        // A late reply to an earlier command doesn't clear a freshly chosen preset…
        h.apply(.clarity)
        t1(h, "57 00 10 06 09 0a 0f 11 11 13")
        #expect(h.activeCuratedEQ == .clarity)
        t1(h, "57 00 a0 06 04 08 0c 0d 0a 11")
        #expect(h.activeCuratedEQ == .clarity)

        // …but a change made elsewhere afterwards (e.g. the phone app) does.
        t1(h, "59 00 a0 06 04 08 0c 0d 0a 12")
        #expect(h.activeCuratedEQ == nil && h.eqPresetName == "Manual")
    }

    @Test func parsesPairedDevices() {
        let h = model()
        t2(h, "37 02 02 31 32 3a 33 34 3a 35 36 3a 37 38 3a 39 41 3a 42 43 02 38 01 0c 07 4d 61 63 42 6f 6f 6b 41 30 3a 42 31 3a 43 32 3a 44 33 3a 45 34 3a 46 35 01 7a 02 0c 10 52 6f 62 69 6e e2 80 99 73 20 69 50 68 6f 6e 65 02")
        #expect(h.pairedDevices.count == 2)
        #expect(h.pairedDevices[0].address == "12:34:56:78:9A:BC" && h.pairedDevices[0].isPlaying)
        #expect(h.pairedDevices[0].symbolName == "laptopcomputer")
        #expect(h.pairedDevices[1].name == "Robin’s iPhone" && h.pairedDevices[1].isConnected && !h.pairedDevices[1].isPlaying)
        #expect(h.pairedDevices[1].symbolName == "iphone")
        t2(h, "41 01 03 00 01 00 01 0f 01 02 03 04 05 06 07 08 09 0a 0b 0d 0f 10 f0")
        #expect(h.voiceGuidanceLanguages.count == 15)
    }
}
