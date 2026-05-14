# 本地通讯录管家

> 一款专注于隐私保护的 iOS 通讯录管理工具，所有数据仅在本地处理，不会上传至任何服务器。

[![Platform](https://img.shields.io/badge/Platform-iOS%2026%2B-blue)](https://developer.apple.com/documentation/ios)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 核心特性

### 隐私优先
- **本地处理**：所有通讯录分析、整理、优化操作均在设备本地完成
- **零网络传输**：无需网络权限，不上传任何数据
- **本地备份**：支持导出 VCF 备份，数据完全可控

### 智能健康分析
通过多维度评估，为您的通讯录打分（0-100）：

| 检测维度 | 说明 |
|---------|------|
| 姓名规范化 | 自动识别并拆分未分割的姓名 |
| 手机号前缀 | 统一 +86 等国际区号格式 |
| 手机标签标准化 | 智能归类同类标签（如 iPhone/Mobile → 手机） |
| 重复联系人 | 自动发现并合并重复记录 |
| 无效号码 | 检测乱码、格式错误的手机号 |
| 空联系人的 | 清理无任何联系方式的条目 |

### 精确写入
- **智能匹配**：写入时自动匹配系统通讯录中的现有记录
- **精确修改**：仅修改实际变更的联系人，不影响其他数据
- **幂等设计**：支持重复写入，自动跳过已确认的修改

---

## 功能概览

### 支持的优化项目

| 功能 | 描述 |
|------|------|
| 姓名标准化 | 自动拆分 "王小明" → 姓"王"名"小明" |
| 手机号前缀统一 | "+86 139xxxx"、"86 139xxxx"、"139xxxx" 统一格式 |
| 手机标签规范化 | "iPhone" / "Mobile" / "手机" 统一为"手机" |
| 邮箱标签规范化 | "Email" / "邮箱" / "邮件" 统一为"邮箱" |
| 手机号去重 | 同一联系人内相同号码去重 |
| 邮箱去重 | 同一联系人内相同邮箱去重 |
| 重复联系人合并 | 智能识别并合并同名/同号联系人 |
| 无效号码清理 | 删除乱码、非法格式的号码 |
| 空联系人删除 | 清理无任何联系方式的条目 |

### 写入策略
系统通讯录写入采用三级匹配策略：
1. **Identifier 精确匹配**：优先通过系统 Identifier 精确匹配，保留容器信息
2. **手机号匹配**：处理 VCF 导入联系人的 UUID 不一致问题
3. **姓名匹配**：兜底按姓名匹配，避免遗漏

---

## 技术架构

### 技术栈
- **UI Framework**: SwiftUI
- **Architecture**: MVVM + ObservableObject
- **Contacts API**: Contacts 框架 (CNContactStore)
- **Persistence**: 系统通讯录 + 本地 VCF 备份
- **Concurrency**: Swift Concurrency (async/await, Task)

### 项目结构

```
本地通讯录管家/
├── Models/                    # 数据模型
│   ├── ContactItem.swift      # 联系人数据结构
│   └── HealthReport.swift     # 健康报告模型
├── ViewModels/                # 视图模型
│   ├── AppViewModel.swift     # 应用主状态管理
│   └── CleanupViewModel.swift # 清理操作核心逻辑
├── Views/                     # 视图层
│   ├── Home/                  # 首页及问题详情
│   ├── Settings/              # 设置页面
│   └── Components/            # 可复用组件
├── Services/                  # 服务层
│   ├── ContactImporter.swift  # 通讯录读取
│   ├── ContactNormalizer.swift# 数据标准化
│   ├── ContactExporter.swift  # VCF 导出
│   ├── ContactDeduplicator.swift # 去重算法
│   └── HealthAnalyzer.swift   # 健康分析引擎
├── Utils/                     # 工具类
│   ├── ContactValidator.swift # 数据校验
│   └── TagManager.swift       # 标签管理
└── Theme/                     # 主题配置
```

### 核心算法

#### 手机标签归类逻辑
```swift
// 统一将手机相关标签归为"手机"类型
// Mobile / iPhone / 手机 / MP / TEL / Phone / 空标签 → "手机"
// Main / 主要 → "主号码"（独立分类）
// Home / Work / 其他 → 保持原样
```

#### 重复联系人检测
采用多维度匹配：
1. 姓名相似度（支持中文姓名拆分）
2. 手机号标准化匹配（去除前缀后匹配）
3. 邮箱精确匹配

---

## 版本历史

### v1.6 (2026-05-14)
**Bug Fixes:**
- 修复手机标签检测逻辑：区分不同电话类型（如 Mobile + Home）与同类型不同写法（如 Mobile + iPhone）
- 修复写入持久化问题：affectedContacts 数组在数据转换后正确更新
- 修复主号码误归类：main/主要 不再错误归为"手机"

**Improvements:**
- 优化写入确认弹窗显示的联系人数量
- 增加清理过程详细日志

### v1.5 (Previous)
- 性能优化：重复联系人缓存预计算
- UI 重新设计
- Bug 修复

---

## 开发说明

### 环境要求
- Xcode 16.0+
- iOS 26.4+ Simulator 或真机
- Swift 6.0

### 构建
```bash
xcodebuild -project 本地通讯录管家.xcodeproj \
  -scheme 本地通讯录管家 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### 测试
```bash
# 运行单元测试
xcodebuild test -scheme 本地通讯录管家

# 运行 UI 测试
xcodebuild test -scheme 本地通讯录管家UITests
```

---

## 隐私说明

本应用非常重视用户隐私：

- **无需网络权限**：App Store 版本不包含任何网络请求
- **数据本地存储**：所有数据处理在设备本地完成
- **VCF 备份**：用户可随时导出备份，数据完全可控
- **不收集任何信息**：不收集任何用户行为或分析数据

---

## 许可证

本项目基于 MIT 许可证开源。

---

## 致谢

- [Contacts 框架](https://developer.apple.com/documentation/contacts) - Apple 官方通讯录 API
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - Apple 官方 UI 框架
