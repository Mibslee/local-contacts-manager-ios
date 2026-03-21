
import SwiftUI

struct ContactRow: View {
    let contact: ContactItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(String(contact.initials))
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                    .font(.subheadline.bold())

                if let phone = contact.phoneNumbers.first {
                    Text(phone.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let email = contact.emailAddresses.first {
                    Text(email.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

