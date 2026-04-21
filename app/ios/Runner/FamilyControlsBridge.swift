import Foundation
import UIKit

#if canImport(FamilyControls)
import FamilyControls
import SwiftUI
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif

/// Wraps FamilyControls + ManagedSettings so the Flutter layer can request
/// authorization, present the Family Activity Picker, and toggle the shield.
///
/// Requirements to actually shield apps at runtime:
///   - iOS 16+ (individual authorization). iOS 15 supports the APIs but only
///     for parent→child flows.
///   - The `com.apple.developer.family-controls` entitlement, approved by
///     Apple. Without it, `AuthorizationCenter.requestAuthorization` fails
///     immediately with `.networkError` or `.invalidAccountType`.
///   - A REAL device. The iOS Simulator reports an error for the
///     authorization request.
///
/// On older iOS or missing SDK, the bridge becomes a no-op so the Flutter
/// app still launches.
final class FamilyControlsBridge: NSObject {

    private weak var presenter: UIViewController?

    #if canImport(ManagedSettings)
    private let store = ManagedSettingsStore()
    #endif

    #if canImport(FamilyControls)
    private var selection = FamilyActivitySelection()
    #endif

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
        loadSelection()
    }

    // MARK: - Authorization

    func hasAuthorization() -> Bool {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            return AuthorizationCenter.shared.authorizationStatus == .approved
        }
        #endif
        return false
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            Task { @MainActor in
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    completion(AuthorizationCenter.shared.authorizationStatus == .approved)
                } catch {
                    NSLog("FamilyControls auth failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
            return
        }
        #endif
        completion(false)
    }

    // MARK: - Picker

    func presentPicker(completion: @escaping (Bool) -> Void) {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            guard let presenter = presenter else {
                completion(false)
                return
            }
            let initial = self.selection
            let vc = UIHostingController(rootView: PickerView(
                initialSelection: initial,
                onDone: { [weak self, weak presenter] saved, updated in
                    presenter?.dismiss(animated: true) {
                        if saved, let updated = updated {
                            self?.selection = updated
                            self?.saveSelection()
                        }
                        completion(saved)
                    }
                }
            ))
            presenter.present(vc, animated: true)
            return
        }
        #endif
        completion(false)
    }

    // MARK: - Shield

    func applyShield() {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            store.shield.applications = selection.applicationTokens.isEmpty
                ? nil
                : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)
        }
        #endif
    }

    func clearShield() {
        #if canImport(ManagedSettings)
        if #available(iOS 16.0, *) {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }
        #endif
    }

    // MARK: - Persistence (selection tokens)

    private var selectionURL: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("family_selection.json")
    }

    private func saveSelection() {
        #if canImport(FamilyControls)
        guard let url = selectionURL else { return }
        do {
            let data = try JSONEncoder().encode(selection)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Failed to save selection: \(error)")
        }
        #endif
    }

    private func loadSelection() {
        #if canImport(FamilyControls)
        guard let url = selectionURL,
              let data = try? Data(contentsOf: url) else { return }
        do {
            selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            NSLog("Failed to load selection: \(error)")
        }
        #endif
    }
}

#if canImport(FamilyControls)
@available(iOS 16.0, *)
private struct PickerView: View {
    let onDone: (Bool, FamilyActivitySelection?) -> Void

    @State private var workingSelection: FamilyActivitySelection

    init(
        initialSelection: FamilyActivitySelection,
        onDone: @escaping (Bool, FamilyActivitySelection?) -> Void
    ) {
        self.onDone = onDone
        self._workingSelection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $workingSelection)
                .navigationTitle("Apps to shield")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDone(false, nil) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onDone(true, workingSelection) }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}
#endif
