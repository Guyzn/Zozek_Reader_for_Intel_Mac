# Zozek Reader for Intel Mac

一款专为 Intel Mac (macOS 14+) 优化的本地化电子书阅读与朗读软件。

## 📚 项目简介

Zozek Reader (阻只读书) 是一款轻量级、隐私优先的电子书阅读器，专为 Intel Mac 用户设计。支持 TXT、DOCX、EPUB 等多种格式，内置 TTS 语音朗读功能，让您的 Mac 变成专业的听书设备。

### ✨ 核心特性

- 🎯 **专为 Intel Mac 优化** - 完美适配 macOS 14 (Sonoma) 及以上版本
- 📖 **多格式支持** - TXT、DOCX、EPUB 等主流电子书格式
- 🔊 **TTS 语音朗读** - 内置多种语音引擎，支持语速、音量调节
- 🎨 **现代化 UI** - 简洁优雅的 SwiftUI 界面设计
- 🔒 **隐私优先** - 所有文件本地处理，无需联网
- 📌 **阅读进度保存** - 自动保存阅读位置和书签
- 🌙 **深色模式支持** - 完美适配系统外观设置

## 🚀 快速开始

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Intel Mac (x86_64 架构)
- 建议 4GB 以上内存

### 安装方法

#### 方法一：下载 DMG 安装（推荐）

1. 前往 [Releases](https://github.com/Guyzn/Zozek_Reader_for_Intel_Mac/releases) 页面
2. 下载最新版本的 `Zozek_Reader_for_Intel_Mac.dmg`
3. 双击 DMG 文件，将 `阻只读书.app` 拖入 `Applications` 文件夹
4. 首次打开可能需要在"系统设置 > 隐私与安全性"中允许运行

#### 方法二：从源码构建

```bash
# 克隆仓库
git clone https://github.com/Guyzn/Zozek_Reader_for_Intel_Mac.git

# 打开项目
cd Zozek_Reader_for_Intel_Mac
open M-ReaderApp.xcodeproj

# 在 Xcode 中选择目标为 macOS 14.0+，然后 Build & Run
```

## 📖 使用指南

### 导入书籍

1. 点击左上角「+」按钮或拖拽文件到书架
2. 支持批量导入多个文件
3. 支持 TXT、DOCX、EPUB 格式

### 开始阅读

1. 在书架点击书籍封面
2. 使用触控板或鼠标滚轮翻页
3. 点击右上角「书签」按钮保存当前位置

### 语音朗读

1. 打开书籍后，点击底部播放按钮
2. 在设置中调整语速、音量、语音类型
3. 支持后台播放（可最小化窗口）

### 快捷键

- `Space` - 播放/暂停朗读
- `↑/↓` - 调整音量
- `←/→` - 快进/快退 10 秒
- `Cmd + T` - 显示/隐藏目录
- `Cmd + B` - 添加书签

## 🛠 技术架构

### 技术栈

- **语言**: Swift 5.9+
- **框架**: SwiftUI 4.0, AVFoundation
- **最低支持**: macOS 14.0 (Sonoma)
- **架构**: x86_64 (Intel Mac)

### 项目结构

```
M-ReaderApp/
├── M-ReaderApp.xcodeproj          # Xcode 项目文件
├── M-ReaderApp/
│   ├── AppDelegate.swift          # 应用入口
│   ├── Assets.xcassets            # 图标和资源
│   ├── Models/                    # 数据模型
│   │   ├── BookDocument.swift     # 书籍文档模型
│   │   └── BookParserProtocol.swift # 解析器协议
│   ├── Views/                     # SwiftUI 视图
│   │   ├── MContentView.swift     # 主界面
│   │   ├── MReaderView.swift      # 阅读器视图
│   │   └── Components/           # 可复用组件
│   ├── ViewModels/                # 视图模型
│   │   └── LibraryViewModel.swift # 书架管理
│   ├── Services/                  # 服务层
│   │   ├── TTSManager.swift       # TTS 语音服务
│   │   └── SecurityScopedBookmarkService.swift # 沙盒权限
│   └── Parsers/                   # 文件解析器
│       ├── MTXTParser.swift       # TXT 解析
│       ├── MEPUBParser.swift      # EPUB 解析
│       └── MDOCXParser.swift      # DOCX 解析
└── README.md                      # 本文件
```

## 🐛 已知问题

- [ ] EPUB 格式复杂样式可能显示异常
- [ ] DOCX 表格和图片暂不支持
- [ ] Apple Silicon (M1/M2/M3) 未充分测试

## 🔜 开发计划

- [ ] 支持更多电子书格式 (PDF, MOBI)
- [ ] 笔记和高亮功能
- [ ] iCloud 同步
- [ ] 统计阅读数据和进度
- [ ] 支持 Apple Silicon 原生适配

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交 Bug Report

请包含以下信息：
- macOS 版本
- 应用版本
- 复现步骤
- 崩溃日志（如有）

### 提交 Pull Request

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 开源协议

本项目采用 MIT 协议开源 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - Apple 官方 UI 框架
- [AVFoundation](https://developer.apple.com/av-foundation/) - Apple 多媒体框架

## 📧 联系方式

- GitHub Issues: [提交问题](https://github.com/Guyzn/Zozek_Reader_for_Intel_Mac/issues)
- 电子邮件: guyznhastings@gmail.com
- 微信公众号：阻只Zozek

---

⭐ 如果这个项目对您有帮助，请给它一个 Star！
