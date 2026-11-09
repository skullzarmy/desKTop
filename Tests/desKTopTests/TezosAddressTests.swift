import Foundation
import desKTopCore

public struct TezosAddressTests {
    public static func run() throws {
        let tz1 = "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"
        let tz2 = "tz2V4g47nNpSVDH9Sj67uK6Y2W9L8oZ19r4m"
        let tz3 = "tz3RDC3JdnUmAGAJayqaYSuKN9gyPv2BKqm5"
        let kt1 = "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"

        let addr1 = TezosAddress(tz1)
        try assertNotNil(addr1)
        try assertEqual(addr1?.type, .tz1)
        try assertEqual(addr1?.raw, tz1)

        let addr2 = TezosAddress(tz2)
        try assertNotNil(addr2)
        try assertEqual(addr2?.type, .tz2)

        let addr3 = TezosAddress(tz3)
        try assertNotNil(addr3)
        try assertEqual(addr3?.type, .tz3)

        let addr4 = TezosAddress(kt1)
        try assertNotNil(addr4)
        try assertEqual(addr4?.type, .kt1)
        try assertTrue(TezosAddressValidator.isContract(kt1))

        // Invalid tests
        try assertNil(TezosAddress("tz1short"))
        try assertNil(TezosAddress("tz1VSUr8wwNhLAzempoch5d6hLRiTh8CjcjbEXTRA"))
        try assertNil(TezosAddress("tz5VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        try assertNil(TezosAddress("tz10OUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
    }
}
