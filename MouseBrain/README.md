# DUET 显微镜图像配准与处理工具包

**DUET Microscope Image Registration & Processing Toolkit**

## 📂 项目概览

本文件夹包含用于双光子/显微镜成像数据的**配准 (Registration)**、**去抖动 (De-jittering)** 和 **可视化** 的 MATLAB 核心脚本及处理后的数据。

主要解决双通道（920nm/1030nm）图像的空间配准、时间序列上的运动校正，以及针对 Z 轴变焦场景的特殊去抖动处理。

---

## 🛠️ 1. 核心处理脚本 (Core Processing Scripts)

* **`Microscope_RefExport_v27.m`** (关键脚本)
* **功能**：基于时间序列的图像配准、去抖动与导出。
* **算法逻辑**：计算前 30 帧的平均图像作为参考（Reference），将后续图像序列与该参考进行对齐。
* **用途**：生成稳定、对齐的参考栈（Ref Stacks），用于后续的 ROI 圈选或双通道合并。


* **`Microscope_Registration_z.m`**
* **功能**：**滑动窗口去抖动**（Sliding Window De-jittering）。
* **适用场景**：专门针对 **Z 轴变焦 (Z-stack / Focus Shift)** 或成像平面发生缓慢变化的场景。
* **特点**：相比于固定参考帧，滑动窗口能更好地适应焦平面变化带来的图像特征改变。


* **`FFT_Cross_Correlation.m`**
* **功能**：基于 FFT（快速傅里叶变换）的**互相关算法**。
* **用途**：这是配准算法的数学核心，用于精确计算两帧图像之间的平移量（Translation/Shift），以实现像素级的对齐。



---

## 🔧 2. 辅助工具与可视化 (Tools & Visualization)

* **`Tiff_to_MP4_Tool.m`**
* **功能**：格式转换工具。
* **用途**：将巨大的 `.tif` 图像栈转换为轻量级的 `.mp4` 视频。
* **目的**：方便快速播放和肉眼观察去抖动效果（检查是否有残余晃动）。


---

## 📦 3. 依赖函数与配置文件 (Dependencies & Config)

* **`nanmean.m`** / **`nanmedian.m`**
* **功能**：处理包含 `NaN`（空值）的数据的平均值和中位数计算。
* **说明**：这是核心脚本的依赖函数，用于配合特定的工具箱或在低版本 MATLAB 中处理数据缺失情况。


* **`920.json`** / **`1030.json`**
* **功能**：畸变校正或初始配准参数文件。
* **说明**：包含 920nm 和 1030nm 通道的空间校准信息（如网格畸变参数）。


---

## 🚀 建议处理流程 (Workflow)

1. **畸变校正**：读取 `920.json` / `1030.json` 加载校正参数。
2. **配准计算**：
* 一般情况：运行 `Microscope_RefExport_v27.m` 进行基于参考帧的对齐。
* Z轴变焦情况：运行 `Microscope_Registration_z.m` 使用滑动窗口去抖。
* *底层调用 `FFT_Cross_Correlation.m` 计算位移。*


3. **效果检查**：
* 运行 `Tiff_to_MP4_Tool.m` 生成视频，检查图像是否稳定。


4. **导出结果**：生成最终的 `Ref_Aligned_..._Stack.tif` 文件。
