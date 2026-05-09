import SwiftUI

struct ContactRow: View {
    let contact: ContactItem

    private static let avatarColors: [Color] = [
        Color(hex: "4F7DF5"), Color(hex: "7C5CE0"), Color(hex: "00B4D8"),
        Color(hex: "E17055"), Color(hex: "00B894"), Color(hex: "6C5CE7"),
        Color(hex: "FD79A8"), Color(hex: "FDCB6E")
    ]

    private var avatarColor: Color {
        let hash = abs(contact.id.hashValue)
        return Self.avatarColors[hash % Self.avatarColors.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            // 彩色头像
            Text(String(contact.initials))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                if let phone = contact.phoneNumbers.first {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(phone.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let email = contact.emailAddresses.first {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(email.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
