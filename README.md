# iPhone Duo & NotchFold 📱✨

> **为折叠屏与 macOS 物理刘海量身打造的双端拟态流体体验**  
> 包含 **Web 3D 折叠交互演示** 与 **macOS 原生刘海灵动岛应用 (NotchFold)**。

---

## 🌟 项目亮点

### 1. Web 3D 折叠双屏体验 (`index.html`)
- **真实折叠物理手感**：支持三种交互模式（呼吸自律、鼠标跟随、滚轮缩放与折叠角度控制）。
- **Apple 级动态壁纸**：内置暮色、极光、深海、余烬 4 套渐变壁纸与星空微粒系统。
- **拟态动态岛与锁屏**：上屏灵动岛、实时时钟与下屏组件完美协同。
- **一键查看实机演练与下载**：页面右上角直连 macOS 原生客户端演示与打包下载。

### 2. macOS 原生刘海灵动岛 (`NotchFold.app`)
- **避让物理刘海（Notch Clearance）**：顶部 38pt 完美融合 MacBook 物理硬件刘海，所有工具栏、标题与胶囊按钮完全在刘海下方，0 遮挡。
- **开合角度传感器联动**：实时接管 Apple Silicon 笔记本转轴角度传感器 (`las`)，感知真实开盖合盖物理角度。
- **5 大 Metal GPU 流体光学着色器**：
  - `Flex`：微曲流体拟态
  - `Duo`：经典书本折叠
  - `Roll`：曲面柔性卷轴
  - `Shutter`：百叶光影百褶
  - `Iris`：虹膜渐变聚焦
- **拖动加功能 (Drag & Drop)**：
  - 直接从访达拖入 `.app` 应用，自动提取图标与名称加入“常用应用”；
  - 拖入文件夹，自动加入“常用目录”；
  - 自动持久化保存到本地配置。
- **快速随手记 (Scratchpad)**：
  - 随手记录灵感与待办；
  - ⌘V 粘贴图片、拖入文件；
  - 一键存入 macOS 原生系统“备忘录 (Apple Notes)”并开新记录。
- **零权限侵扰**：
  - 彻底剥离不必要的系统录屏权限调用，打开即用，0 权限弹窗骚扰。

---

## 🚀 快速开始

### 方式一：直接运行 Web 端
双击打开 `index.html`，即可在任何现代浏览器体验 3D 折叠屏。

### 方式二：直接安装 macOS 桌面版
1. 下载根目录下的 `NotchFold-macOS.zip` 并解压；
2. 双击打开 `NotchFold.app`；
3. 将鼠标移至 MacBook 屏幕顶部中央刘海区域，即可平滑唤出面板；移出鼠标自动平滑收起。

### 方式三：从源码本地编译
```bash
cd NotchFold
chmod +x build.sh
./build.sh
open NotchFold.app
```

---

## 🛠 技术栈
- **Web 端**：HTML5 / CSS3 3D Transforms / Vanilla JavaScript (0 依赖，极速加载)
- **客户端**：Swift 5.9+ / AppKit / Metal 3 / IOKit HID (Apple Silicon LID Sensor)

---

## 📄 开源许可
MIT License © 2026 Alan Qin
