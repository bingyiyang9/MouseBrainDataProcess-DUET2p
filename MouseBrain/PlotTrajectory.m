function PlotTrajectory(csvFile)
    % PlotPaperStyle 复刻期刊级旷场实验轨迹图
    % 输入: csvFile (可选，不填则弹出选择框)
    
    %% 1. 加载数据
    if nargin < 1
        [file, path] = uigetfile('*.csv', '选择轨迹数据 CSV');
        if isequal(file, 0); return; end
        csvFile = fullfile(path, file);
    end
    
    % 读取数据 (兼容你的格式: Frame, X, Y)
    try
        data = readmatrix(csvFile); 
    catch
        data = csvread(csvFile, 1, 0); % 跳过表头
    end
    
    % 提取坐标
    rawX = data(:, 2);
    rawY = data(:, 3);
    
    %% 2. 关键步骤：数据平滑 (去噪)
    % 你的数据抖动很大，必须平滑。
    % 'gaussian' 是高斯平滑，窗口大小设为 10-15 (根据帧率调整)
    % 这能把锯齿状的"震动"变成流畅的"路径"
    x = smoothdata(rawX, 'gaussian', 80);
    y = smoothdata(rawY, 'gaussian', 80);
    
    %% 3. 设定实验场地边界 (Arena)
    % 注意：你的数据范围极小(730-740)，这说明老鼠可能根本没动，或者这是局部放大。
    % 为了演示效果，我自动计算数据的边界作为"箱子"的大小。
    % 在实际实验中，你应该知道箱子的真实像素坐标，例如 box = [0, 0, 500, 500]
    
    padding = 5; % 留一点边距
    minX = min(x) - padding; maxX = max(x) + padding;
    minY = min(y) - padding; maxY = max(y) + padding;
    w = maxX - minX;
    h = maxY - minY;
    
    %% 4. 开始绘图 (样式复刻)
    figure('Color', 'w', 'Position', [200, 200, 500, 500]); % 白色背景，正方形画布
    hold on;
    axis equal; % 必须！保证正方形不被拉伸
    
    % [A] 绘制外框 (黑框)
    rectangle('Position', [minX, minY, w, h], ...
        'EdgeColor', 'k', 'LineWidth', 2);
    
    % [B] 绘制中心区域 (ROI, 红虚线)
    % 假设中心区域是整体面积的 50% (边长约 70%)
    roiScale = 0.7; 
    roiW = w * roiScale;
    roiH = h * roiScale;
    roiX = minX + (w - roiW)/2;
    roiY = minY + (h - roiH)/2;
    
    rectangle('Position', [roiX, roiY, roiW, roiH], ...
        'EdgeColor', [0.8, 0, 0], ... % 深红色
        'LineStyle', '--', ...        % 虚线
        'LineWidth', 1.5);
    
    % [C] 绘制轨迹 (Styling)
    % 使用深灰色，透明度(如果版本支持)，线条极细
    plot(x, y, '-', ...
        'Color', [0.4, 0.4, 0.4, 0.7], ... % [R G B Alpha] (灰色半透明)
        'LineWidth', 0.8);             % 线宽 < 1
        
    % [D] 隐藏坐标轴 (期刊风格通常不需要刻度)
    axis([minX minY maxX maxY]); % 锁定范围
    set(gca, 'Visible', 'off'); % 隐藏坐标轴
    
    % [E] 添加比例尺 (可选)
    % 假设总宽度代表 50cm
    scaleBarLen = w * 0.2; % 20% 的长度
    plot([maxX-scaleBarLen, maxX], [minY+1, minY+1], 'k-', 'LineWidth', 2);
    text(maxX-scaleBarLen/2, minY+3, 'Scale', 'HorizontalAlignment', 'center', 'FontSize', 10);

    title('Subject Trajectory', 'FontSize', 14);
    hold off;
end