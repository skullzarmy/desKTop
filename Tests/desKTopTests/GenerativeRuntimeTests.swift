import Foundation
import desKTopCore

public struct GenerativeRuntimeTests {
    public static func run() throws {
        // 1. Aleatory decompress raw UTF-8
        let rawCode = "function render() { console.log('render'); }"
        let decompressedRaw = try AleatoryRuntime.decompress(code: rawCode)
        try assertEqual(decompressedRaw, rawCode)

        // 2. Aleatory decompress Base64 string
        let base64Code = Data(rawCode.utf8).base64EncodedString()
        let decompressedB64 = try AleatoryRuntime.decompress(code: base64Code)
        try assertEqual(decompressedB64, rawCode)

        // 3. Aleatory HTML harness composition
        let harness = AleatoryRuntime.composeHTMLHarness(
            decompressedScript: rawCode,
            seed: "ooZ123456789",
            params: "{\"color\": \"#ff0000\"}"
        )
        try assertTrue(harness.contains("window.$alea"), "Harness must define $alea")
        try assertTrue(harness.contains("ooZ123456789"), "Harness must contain seed")
        try assertTrue(harness.contains("sfc32"), "Harness must contain sfc32 PRNG")

        // 4. Bootloader (BTLDR) document composition
        let btldrDoc = BootloaderRuntime.composeHTMLDocument(
            script: "console.log(window.BTLDR.seed);",
            seed: "btldr-seed-99",
            iterationNumber: 42,
            isPreview: true
        )
        try assertTrue(btldrDoc.contains("window.BTLDR"), "Doc must define window.BTLDR")
        try assertTrue(btldrDoc.contains("isPreview: true"), "Doc must pass isPreview: true")
        try assertTrue(btldrDoc.contains("iterationNumber: 42"), "Doc must include iteration number")

        // 5. EditArt parameter query formatting
        let query = EditArtRuntime.formatParameterQuery(
            parameters: ["contrast": 0.7523, "brightness": 0.4],
            seed: "editart-seed"
        )
        try assertTrue(query.contains("brightness=0.400"))
        try assertTrue(query.contains("contrast=0.752"))
        try assertTrue(query.contains("seed=editart-seed"))

        // 6. fxhash harness injection
        let baseHtml = "<html><head><title>Fx</title></head><body></body></html>"
        let injected = FxhashRuntime.injectHarness(into: baseHtml, seed: "ooABCDEF123456")
        try assertTrue(injected.contains("var fxhash = \"ooABCDEF123456\";"))
        try assertTrue(injected.contains("window.$fx"))
        try assertTrue(injected.contains("function fxpreview()"))
    }
}
