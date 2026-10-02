import Darwin
import Foundation

// Retains Lara's vnode redirection flow, with one exit path that always restores it.
enum KernelcacheLoader {
  static func fetch() -> Bool {
    guard ds_is_ready(), ds_get_our_proc() != 0, ds_get_our_task() != 0,
      off_proc_p_fd != 0, off_filedesc_fd_ofiles != 0,
      off_fileproc_fp_glob != 0, off_fileglob_fg_data != 0,
      off_vnode_v_data != 0, off_namecache_nc_vp != 0,
      off_namecache_nc_child_tqe_next != 0
    else { return false }

    let preboot = "/private/preboot"
    guard let pattern = try? NSRegularExpression(pattern: "^[A-Fa-f0-9]{64,128}$") else {
      return false
    }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: preboot),
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return false
    }
    let hashes = names.filter {
      pattern.firstMatch(in: $0, range: NSRange($0.startIndex..<$0.endIndex, in: $0)) != nil
    }
    guard hashes.count == 1, let hash = hashes.first else {
      return false  // Never guess among multiple boot manifests.
    }
    let source = "\(preboot)/\(hash)/System/Library/Caches/com.apple.kernelcaches/kernelcache"
    let visible = "/private/preboot/Cryptexes/OS/System/Library/CoreServices/RestoreVersion.plist"
    let destination = documents.appendingPathComponent("kernelcache").path
    var originalVnode: UInt64 = 0
    var originalData: UInt64 = 0
    guard source.withCString({ vn_fileredirect(visible, $0, &originalVnode, &originalData) }) else {
      return false
    }
    defer { vn_fileunredirect(originalVnode, originalData) }

    let input = open(visible, O_RDONLY)
    guard input >= 0 else { return false }
    defer { close(input) }
    let output = open(destination, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard output >= 0 else { return false }
    defer { close(output) }
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    var total = 0
    while true {
      let amount = buffer.withUnsafeMutableBytes { read(input, $0.baseAddress, $0.count) }
      if amount < 0 { return false }
      if amount == 0 { break }
      var written = 0
      while written < amount {
        let count = buffer.withUnsafeBytes { bytes in
          write(output, bytes.baseAddress!.advanced(by: written), amount - written)
        }
        if count <= 0 { return false }
        written += count
      }
      total += amount
    }
    guard total > 2 else { return false }
    guard let handle = FileHandle(forReadingAtPath: destination) else { return false }
    let magic = handle.readData(ofLength: 2)
    handle.closeFile()
    return magic == Data([0x30, 0x84])
  }
}
