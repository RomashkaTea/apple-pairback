import Combine
import Darwin
import Foundation

@MainActor
final class AccessController: ObservableObject {
  static let shared = AccessController()

  @Published private(set) var isWorking = false
  @Published private(set) var isReady = false
  @Published private(set) var progress = 0.0
  @Published private(set) var message = "Access has not been prepared."

  private init() {}

  static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard name.withCString({ sysctlbyname($0, nil, &size, nil, 0) }) == 0,
      size > 1, size < 256
    else { return nil }
    var bytes = [CChar](repeating: 0, count: size)
    guard name.withCString({ sysctlbyname($0, &bytes, &size, nil, 0) }) == 0 else { return nil }
    return String(cString: bytes)
  }

  static var isExactTarget: Bool {
    sysctlString("hw.machine") == "iPhone17,1" && sysctlString("kern.osversion") == "22G100"
  }

  private static var isDebugged: Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    return sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0
      && (info.kp_proc.p_flag & 0x800) != 0
  }

  func prepare() {
    guard !isWorking, !isReady else { return }
    guard Self.isExactTarget else {
      message = "PairBack only supports iPhone17,1 on iOS build 22G100."
      return
    }
    guard !Self.isDebugged else {
      message = "Close the debugger before preparing access."
      return
    }
    isWorking = true
    progress = 0
    message = "Running Lara's DarkSword access method…"
    init_offsets()
    offsets_init()
    ds_set_progress_callback { value in
      DispatchQueue.main.async { AccessController.shared.progress = value }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let kernelReady = ds_run() == 0 && ds_is_ready()
      guard kernelReady else {
        DispatchQueue.main.async {
          AccessController.shared.message = "Kernel access failed; no pairing settings changed."
          AccessController.shared.isWorking = false
        }
        return
      }
      let offsetsReady =
        emergencyfixfunctiontobereplacedlateronquestionmark()
        || (KernelcacheLoader.fetch() && dlkcache())
      guard offsetsReady else {
        DispatchQueue.main.async {
          AccessController.shared.message = "Could not load offsets; no pairing settings changed."
          AccessController.shared.isWorking = false
        }
        return
      }
      DispatchQueue.main.async { AccessController.shared.message = "Opening file access…" }
      let sandboxReady = sbx_escape(ds_get_our_proc()) == 0
      DispatchQueue.main.async {
        AccessController.shared.isReady = sandboxReady
        AccessController.shared.message =
          sandboxReady
          ? "Access ready. Read the values, then Apply."
          : "File access failed; no pairing settings changed."
        AccessController.shared.isWorking = false
      }
    }
  }

  func overwrite(_ data: Data, at path: String) throws {
    guard isReady else { throw PairBackError("Prepare Access first") }
    let file = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard file >= 0 else { throw PairBackError("Open failed at \(path): errno \(errno)") }
    defer { close(file) }
    var offset = 0
    try data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      while offset < bytes.count {
        let amount = write(file, base.advanced(by: offset), bytes.count - offset)
        guard amount > 0 else { throw PairBackError("Write failed at \(path): errno \(errno)") }
        offset += amount
      }
    }
    guard ftruncate(file, off_t(data.count)) == 0, fsync(file) == 0 else {
      throw PairBackError("Could not finish writing \(path): errno \(errno)")
    }
    guard try Data(contentsOf: URL(fileURLWithPath: path)) == data else {
      throw PairBackError("Readback differs at \(path)")
    }
  }
}
