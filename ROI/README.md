# 神经元钙成像 ROI 分析与绘图项目

**Neuron Calcium Imaging ROI Analysis & Plotting**

## 📂 文件夹概览

本文件夹包含用于处理 ImageJ 导出的 ROI 文件、对 tiff 文件提取神经元钙信号轨迹（Trace）、以及绘制神经元质心分布图的 MATLAB 脚本、数据和结果图。

---

## 📜 1. MATLAB 脚本 (Code)

* **`PlotNeuronROIs.m`** (2025/12/31)
* **核心功能**：读取 ImageJ 的 `.roi` 文件，绘制**白底、彩色实心**的神经元质心分布图（复刻 Nature 风格）。


* **`Plot_DualGroup_Proportional_Final.m`** (2025/12/31)
* **功能**：双组数据比例分析脚本（用于分析 920nm vs 1030nm 或两组实验条件下的神经元激活比例）。输出结果为**`freely_Neuron.fig`**


* **`Batch_Trace_Analysis_GUI.m`** (2025/12/30)
* **功能**：带图形界面的批量钙信号提取工具。用于批量处理多个视频的 Trace 提取。读取数据为ImageJ标注的ROI数据，导出数据为csv，后期通过


---

## 📊 2. 数据文件 (Data & CSV)

* **`920only_Batch_Results_Merged.csv`**
* 仅包含 920nm 激发波长（通常为 GCaMP 绿色通道）的批量处理结果汇总表。


* **`920&1030_Batch_Results_Merged.csv`**
* 包含 920nm 和 1030nm 重合细胞的合并分析结果。


---

## 📐 3. 原始 ROI 文件 (Raw ImageJ Files)

* **`RoiSet_920.zip`** / **`RoiSet_920only.zip`**：ImageJ 圈出的 920nm 通道 ROI 集合。
* **`RoiSet_1030.zip`**：ImageJ 圈出的 1030nm 通道 ROI 集合。

---

## 🛠️ 5. 其他 (Others)
* **`ReadImageJROI-master`** (文件夹)
* 第三方工具箱。内置解析ROI功能
