import SwiftUI

struct OptimizedHomeView: View {
    @ObservedObject var appVM: AppViewModel
    @StateObject private var cleanupVM = CleanupViewModel()
    @State private var selectedIssueType: HealthReport.IssueType?
    @State private var showIssueDetail = false
    @State private var showWriteBack = false
    @State private var showRestoreConfirm = false
    @State private var writeBackResult: (success: Int, failed: Int)?
    @State private var showPreExecute = false
    @State private var preExecuteResult: [ContactItem]?
    
    // 存储用户选择的联系人（用于排除）
    @State private var selectedContactIDs: Set<ContactItem.ID> = []
    // 存储用户忽略的问题
    @State private var ignoredIssues: Set<HealthReport.IssueType> = []
    // 处理状态
    @State private var isProcessing = false

    public var body: some View {
        ZStack {
            // 主内容
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
                        actionSection
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("home.scroll")
            .navigationTitle("通讯录管家")
            .refreshable {
                await appVM.refresh()
            }
            .onAppear {
                appVM.checkAuthorization()
            }
            .searchable(text: $appVM.searchText, prompt: "搜索联系人")
            .sheet(isPresented: $showIssueDetail) {
                if let issueType = selectedIssueType {
                    IssueDetailView(
                        title: appVM.issueTitle(for: issueType),
                        issueType: issueType,
                        contacts: appVM.contactsForIssue(issueType),
                        selectedContactIDs: $selectedContactIDs,
                        onPreExecute: { await preExecute(for: issueType) },
                        onIgnore: { ignoreIssue(issueType) },
                        appVM: appVM
                    )
                }
            }
            .sheet(isPresented: $showPreExecute) {
                if let result = preExecuteResult {
                    PreExecuteResultView(
                        contacts: result,
                        onWriteBack: { showWriteBack = true }
                    )
                }
            }
            .alert("写入系统通讯录", isPresented: $showWriteBack) {
                Button("取消", role: .cancel) {}
                if !cleanupVM.isWritingBack {
                    Button("确认写入", role: .destructive) {
                        Task {
                            writeBackResult = await cleanupVM.writeBackToSystemDirect()
                        }
                    }
                }
            } message: {
                if cleanupVM.isWritingBack {
                    VStack(spacing: 12) {
                        Text("正在写入，请稍候...")
                        ProgressView(value: cleanupVM.writeBackProgress)
                            .tint(.blue)
                            .padding(.horizontal, 20)
                        Text("\(Int(cleanupVM.writeBackProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("将写入 \(cleanupVM.processedContacts.count) 位联系人（已自动备份）")
                }
            }
            .alert("写入完成", isPresented: .init(
                get: { writeBackResult != nil },
                set: { if !$0 { writeBackResult = nil } }
            )) {
                Button("确定") {
                    writeBackResult = nil
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await appVM.refresh()
                    }
                }
            } message: {
                if let result = writeBackResult {
                    Text("成功写入 \(result.success) 位联系人" + (result.failed > 0 ? "，失败 \(result.failed) 位" : ""))
                }
            }
            .alert("恢复通讯录", isPresented: $showRestoreConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认恢复", role: .destructive) {
                    Task {
                        let ok = await cleanupVM.restoreFromBackup()
                        if ok {
                            await appVM.refresh()
                        }
                    }
                }
            } message: {
                Text("将从备份文件恢复通讯录到备份时的状态")
            }
            
            // 加载动画
            if appVM.isLoading {
                Color(.systemBackground).opacity(0.95)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(2.0)
                                .tint(.blue)
                            Text("通讯录健康分析中...")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("正在分析联系人数据，请稍候")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            if appVM.loadedContactsCount > 0 {
                                Text("已加载 \(appVM.loadedContactsCount) 位联系人")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            
            // 处理中动画
            if isProcessing {
                Color(.systemBackground).opacity(0.95)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(2.0)
                                .tint(.blue)
                            Text("正在处理: \(selectedIssueType?.rawValue ?? "问题")")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("正在优化联系人数据，请稍候")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
            }
        }
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
            .accessibilityIdentifier("home.requestContactsButton")
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
            .accessibilityIdentifier("home.retryButton")
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
        .accessibilityIdentifier("home.healthScoreCard")
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
        .accessibilityIdentifier("home.statsSection")
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appVM.isLoading {
                HStack {
                    ProgressView()
                    Text("正在分析通讯录...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if filteredIssueItems.isEmpty {
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

                ForEach(Array(filteredIssueItems.enumerated()), id: \.element.issueType) { index, item in
                    Button {
                        selectedIssueType = item.issueType
                        selectedContactIDs.removeAll() // 重置选择
                        showIssueDetail = true
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
                                Text(item.description)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(index == 0 ? "home.issueRow.first" : "home.issueRow.\(item.issueType.rawValue)")
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if cleanupVM.hasBackup {
                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("从备份恢复")
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            if !filteredIssueItems.isEmpty {
                Button {
                    Task {
                        // 备份当前通讯录
                        _ = await cleanupVM.backupContacts(appVM.contacts)
                        
                        // 使用当前已更新的联系人数据
                        cleanupVM.processedContacts = appVM.contacts
                        
                        // 显示写入确认弹窗
                        showWriteBack = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                        Text("写入系统通讯录")
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityIdentifier("home.writeToSystemButton")
            }
        }
        .accessibilityIdentifier("home.actionSection")
    }

    private var filteredIssueItems: [HealthReport.IssueItem] {
        appVM.healthReport.issueItems.filter { !ignoredIssues.contains($0.issueType) }.sorted { $0.count > $1.count }
    }

    private func preExecute(for issueType: HealthReport.IssueType) async {
        // 显示加载动画
        isProcessing = true
        
        // 预执行特定问题的优化
        
        // 根据 issueType 设置相应的清理选项
        switch issueType {
        case .nameNeedsStandardize, .nameNotSplit:
            cleanupVM.selectedOptions = [.nameNormalization]
        case .phonePrefixInconsistent:
            cleanupVM.selectedOptions = [.phonePrefixUnify]
        case .phoneLabelInconsistent:
            cleanupVM.selectedOptions = [.phoneLabelUnify]
        case .phoneDuplicate:
            cleanupVM.selectedOptions = [.phoneDeduplicate]
        case .phoneGarbled:
            cleanupVM.selectedOptions = [.phoneClean]
        case .emailLabelInconsistent:
            cleanupVM.selectedOptions = [.emailLabelUnify]
        case .emailDuplicate:
            cleanupVM.selectedOptions = [.emailDeduplicate]
        case .emailInvalid:
            cleanupVM.selectedOptions = [.emailValidation]
        case .contactDuplicate:
            cleanupVM.selectedOptions = [.contactDeduplicate]
        case .emptyContact:
            cleanupVM.selectedOptions = [.removeEmptyContacts]
        }
        
        var processed: [ContactItem]
        
        // 对于所有问题，都处理整个联系人列表，通过 excludedContactIDs 控制只处理选中的联系人
        let selectedIDs = selectedContactIDs
        let allContacts = appVM.contacts
        
        // 排除未选中的联系人
        cleanupVM.excludedContactIDs = Set(allContacts.map { $0.id }).subtracting(selectedIDs)
        
        // 在后台线程执行清理操作
        processed = await cleanupVM.runCleanup(on: allContacts)

        await MainActor.run {
            updateContacts(with: processed)
            isProcessing = false
            preExecuteResult = processed
            showIssueDetail = false
        }
        // 关闭问题详情后再展示预执行结果，避免双 sheet 冲突
        try? await Task.sleep(nanoseconds: 600_000_000)
        await MainActor.run {
            showPreExecute = true
        }
    }
    
    private func updateContacts(with processedContacts: [ContactItem]) {
        // 直接使用处理后的联系人数据替换原始数据
        // 因为 runCleanup 已经返回了完整的联系人列表，包括未处理的和处理后的
        appVM.contacts = processedContacts
        appVM.healthReport = HealthAnalyzer.analyze(processedContacts)
    }

    private func ignoreIssue(_ issueType: HealthReport.IssueType) {
        ignoredIssues.insert(issueType)
        showIssueDetail = false
    }
}

struct IssueDetailView: View {
    let title: String
    let issueType: HealthReport.IssueType
    let contacts: [ContactItem]
    @Binding var selectedContactIDs: Set<ContactItem.ID>
    let onPreExecute: () async -> Void
    let onIgnore: () -> Void
    @ObservedObject var appVM: AppViewModel
    
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isContentLoaded = false
    @State private var duplicateContacts: [ContactItem] = []

    var displayedContacts: [ContactItem] {
        if issueType == .contactDuplicate {
            return duplicateContacts
        } else {
            return contacts
        }
    }
    
    var filteredContacts: [ContactItem] {
        if searchText.isEmpty { return displayedContacts }
        return displayedContacts.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.phoneNumbers.contains(where: { $0.value.contains(searchText) })
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 主内容
                if isContentLoaded {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            HStack {
                                Text("\(displayedContacts.count) 位联系人存在「\(title)」问题")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(action: toggleSelectAll) {
                                    Text(selectedContactIDs.count == filteredContacts.count ? "取消全选" : "全选")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .accessibilityIdentifier("issue.detail.selectAll")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            if filteredContacts.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.green)
                                    Text("没有找到需要处理的联系人")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 40)
                                .frame(maxWidth: .infinity)
                            } else {
                                ForEach(filteredContacts) { contact in
                                    HStack(spacing: 12) {
                                        Button(action: { toggleSelection(contact) }) {
                                            Image(systemName: selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedContactIDs.contains(contact.id) ? .blue : .secondary)
                                                .font(.system(size: 20))
                                        }

                                        ZStack {
                                            Circle()
                                                .fill(.blue.opacity(0.15))
                                                .frame(width: 44, height: 44)
                                            Text(String(contact.initials))
                                                .font(.headline.bold())
                                                .foregroundStyle(.blue)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                                                .font(.body.bold())
                                                .lineLimit(1)

                                            issueDetail(for: contact)
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)

                                    Divider()
                                        .padding(.leading, 88)
                                }
                            }

                            VStack(spacing: 12) {
                                Button(action: { 
                                    Task {
                                        isLoading = true
                                        await onPreExecute()
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        isLoading = false
                                    }
                                }) {
                                    HStack {
                                        if isLoading {
                                            ProgressView()
                                                .tint(.white)
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                        }
                                        Text("预执行优化")
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(isLoading)
                                .accessibilityIdentifier("issue.detail.preExecute")

                                Button(action: onIgnore) {
                                    HStack {
                                        Image(systemName: "eye.slash.fill")
                                        Text("忽略此问题")
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .accessibilityIdentifier("issue.detail.ignore")
                            }
                            .padding()
                        }
                    }
                    .accessibilityIdentifier("issue.detail.scroll")
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(text: $searchText, prompt: "搜索联系人")
                }
                
                // 加载动画
                if isLoading {
                    Color(.systemBackground).opacity(0.95)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.blue)
                                Text("正在建立索引...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("请稍候，正在分析联系人数据")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                }
            }
            .onAppear {
                if issueType == .contactDuplicate {
                    isLoading = true
                    isContentLoaded = false
                    Task {
                        let duplicates = appVM.contactsForIssue(.contactDuplicate)
                        await MainActor.run {
                            self.duplicateContacts = duplicates
                            self.isLoading = false
                            self.isContentLoaded = true
                        }
                    }
                } else {
                    isLoading = false
                    isContentLoaded = true
                }
            }
            .accessibilityIdentifier("issue.detail.root")

        }
    }

    private func toggleSelectAll() {
        if selectedContactIDs.count == filteredContacts.count {
            selectedContactIDs.removeAll()
        } else {
            selectedContactIDs = Set(filteredContacts.map { $0.id })
        }
    }

    private func toggleSelection(_ contact: ContactItem) {
        if selectedContactIDs.contains(contact.id) {
            selectedContactIDs.remove(contact.id)
        } else {
            selectedContactIDs.insert(contact.id)
        }
    }

    @ViewBuilder
    private func issueDetail(for contact: ContactItem) -> some View {
        switch issueType {
        case .nameNeedsStandardize, .nameNotSplit:
            let display = contact.familyName.isEmpty ? contact.givenName : contact.familyName
            Text("姓名: \(display) → 需要拆分为姓/名")
        case .phoneGarbled:
            let phones = contact.phoneNumbers.map { $0.value }.joined(separator: ", ")
            Text("异常号码: \(phones)")
        case .phonePrefixInconsistent:
            let prefixes = Set(contact.phoneNumbers.map { extractPrefix($0.value) })
            Text("前缀混用: \(prefixes.joined(separator: ", "))")
        case .phoneLabelInconsistent:
            let labels = Set(contact.phoneNumbers.map { $0.label })
            Text("标签混用: \(labels.joined(separator: ", "))")
        case .phoneDuplicate:
            let dupes = ContactDeduplicator.findDuplicatePhonesInContact(contact)
            Text("重复号码: \(dupes.joined(separator: ", "))")
        case .emailLabelInconsistent:
            let labels = Set(contact.emailAddresses.map { $0.label })
            Text("标签混用: \(labels.joined(separator: ", "))")
        case .emailDuplicate:
            let dupes = ContactDeduplicator.findDuplicateEmailsInContact(contact)
            Text("重复邮箱: \(dupes.joined(separator: ", "))")
        case .emailInvalid:
            let invalids = contact.emailAddresses.filter { !ContactNormalizer.isValidEmail($0.value) }
            Text("无效邮箱: \(invalids.map(\.value).joined(separator: ", "))")
        case .contactDuplicate:
            Text("存在重复记录")
        case .emptyContact:
            Text("无任何联系方式")
        }
    }

    private func extractPrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "无前缀"
    }
    
}


struct PreExecuteResultView: View {
    let contacts: [ContactItem]
    let onWriteBack: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("预执行结果")
                        .font(.headline)

                    Text("已处理 \(contacts.count) 位联系人")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: onWriteBack) {
                        HStack {
                            Image(systemName: "arrow.down.to.line.circle.fill")
                            Text("写入系统通讯录")
                            Spacer()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityIdentifier("preexecute.writeSystem")
                    .padding()
                }
            }
            .accessibilityIdentifier("preexecute.result.scroll")
            .navigationTitle("预执行结果")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("preexecute.result.root")
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
