import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UsernameSetupView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var username: String = ""
    @State private var status: Status = .idle
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    @State private var checkWorkItem: DispatchWorkItem?
    @State private var showPhotoSetup = false
    @State private var currentUID: String? = nil
    
    enum Status: Equatable {
        case idle
        case invalid(String)
        case checking
        case available
        case taken
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a unique username")
                    .font(.title2).bold()
                Text("This will be your public handle. You can change it later (subject to availability).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .submitLabel(.done)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .onChange(of: username) { _, _ in
                        debouncedCheck()
                    }
                    .onSubmit { Task { await claimTapped() } }
                
                statusView
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                
                Button(action: { Task { await claimTapped() } }) {
                    HStack {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text("Continue").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isContinueEnabled ? Color.accentColor : Color.accentColor.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!isContinueEnabled)
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
            .onAppear {
                focused = true
                // Lazily fetch UID after Firebase is configured
                currentUID = Auth.auth().currentUser?.uid
            }
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: $showPhotoSetup) {
            ProfileImageSetupView()
                .interactiveDismissDisabled(true)
        }
    }
    
    // MARK: - Computed
    private var borderColor: Color {
        switch status {
        case .idle: return .clear
        case .invalid: return .red.opacity(0.6)
        case .checking: return .yellow.opacity(0.6)
        case .available: return .green.opacity(0.7)
        case .taken: return .red.opacity(0.6)
        }
    }
    
    private var isContinueEnabled: Bool {
        switch status {
        case .available: return !isSubmitting
        case .idle: return isLocallyValid(username) && !isSubmitting // allow press; server enforces
        default: return !isSubmitting && isLocallyValid(username)
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            Text("Use 3–20 letters, numbers, dots, or underscores.")
                .font(.footnote).foregroundStyle(.secondary)
        case .invalid(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.red)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking availability…").font(.footnote)
            }
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        case .taken:
            Label("Already taken", systemImage: "xmark.circle.fill")
                .font(.footnote).foregroundStyle(.red)
        }
    }
    
    // MARK: - Logic
    private func debouncedCheck() {
        errorMessage = nil
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let msg = validate(trimmed) {
            status = .invalid(msg)
            return
        }
        status = .checking
        checkWorkItem?.cancel()
        let work = DispatchWorkItem { Task { await availabilityCheck(for: trimmed) } }
        checkWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    private func isLocallyValid(_ s: String) -> Bool { validate(s.trimmingCharacters(in: .whitespacesAndNewlines)) == nil }
    
    private func validate(_ s: String) -> String? {
        if s.isEmpty { return "" }
        if s.count < 3 { return "Too short (min 3)." }
        if s.count > 20 { return "Too long (max 20)." }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        if s.rangeOfCharacter(from: allowed.inverted) != nil { return "Only letters, numbers, . and _." }
        if s.hasPrefix(".") || s.hasSuffix(".") || s.hasPrefix("_") || s.hasSuffix("_") {
            return "Cannot start or end with . or _."
        }
        return nil
    }
    
    private func availabilityCheck(for raw: String) async {
        let lower = raw.lowercased()
        do {
            let doc = try await Firestore.firestore().collection("usernames").document(lower).getDocument()
            await MainActor.run {
                status = (doc.exists ? .taken : .available)
            }
        } catch {
            print("[UsernameSetup] availability error:", error.localizedDescription)
            await MainActor.run { status = .idle; errorMessage = error.localizedDescription }
        }
    }
    
    private func claimTapped() async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let msg = validate(trimmed) { status = .invalid(msg); return }
        guard let uid = currentUID ?? Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in."; return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            try await claimUsernameBatch(username: trimmed, uid: uid)
            print("[UsernameSetup] ✅ batch committed, username set, moving to photo step")
            await MainActor.run {
                isSubmitting = false
                showPhotoSetup = true
            }
        } catch {
            let ns = error as NSError
            print("[UsernameSetup] ❌ batch failed code=\(ns.code) domain=\(ns.domain) msg=\(ns.localizedDescription)")
            await MainActor.run {
                isSubmitting = false
                errorMessage = ns.localizedDescription
                status = .taken // most common failure path
            }
        }
    }
    
    /// Robust, rule-compliant write:
    /// 1) Reserve usernames/{lower} = { uid }
    /// 2) Set users/{uid}.username + .usernameLower + updatedAt
    /// 3) If renaming, delete old reservation
    private func claimUsernameBatch(username: String, uid: String) async throws {
        let db = Firestore.firestore()
        let lower = username.lowercased()
        let unameRef = db.collection("usernames").document(lower)
        let userRef  = db.collection("users").document(uid)
        
        print("[UsernameSetup] begin claim: \(username) (\(lower)) for uid \(uid)")
        
        // Read current user once to know if we must release previous reservation
        let userSnap = try await userRef.getDocument()
        let oldLower = (userSnap.get("usernameLower") as? String)?.lowercased()
        if let oldLower, !oldLower.isEmpty {
            print("[UsernameSetup] existing usernameLower=\(oldLower) -> will release if changed")
        } else {
            print("[UsernameSetup] no existing usernameLower on profile")
        }
        
        // Build batch
        let batch = db.batch()
        
        // 1) Reserve the new handle (rules: usernames create allowed only if not exists and maps to caller)
        batch.setData(["uid": uid], forDocument: unameRef, merge: false)
        
        // 2) Upsert user doc (rules allow updating usernameLower only if a reservation exists-after and maps to uid)
        batch.setData([
            "username": username,
            "usernameLower": lower,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: userRef, merge: true)
        
        // 3) If renaming, release the old reservation
        if let old = oldLower, !old.isEmpty, old != lower {
            let oldRef = db.collection("usernames").document(old)
            batch.deleteDocument(oldRef)
            print("[UsernameSetup] will delete old reservation \(old)")
        }
        
        // Commit
        do {
            try await batch.commit()
        } catch {
            let ns = error as NSError
            // Common permission messages you might see:
            // - "Missing or insufficient permissions."
            // - "PERMISSION_DENIED: ..." (when rules reject)
            // - "ALREADY_EXISTS" if someone nabbed the handle between check & write
            print("[UsernameSetup] commit error code=\(ns.code) domain=\(ns.domain) msg=\(ns.localizedDescription)")
            throw error
        }
    }
}
