import SwiftUI

// MARK: - 统一主题系统

enum AppTheme {

    // MARK: - 渐变色
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "4F7DF5"), Color(hex: "7C5CE0")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [Color(hex: "34C759"), Color(hex: "28A745")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let warningGradient = LinearGradient(
        colors: [Color(hex: "FF9500"), Color(hex: "FF6B00")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let dangerGradient = LinearGradient(
        colors: [Color(hex: "FF3B30"), Color(hex: "D32F2F")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let scoreGradient = LinearGradient(
        colors: [Color(hex: "4F7DF5"), Color(hex: "00C6FB")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - 卡片背景
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)

    // MARK: - 间距
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12

    // MARK: - 阴影
    static let cardShadow = Color.black.opacity(0.06)
}

// MARK: - View 扩展：统一卡片样式

extension View {
    func themedCard(padding: CGFloat = AppTheme.cardPadding) -> some View {
        self
            .padding(padding)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 2)
    }

    func themedSection() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

// MARK: - Color hex 初始化

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
