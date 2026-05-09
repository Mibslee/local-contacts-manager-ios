# 升级记录

## v1.1 (2026-04-08)

### 关键 Bug 修复
- **修复整理后写回系统通讯录会重复写入、联系人数量翻倍的问题**
  - 在 `CleanupViewModel.writeBackToSystemDirect()` 增加重入保护 (`isWritingBack` 检查) 以及基于 `processedContacts` 内容的幂等签名 (`lastWrittenSignature`)。同一批整理结果只会被写入一次，避免用户连点或视图重建触发的重复写入。
  - 整理流程结束后会重置写入签名，确保下一轮整理可以正常写回。
- **修复 `ContactsManager.saveContact()` 单条更新会失败甚至产生重复联系人的问题**
  - 之前 update 路径使用了一个全新的 `CNMutableContact`（缺少 `identifier`），导致系统通讯录无法定位现有记录。现在改为先 `unifiedContact(withIdentifier:)` 拿到现有联系人后 `mutableCopy()` 再修改字段。

### 性能优化
- **大幅加快通讯录读取速度**
  - `ContactsManager.fetchAllContacts()` 不再请求 `CNContactThumbnailImageDataKey` / `CNContactImageDataKey` 等大字段（`ContactItem` 实际未使用），并把枚举操作放到后台线程，预分配容量。在数千条通讯录场景下读取耗时显著下降。
- **重写写回流程，写入速度数倍提升**
  - 删除环节从「按 50 条小批 + 每批 sleep 200ms + 多轮重新枚举验证」改为「单次枚举 → 每批 200 条单事务删除 → 无 sleep」。
  - 添加环节同样改为每批 200 条单事务、无 sleep。
  - 整个删除+添加流程移入单个 `Task.detached`，减少线程切换与主线程卡顿。
  - 写入进度回调保留，UI 体验不变。

### 其它改进
- 写回时同时同步 `note` 与 `birthday` 字段，避免备注/生日丢失。
- 写回失败时不更新幂等签名，允许用户再次重试。
- 后台 fetch 启用 `unifyResults = true`，避免多账户场景下出现重复计数。

### 版本号
- MARKETING_VERSION: 1.0 → 1.1
- CURRENT_PROJECT_VERSION (build): 1 → 2

---

## v1.5 (2026-05-09)

### 性能优化
- **重复检测算法从 O(n²) 升级为 Union-Find**
  - `ContactDeduplicator.findDuplicates()` 原先使用嵌套循环逐对比较，数千联系人时耗时严重。
  - 改用哈希表倒排索引 + Union-Find 聚类，时间复杂度降至 O(n)。
- **清理流程合并为单次遍历**
  - `CleanupViewModel.performCleanupInBackground()` 原先对每个联系人执行 10+ 次数组遍历。
  - 合并为单次遍历完成所有逐联系人操作，全局操作（去重、删除空联系人）单独处理。
- **健康分析移至后台线程**
  - `AppViewModel` 中的 `HealthAnalyzer.analyze()` 改用 `Task.detached` 在后台执行，避免阻塞主线程。
- **通讯录缓存**
  - 新增 `cachedDuplicateContacts` 属性，避免重复计算；reload 时自动失效。
- **PinyinHelper 字典延迟初始化**
  - 500+ 条的 `pinyinMap` 改为嵌套 enum + `static let`，首次访问时才初始化。

### Bug 修复
- **修复 `sanitizePhone` 不清理号码的问题**
  - `ContactItem.sanitizePhone()` 原先直接返回原始字符串，现在调用 `ContactValidator.cleanPhoneNumber()` 移除特殊字符。
- **修复 CSV 导出数据截断**
  - `ContactExporter.exportToCSV()` 原先使用固定列数，多余号码/邮箱会被丢弃。
  - 改为动态列数生成：根据所有联系人中最大号码数和邮箱数自动扩展列。
- **修复 OperationLogger 线程安全问题**
  - `OperationLogger` 添加 `@MainActor` 注解，移除 `DispatchQueue.main.async` 包装，消除竞态条件。

### 代码质量
- **消除重复代码**
  - 从 `HealthAnalyzer`、`AppViewModel`、`CleanupViewModel` 中提取 6 个共享方法到新文件 `ContactValidator`：`needsNameFix()`、`needsNameCheck()`、`extractPhonePrefix()`、`isValidChinesePhone()`、`isValidPhone()`、`cleanPhoneNumber()`。
  - 删除 3 个文件中重复的私有方法共约 60 行。

### UI 美化
- **新增统一主题系统** (`Theme/AppTheme.swift`)
  - 定义渐变色、卡片背景、圆角、阴影、间距等设计常量。
  - 提供 `themedCard()`、`themedSection()` 等 View 扩展修饰符。
- **重写全部主要页面**
  - 首页：渐变健康评分环带动画、彩色统计卡片、圆点图标背景。
  - 清理页：卡片式布局、边框高亮选项行、渐变开始按钮。
  - 清理结果页：渐变成功图标、卡片式结果展示、可展开受影响联系人。
  - 导入页：渐变导入图标、卡片式格式按钮、三列结果统计卡。
  - 导出页：渐变导出图标、可选格式卡片、渐变导出按钮。
  - 设置页：分组设置卡片、绿色隐私徽章、胶囊"仅本地"标签。
- **联系人头像系统**
  - 8 色哈希轮转彩色头像，替换原先的灰色默认头像。
  - 统一应用于 `ContactRow`、`IssueContactsView` 等组件。

### 版本号
- MARKETING_VERSION: 1.1 → 1.5
- CURRENT_PROJECT_VERSION (build): 2 → 3
