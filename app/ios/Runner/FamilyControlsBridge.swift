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
    /// The user's "apps to shield" selection.
    private var selection = FamilyActivitySelection()
    /// The user's "always allowed" selection, subtracted from `selection`
    /// when the shield is applied so those apps remain usable.
    private var allowedSelection = FamilyActivitySelection()
    #endif

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
        loadSelection()
        loadAllowedSelection()
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

    // MARK: - Picker (shielded apps)

    func presentPicker(completion: @escaping (Bool) -> Void) {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            guard let presenter = presenter else {
                completion(false)
                return
            }
            let initial = self.selection
            let vc = UIHostingController(rootView: PickerView(
                title: "Apps to shield",
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

    // MARK: - Picker (always-allowed apps)

    /// Same pattern as `presentPicker` but mutates `allowedSelection`. The
    /// selection is persisted separately and subtracted from the shielded
    /// selection when the shield is applied.
    func presentAllowedPicker(completion: @escaping (Bool) -> Void) {
        #if canImport(FamilyControls)
        if #available(iOS 16.0, *) {
            guard let presenter = presenter else {
                completion(false)
                return
            }
            let initial = self.allowedSelection
            let vc = UIHostingController(rootView: PickerView(
                title: "Always-allowed apps",
                initialSelection: initial,
                onDone: { [weak self, weak presenter] saved, updated in
                    presenter?.dismiss(animated: true) {
                        if saved, let updated = updated {
                            self?.allowedSelection = updated
                            self?.saveAllowedSelection()
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
            // Effective shield = shielded ∖ always-allowed. Computing the
            // difference at apply-time means the user can tweak either
            // selection independently and always get the expected result.
            let effectiveApps = selection.applicationTokens
                .subtracting(allowedSelection.applicationTokens)
            let effectiveCategories = selection.categoryTokens
                .subtracting(allowedSelection.categoryTokens)

            store.shield.applications = effectiveApps.isEmpty ? nil : effectiveApps
            store.shield.applicationCategories = effectiveCategories.isEmpty
                ? nil
                : .specific(effectiveCategories)
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

    // MARK: - Persistence (shielded selection)

    private var selectionURL: URL? {
        return applicationSupportURL(for: "family_selection.json")
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

    // MARK: - Persistence (always-allowed selection)

    private var allowedSelectionURL: URL? {
        return applicationSupportURL(for: "family_allowed_selection.json")
    }

    private func saveAllowedSelection() {
        #if canImport(FamilyControls)
        guard let url = allowedSelectionURL else { return }
        do {
            let data = try JSONEncoder().encode(allowedSelection)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Failed to save allowed selection: \(error)")
        }
        #endif
    }

    private func loadAllowedSelection() {
        #if canImport(FamilyControls)
        guard let url = allowedSelectionURL,
              let data = try? Data(contentsOf: url) else { return }
        do {
            allowedSelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            NSLog("Failed to load allowed selection: \(error)")
        }
        #endif
    }

    private func applicationSupportURL(for filename: String) -> URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }
}

#if canImport(FamilyControls)
@available(iOS 16.0, *)
private struct PickerView: View {
    let title: String
    let onDone: (Bool, FamilyActivitySelection?) -> Void

    @State private var workingSelection: FamilyActivitySelection

    init(
        title: String,
        initialSelection: FamilyActivitySelection,
        onDone: @escaping (Bool, FamilyActivitySelection?) -> Void
    ) {
        self.title = title
        self.onDone = onDone
        self._workingSelection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $workingSelection)
                .navigationTitle(title)
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
