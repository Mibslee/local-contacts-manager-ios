import SwiftUI

struct OptimizedHomeView: View {
    @ObservedObject var appVM: AppViewModel
    @StateObject private var cleanupVM = CleanupViewModel()
    @State private var selectedIssueType: HealthReport.IssueType?
    @State private var showWriteBack = false
    @State private var showRestoreConfirm = false
    @State private var writeBackResult: (success: Int, failed: Int)?
    @State private var showPreExecute = false
    @State private var preExecuteResult: [ContactItem]?
    @State private var showMergePreview = false
    @State private var selectedContactIDs: Set<ContactItem.ID> = []
    @State private var ignoredIssues: Set<HealthReport.IssueType> = []
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    if !appVM.isAuthorized {
                        permissionView
                    } else if appVM.isLoading {
                        Color.clear.frame(height: 200)
                    } else if let error = appVM.errorMessage {
                        errorView(message: error)
                    } else {
                        healthScoreCard
                        statsSection
                        if !filteredIssueItems.isEmpty {
                            quickActionBanner
                        }
                        if !appVM.allTags.isEmpty {
                            tagFilterBar
                        }
                        issuesSection
                        actionSection
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("home.scroll")
            .navigationTitle("通讯录管家")
            .refreshable { await appVM.refresh() }
            .onAppear { appVM.checkAuthorization() }
            .searchable(text: $appVM.searchText, prompt: "搜索联系人")
            .fullScreenCover(item: $selectedIssueType) { issueType in
                IssueDetailView(
                    title: appVM.issueTitle(for: issueType),
                    issueType: issueType,
                    selectedContactIDs: $selectedContactIDs,
                    onPreExecute: { await preExecute(for: issueType) },
                    onIgnore: { ignoreIssue(issueType) },
                    appVM: appVM,
                    onDismiss: {
                        selectedIssueType = nil
                    }
                )
            }
            .sheet(isPresented: $showPreExecute) {
                if let result = preExecuteResult {
                    PreExecuteRecordedView(
                        contactCount: result.count,
                        onDismiss: {
                            showPreExecute = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showMergePreview) {
                MergePreviewView(
                    duplicateGroups: cleanupVM.duplicateGroups,
                    onConfirm: { selectedIds in
                        cleanupVM.applyMergeSelection(selectedIds)
                        showMergePreview = false
                        // 更新预览结果
                        preExecuteResult = cleanupVM.processedContacts
                        showPreExecute = true
                        appVM.contacts = cleanupVM.processedContacts
                        appVM.healthReport = HealthAnalyzer.analyze(cleanupVM.processedContacts)
                    },
                    onSkip: {
                        // 跳过合并：还原所有重复分组，仅应用其他优化
                        cleanupVM.applyMergeSelection([])
                        showMergePreview = false
                        preExecuteResult = cleanupVM.processedContacts
                        showPreExecute = true
                        appVM.contacts = cleanupVM.processedContacts
                        appVM.healthReport = HealthAnalyzer.analyze(cleanupVM.processedContacts)
                    }
                )
            }
            .alert("写入系统通讯录", isPresented: $showWriteBack) {
                Button("取消", role: .cancel) {}
                if !cleanupVM.isWritingBack {
                    Button("确认写入", role: .destructive) {
                        Task {
                            writeBackResult = await cleanupVM.writeSelectedContacts(currentSelectedIDs: selectedContactIDs)
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
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    let count = cleanupVM.hasPendingChanges ? cleanupVM.affectedContacts.count : cleanupVM.processedContacts.count
                    Text("将写入 \(count) 位联系人（已自动备份）")
                }
            }
            .alert("写入完成", isPresented: .init(
                get: { writeBackResult != nil },
                set: { if !$0 { writeBackResult = nil } }
            )) {
                Button("确定") {
                    writeBackResult = nil
                    cleanupVM.clearPendingChanges()
                    cleanupVM.resetAll()
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await appVM.refresh()
                    }
                }
            } message: {
                if let r = writeBackResult {
                    Text("成功写入 \(r.success) 位联系人" + (r.failed > 0 ? "，失败 \(r.failed) 位" : ""))
                }
            }
            .alert("恢复通讯录", isPresented: $showRestoreConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认恢复", role: .destructive) {
                    Task { if await cleanupVM.restoreFromBackup() { await appVM.refresh() } }
                }
            } message: { Text("将从备份文件恢复通讯录到备份时的状态") }

            // 全屏加载覆盖层
            if appVM.isLoading { loadingOverlay }
            if isProcessing { processingOverlay }
        }
    }

    // MARK: - 健康分卡片

    private var healthScoreCard: some View {
        VStack(spacing: 16) {
            // 评分环
            ZStack {
                // 底圈
                Circle()
                    .stroke(Color(hex: "E8ECF4"), lineWidth: 14)
                    .frame(width: 130, height: 130)

                // 进度圈
                Circle()
                    .trim(from: 0, to: CGFloat(appVM.healthReport.score) / 100)
                    .stroke(scoreGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: appVM.healthReport.score)

                // 中心数字
                VStack(spacing: 2) {
                    Text("\(appVM.healthReport.score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreGradient)
                    Text("健康分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            // 底部统计
            HStack(spacing: 0) {
                scoreMiniStat(value: "\(appVM.healthReport.totalContacts)", label: "联系人", icon: "person.2.fill")
                Divider().frame(height: 28)
                scoreMiniStat(value: "\(appVM.healthReport.issueItems.count)", label: "待优化", icon: "exclamationmark.circle.fill", color: appVM.healthReport.issueItems.isEmpty ? .green : .orange)
                Divider().frame(height: 28)
                scoreMiniStat(value: scoreGrade, label: "等级", icon: "star.fill", color: scoreGradeColor)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 4)
        .accessibilityIdentifier("home.healthScoreCard")
    }

    private func scoreMiniStat(value: String, label: String, icon: String, color: Color = .blue) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.caption2).foregroundStyle(color)
                Text(value).font(.callout.bold())
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreGradient: some ShapeStyle {
        let score = appVM.healthReport.score
        if score >= 80 { return AppTheme.successGradient }
        if score >= 50 { return AppTheme.warningGradient }
        return AppTheme.dangerGradient
    }

    private var scoreGrade: String {
        let s = appVM.healthReport.score
        if s >= 90 { return "优秀" }
        if s >= 80 { return "良好" }
        if s >= 60 { return "一般" }
        return "较差"
    }

    private var scoreGradeColor: Color {
        let s = appVM.healthReport.score
        if s >= 80 { return .green }
        if s >= 60 { return .orange }
        return .red
    }

    // MARK: - 统计卡片

    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(icon: "person.2.fill", value: "\(appVM.healthReport.totalContacts)", title: "联系人", color: Color(hex: "4F7DF5"))
            statCard(icon: "phone.fill", value: "\(appVM.healthReport.totalPhoneNumbers)", title: "手机号", color: Color(hex: "34C759"))
            statCard(icon: "envelope.fill", value: "\(appVM.healthReport.totalEmails)", title: "邮箱", color: Color(hex: "FF9500"))
        }
        .accessibilityIdentifier("home.statsSection")
    }

    private func statCard(icon: String, value: String, title: String, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 2)
    }

    // MARK: - 快速操作提示

    private var quickActionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.subheadline)
            Text("发现 \(filteredIssueItems.count) 类问题，点击查看详情")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 问题列表

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("可优化项目")
                    .font(.headline)
                Spacer()
                if !filteredIssueItems.isEmpty {
                    Text("\(filteredIssueItems.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if filteredIssueItems.isEmpty {
                emptyStateView
            } else {
                ForEach(Array(filteredIssueItems.enumerated()), id: \.element.issueType) { index, item in
                    issueRow(item: item, index: index)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.successGradient)
            Text("通讯录状态良好")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("无需优化，继续保持！")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func issueRow(item: HealthReport.IssueItem, index: Int) -> some View {
        Button {
            selectedIssueType = item.issueType
            selectedContactIDs.removeAll()
        } label: {
            HStack(spacing: 14) {
                // 图标区域
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(item.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(item.color)
                }

                // 文字区域
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(item.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 数量标签 + 箭头
                VStack(spacing: 4) {
                    Text("\(item.count)")
                        .font(.callout.bold())
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(item.color.opacity(0.1))
                        .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
            .shadow(color: AppTheme.cardShadow, radius: 4, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(index == 0 ? "home.issueRow.first" : "home.issueRow.\(item.issueType.rawValue)")
    }

    // MARK: - 操作区

    private var actionSection: some View {
        VStack(spacing: 10) {
            // 待写入修改提示
            if cleanupVM.hasPendingChanges {
                Button {
                    Task {
                        _ = await cleanupVM.backupContacts(appVM.contacts)
                        // 注意：不要覆盖 processedContacts，它已经是清理后的数据
                        cleanupVM.clearWriteSignature()
                        showWriteBack = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                        Text("写入系统通讯录 (\(cleanupVM.pendingChangesCount) 项待写入)")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
                    .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .accessibilityIdentifier("home.writePendingButton")

                Button {
                    // 放弃修改
                    cleanupVM.resetAll()
                    Task { await appVM.refresh() }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("放弃修改")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }

            if cleanupVM.hasBackup && !cleanupVM.hasPendingChanges {
                Button(role: .destructive) { showRestoreConfirm = true } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("从备份恢复")
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
                }
            }

            // 无待写入时，显示普通写入按钮
            if !filteredIssueItems.isEmpty && !cleanupVM.hasPendingChanges {
                Button {
                    Task {
                        _ = await cleanupVM.backupContacts(appVM.contacts)
                        // 注意：不要覆盖 processedContacts，它已经是清理后的数据
                        cleanupVM.clearWriteSignature()
                        showWriteBack = true
                        print("[Home] 首页写入: 使用 \(cleanupVM.processedContacts.count) 位联系人")
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                        Text("写入系统通讯录")
                        Spacer()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
                    .shadow(color: Color(hex: "4F7DF5").opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .accessibilityIdentifier("home.writeToSystemButton")
            }
        }
        .accessibilityIdentifier("home.actionSection")
    }

    // MARK: - 权限页

    private var permissionView: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(AppTheme.primaryGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color(hex: "4F7DF5").opacity(0.3), radius: 12, y: 6)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("需要访问您的通讯录")
                    .font(.title2.bold())
                Text("本应用仅在本地处理您的通讯录数据\n不会上传到任何服务器")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await appVM.requestAccess() }
            } label: {
                Text("授权访问通讯录")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color(hex: "4F7DF5").opacity(0.3), radius: 8, y: 4)
            }
            .accessibilityIdentifier("home.requestContactsButton")
            .padding(.horizontal, 24)

            // 隐私保障小标签
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("数据仅存本地 · 永不联网")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(Capsule())

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 加载覆盖层

    private var loadingOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.92).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(.blue)
                Text("通讯录健康分析中...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("正在分析联系人数据，请稍候")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if appVM.loadedContactsCount > 0 {
                    Text("已加载 \(appVM.loadedContactsCount) 位联系人")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.92).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(.blue)
                Text("正在处理: \(selectedIssueType?.rawValue ?? "问题")")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("正在优化联系人数据，请稍候")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - 错误页

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { Task { await appVM.refresh() } }
                .accessibilityIdentifier("home.retryButton")
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .padding(.top, 40)
    }

    // MARK: - 标签筛选栏

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip(tag: nil, label: "全部", isSelected: appVM.selectedTag == nil)
                ForEach(appVM.allTags, id: \.self) { tag in
                    tagChip(tag: tag, label: tag, isSelected: appVM.selectedTag == tag)
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("home.tagFilter")
    }

    private func tagChip(tag: String?, label: String, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appVM.selectedTag = tag
            }
        } label: {
            HStack(spacing: 4) {
                if tag != nil {
                    Image(systemName: "tag.fill").font(.caption2)
                }
                Text(label).font(.caption.bold())
            }
            .foregroundStyle(isSelected ? .white : Color(hex: "4F7DF5"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color(hex: "4F7DF5") : Color(hex: "4F7DF5").opacity(0.1))
            .clipShape(Capsule())
        }
        .accessibilityIdentifier(tag.map { "home.tag.\($0)" } ?? "home.tag.all")
    }

    // MARK: - 辅助

    private var filteredIssueItems: [HealthReport.IssueItem] {
        appVM.healthReport.issueItems.filter { !ignoredIssues.contains($0.issueType) }.sorted { $0.count > $1.count }
    }

    private func preExecute(for issueType: HealthReport.IssueType) async {
        isProcessing = true
        switch issueType {
        case .nameNeedsStandardize, .nameNotSplit: cleanupVM.selectedOptions = [.nameNormalization]
        case .phonePrefixInconsistent: cleanupVM.selectedOptions = [.phonePrefixUnify]
        case .phoneLabelInconsistent: cleanupVM.selectedOptions = [.phoneLabelUnify]
        case .phoneDuplicate: cleanupVM.selectedOptions = [.phoneDeduplicate]
        case .phoneGarbled: cleanupVM.selectedOptions = [.phoneClean]
        case .emailLabelInconsistent: cleanupVM.selectedOptions = [.emailLabelUnify]
        case .emailDuplicate: cleanupVM.selectedOptions = [.emailDeduplicate]
        case .emailInvalid: cleanupVM.selectedOptions = [.emailValidation]
        case .contactDuplicate: cleanupVM.selectedOptions = [.contactDeduplicate]
        case .emptyContact: cleanupVM.selectedOptions = [.removeEmptyContacts]
        }
        let selectedIDs = selectedContactIDs
        let allContacts = appVM.contacts
        cleanupVM.excludedContactIDs = Set(allContacts.map { $0.id }).subtracting(selectedIDs)

        // 使用 recordChanges 而不是 runCleanup，只记录修改不写入
        await cleanupVM.performCleanupAndRecord(on: allContacts)

        // 写入时只写用户选中的联系人（而非所有处理过的联系人）
        cleanupVM.selectedContactIDsAtPreExecute = selectedIDs

        // 更新 appVM.contacts 和 appVM.healthReport（健康分析移到后台避免阻塞 UI）
        let processedContacts = cleanupVM.processedContacts
        Task.detached {
            let newReport = HealthAnalyzer.analyze(processedContacts)
            await MainActor.run {
                appVM.contacts = processedContacts
                appVM.healthReport = newReport
                appVM.cachedDuplicateContacts = nil
                isProcessing = false
                preExecuteResult = processedContacts
                selectedIssueType = nil

                // 重复联系人展示合并预览
                if issueType == .contactDuplicate && !cleanupVM.duplicateGroups.isEmpty {
                    showMergePreview = true
                } else {
                    showPreExecute = true
                }
                print("[Home] 预执行完成: 已更新健康报告")
            }
        }
    }

    /// 预执行完成后应用修改到本地（显示预览效果，但标记为待写入）
    private func applyPendingChanges() {
        appVM.contacts = cleanupVM.processedContacts
        appVM.healthReport = HealthAnalyzer.analyze(cleanupVM.processedContacts)
        appVM.cachedDuplicateContacts = nil
        print("[Home] 应用待写入修改: \(cleanupVM.processedContacts.count) 位")
    }

    /// 放弃所有待写入的修改
    private func discardPendingChanges() {
        cleanupVM.resetAll()
        Task { await appVM.refresh() }
    }

    private func ignoreIssue(_ issueType: HealthReport.IssueType) {
        ignoredIssues.insert(issueType)
        selectedIssueType = nil
    }
}

// MARK: - 问题详情页

struct IssueDetailView: View {
    let title: String
    let issueType: HealthReport.IssueType
    @Binding var selectedContactIDs: Set<ContactItem.ID>
    let onPreExecute: () async -> Void
    let onIgnore: () -> Void
    @ObservedObject var appVM: AppViewModel
    var onDismiss: (() -> Void)?

    @State private var searchText = ""
    @State private var loadState: LoadState = .loading

    enum LoadState {
        case loading
        case loaded([ContactItem])
        case empty
        case error(String)
    }

    private var displayedContacts: [ContactItem] {
        if case .loaded(let contacts) = loadState {
            return contacts
        }
        return []
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
                AppTheme.pageBackground.ignoresSafeArea()

                // 直接渲染内容，不使用 opacity 动画
                mainContent
            }
            .task {
                print("[IssueDetail] .task 开始加载: issueType=\(issueType.rawValue), appVM.contacts=\(appVM.contacts.count)")
                await loadContacts()
            }
            .onDisappear {
                print("[IssueDetail] onDisappear")
                onDismiss?()
            }
            .accessibilityIdentifier("issue.detail.root")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch loadState {
        case .loading:
            loadingOverlay

        case .loaded(let contacts) where contacts.isEmpty:
            emptyStateView

        case .loaded:
            contactListView

        case .empty:
            emptyStateView

        case .error(let message):
            errorView(message: message)
        }
    }

    private var contactListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 顶部摘要
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("\(displayedContacts.count) 位联系人存在「\(title)」问题")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: toggleSelectAll) {
                            Text(selectedContactIDs.count == filteredContacts.count ? "取消全选" : "全选")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .accessibilityIdentifier("issue.detail.selectAll")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                    }
                }
            }
            .accessibilityIdentifier("issue.detail.scroll")

            // 底部操作按钮（固定在屏幕底部）
            VStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        await onPreExecute()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("预执行优化")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("issue.detail.preExecute")

                Button(action: onIgnore) {
                    HStack {
                        Image(systemName: "eye.slash.fill")
                        Text("忽略此问题")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("issue.detail.ignore")
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索联系人")
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有找到需要处理的联系人")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5).tint(.blue)
            Text("正在建立索引...")
                .font(.subheadline).foregroundStyle(.primary)
            Text("请稍候，正在分析联系人数据")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func contactRow(_ contact: ContactItem) -> some View {
        HStack(spacing: 12) {
            Button(action: { toggleSelection(contact) }) {
                Image(systemName: selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedContactIDs.contains(contact.id) ? .blue : .secondary)
                    .font(.system(size: 22))
            }

            Text(String(contact.initials))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor(for: contact))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                issueDetail(for: contact)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private func avatarColor(for contact: ContactItem) -> Color {
        let colors: [Color] = [
            Color(hex: "4F7DF5"), Color(hex: "7C5CE0"), Color(hex: "00B4D8"),
            Color(hex: "E17055"), Color(hex: "00B894"), Color(hex: "6C5CE7"),
            Color(hex: "FD79A8"), Color(hex: "FDCB6E")
        ]
        let hash = abs(contact.id.hashValue)
        return colors[hash % colors.count]
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

    private func loadContacts() async {
        print("[IssueDetail] loadContacts: issueType=\(issueType.rawValue), appVM.contacts=\(appVM.contacts.count)")

        // contactDuplicate 有预计算缓存
        if issueType == .contactDuplicate, let cached = appVM.cachedDuplicateContacts {
            print("[IssueDetail] 使用缓存的重复联系人: \(cached.count) 位")
            loadState = .loaded(cached)
            return
        }

        let allContacts = appVM.contacts
        print("[IssueDetail] 开始过滤: 联系人总数=\(allContacts.count)")

        // 过滤操作
        var filtered: [ContactItem] = []
        switch issueType {
        case .nameNeedsStandardize, .nameNotSplit:
            filtered = allContacts.filter { ContactValidator.needsNameFix($0) }
        case .phonePrefixInconsistent:
            filtered = allContacts.filter { c in
                let prefixes = Set(c.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                return prefixes.count > 1
            }
        case .phoneLabelInconsistent:
            // 使用与 HealthAnalyzer 相同的逻辑：同类型有多种写法才是不统一
            filtered = allContacts.filter { contact in
                let grouped = Dictionary(grouping: contact.phoneNumbers) {
                    ContactNormalizer.unifyPhoneLabel($0.label)
                }
                return grouped.values.contains { phones in
                    Set(phones.map { $0.label }).count > 1
                }
            }
        case .phoneDuplicate:
            filtered = allContacts.filter { !ContactDeduplicator.findDuplicatePhonesInContact($0).isEmpty }
        case .phoneGarbled:
            filtered = allContacts.filter { c in
                c.phoneNumbers.contains { phone in
                    let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    return !ContactValidator.isValidChinesePhone(digits)
                }
            }
        case .emailLabelInconsistent:
            // 使用与 HealthAnalyzer 相同的逻辑：同类型有多种写法才是不统一
            filtered = allContacts.filter { contact in
                let grouped = Dictionary(grouping: contact.emailAddresses) {
                    ContactNormalizer.unifyEmailLabel($0.label)
                }
                return grouped.values.contains { emails in
                    Set(emails.map { $0.label }).count > 1
                }
            }
        case .emailDuplicate:
            filtered = allContacts.filter { !ContactDeduplicator.findDuplicateEmailsInContact($0).isEmpty }
        case .emailInvalid:
            filtered = allContacts.filter { c in
                c.emailAddresses.contains { !ContactNormalizer.isValidEmail($0.value) }
            }
        case .contactDuplicate:
            filtered = ContactDeduplicator.findDuplicates(in: allContacts).flatMap { $0.contacts }
        case .emptyContact:
            filtered = allContacts.filter { $0.isEmpty }
        }

        print("[IssueDetail] 过滤完成: 结果数=\(filtered.count)")
        loadState = .loaded(filtered)
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
            let prefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
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
}

// MARK: - 预执行结果页（统一写入模式）

struct PreExecuteRecordedView: View {
    let contactCount: Int
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 成功图标
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.green)

                Text("修改已记录")
                    .font(.title2.bold())

                VStack(spacing: 8) {
                    Text("已处理 \(contactCount) 位联系人")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("修改已暂存，请返回首页点击")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("「写入系统通讯录」")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                }

                VStack(spacing: 12) {
                    Button(action: onDismiss) {
                        HStack {
                            Image(systemName: "arrow.left.circle.fill")
                            Text("继续处理其他问题")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("preexecute.continueButton")

                    Button(action: onDismiss) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("知道了")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("preexecute.dismissButton")
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 40)
            .background(AppTheme.pageBackground)
            .navigationTitle("预执行结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onDismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("preexecute.recorded.root")
    }
}

// MARK: - 统计卡片 (旧版保留给 CleanupResultView)

struct StatCard: View {
    let icon: String
    let value: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

// MARK: - 后台线程过滤联系人（避免阻塞主线程）

private func filterContactsForIssue(_ contacts: [ContactItem], type: HealthReport.IssueType) -> [ContactItem] {
    switch type {
    case .nameNeedsStandardize, .nameNotSplit:
        return contacts.filter { ContactValidator.needsNameFix($0) }
    case .phonePrefixInconsistent:
        return contacts.filter { c in
            let prefixes = Set(c.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
            return prefixes.count > 1
        }
    case .phoneLabelInconsistent:
        return contacts.filter { Set($0.phoneNumbers.map { $0.label }).count > 1 }
    case .phoneDuplicate:
        return contacts.filter { !ContactDeduplicator.findDuplicatePhonesInContact($0).isEmpty }
    case .phoneGarbled:
        return contacts.filter { c in
            c.phoneNumbers.contains { phone in
                let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                return !ContactValidator.isValidChinesePhone(digits)
            }
        }
    case .emailLabelInconsistent:
        return contacts.filter { Set($0.emailAddresses.map { $0.label }).count > 1 }
    case .emailDuplicate:
        return contacts.filter { !ContactDeduplicator.findDuplicateEmailsInContact($0).isEmpty }
    case .emailInvalid:
        return contacts.filter { c in
            c.emailAddresses.contains { !ContactNormalizer.isValidEmail($0.value) }
        }
    case .contactDuplicate:
        return ContactDeduplicator.findDuplicates(in: contacts).flatMap { $0.contacts }
    case .emptyContact:
        return contacts.filter { $0.isEmpty }
    }
}
