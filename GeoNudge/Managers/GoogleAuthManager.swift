import GoogleSignIn
import UIKit

@Observable @MainActor final class GoogleAuthManager {
    var currentUser: GIDGoogleUser? = nil
    var isSignedIn: Bool { currentUser != nil }

    func restorePreviousSignIn() async {
        currentUser = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    func signIn(presenting vc: UIViewController) async throws {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: vc)
        currentUser = result.user
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }
}
