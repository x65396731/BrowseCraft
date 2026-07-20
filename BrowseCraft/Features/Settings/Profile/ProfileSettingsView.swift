import SwiftUI

struct ProfileSettingsView: View {
    @Binding var displayName: String
    @Binding var email: String

    var body: some View {
        Form {
            Section("Personal Profile") {
                TextField("Display Name", text: self.$displayName)
                    .textInputAutocapitalization(.words)

                TextField("Email", text: self.$email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Profile")
    }
}
