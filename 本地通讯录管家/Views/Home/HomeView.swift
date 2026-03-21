import SwiftUI

struct HomeView: View {
    @ObservedObject var appVM: AppViewModel
    @State private var showPermissionAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !appVM.isAuthorized {
                    permissionView
                } else if appVM.isLoading {
                    loadingView
                } else if let error = appVM.errorMessage {
                    errorView(message: error)
                } else {
                    healthScoreCard
                    statsSection
                    issuesSection
                }
            }
            .padding()
        }
        .navigationTitle("通讯录管家")
        .refreshable {
            await appVM.refresh()
        }
        .onAppear {
            appVM.checkAuthorization()
        }
        .searchable(text: $appVM.searchText, prompt: "搜索联系人")
    }

    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("需要访问您的通讯录")
                .font(.title2.bold())

            Text("本应用仅在本地处理您的通讯录数据\n不会上传到任何服务器")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await appVM.requestAccess() }
            } label: {
                Text("授权访问通讯录")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在扫描通讯录...")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await appVM.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    private var healthScoreCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(appVM.healthReport.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(appVM.healthReport.score)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("健康分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(appVM.healthReport.totalContacts) 位联系人")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var scoreColor: Color {
        let score = appVM.healthReport.score
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(icon: "person.2.fill", value: "\(appVM.healthReport.totalContacts)", title: "联系人", color: .blue)
            StatCard(icon: "phone.fill", value: "\(appVM.healthReport.totalPhoneNumbers)", title: "手机号", color: .green)
            StatCard(icon: "envelope.fill", value: "\(appVM.healthReport.totalEmails)", title: "邮箱", color: .orange)
        }
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appVM.healthReport.issueItems.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("通讯录状态良好，无需优化")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("可优化项目")
                    .font(.headline)

                ForEach(appVM.healthReport.issueItems) { item in
                    NavigationLink {
                        IssueContactsView(
                            title: item.title,
                            issueType: item.issueType,
                            contacts: appVM.contactsForIssue(item.issueType)
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.title3)
                                .foregroundStyle(item.color)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.bold())
                                Text("\(item.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
