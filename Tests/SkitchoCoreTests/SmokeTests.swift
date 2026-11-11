import Foundation
import Testing

@testable import SkitchoCore

@Suite struct CoreSmokeTests {
  @Test func moduleImports() {
    #expect(SkitchoCore.moduleName == "SkitchoCore")
  }

  @Test func runsOnArm64() {
    #if !arch(arm64)
      Issue.record("Skitcho must be built for arm64")
    #endif
  }

  @Test func notTranslatedByRosetta() {
    var translated: Int32 = -1
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
    // The key may be absent on some systems; absence means "not translated".
    #expect(rc != 0 || translated == 0)
  }
}
