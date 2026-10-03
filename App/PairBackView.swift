import SwiftUI

struct PairBackView: View {
  @ObservedObject private var access = AccessController.shared
  @ObservedObject private var store = PairingStore.shared

  var body: some View {
    Form {
      Section("Support") {
        Text("DarkSword: iOS 17.0–18.7.1 or 26.0–26.0.1")
        Text(
          "PairBack changes the three settings used to pair a Series 10 on watchOS 26.5. Pairing was verified on iPhone 16 Pro with iOS 18.6.2."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      Section("1 · Prepare access") {
        Button("Prepare Access") { access.prepare() }
          .disabled(access.isWorking || access.isReady || store.isBusy)
        if access.isWorking { ProgressView(value: access.progress) }
        Text(access.message)
          .font(.footnote)
          .textSelection(.enabled)
      }
      Section("2 · Pairing settings") {
        Button("Read current values") { store.refresh() }
          .disabled(!access.isReady || store.isBusy)
        Button("Apply all three settings") { store.apply() }
          .disabled(!access.isReady || store.isBusy || store.hasOwnerReceipts)
        Button("Restore saved values") { store.restore() }
          .disabled(
            !access.isReady || store.isBusy || !store.backupAvailable || store.hasOwnerReceipts)
        if store.hasOwnerReceipts {
          Button("Repair file ownership") { store.repairOwnership() }
            .disabled(!access.isReady || store.isBusy)
        }
      }
      Section("Result") {
        Text(store.message)
          .textSelection(.enabled)
        if let status = store.status {
          Text(status.summary)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
        }
      }
      Section("After applying") {
        Text(
          "Restart the iPhone normally before pairing. PairBack only prepares local settings; it does not update iOS, erase the watch, or install a full jailbreak."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("PairBack")
    .onChange(of: access.isReady) { _, ready in
      if ready { store.refresh() }
    }
  }
}
