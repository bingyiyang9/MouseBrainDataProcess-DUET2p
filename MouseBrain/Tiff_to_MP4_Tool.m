%% 四路对比视频生成工具 (2x2 Grid Generator)
% Author: yangbingyi 2025/12/28
% Layout:
%   [ Raw 920  ] [ Corr 920  ]
%   [ Raw 1030 ] [ Corr 1030 ]

clear; clc; close all;

try
    %% 1. 文件选择 (依次选择4个文件)
    fprintf('请按顺序选择文件...\n');
    
    % 1. Raw 920
    [f1, p1] = uigetfile('*.tif', '1/4: 选择 [原始 Raw] 920nm');
    if f1==0, error('已取消'); end
    path_raw_920 = fullfile(p1, f1);
    
    % 2. Corrected 920
    [f2, p2] = uigetfile('*.tif', '2/4: 选择 [校正后 Corrected] 920nm');
    if f2==0, error('已取消'); end
    path_cor_920 = fullfile(p2, f2);
    
    % 3. Raw 1030
    [f3, p3] = uigetfile('*.tif', '3/4: 选择 [原始 Raw] 1030nm');
    if f3==0, error('已取消'); end
    path_raw_1030 = fullfile(p3, f3);
    
    % 4. Corrected 1030
    [f4, p4] = uigetfile('*.tif', '4/4: 选择 [校正后 Corrected] 1030nm');
    if f4==0, error('已取消'); end
    path_cor_1030 = fullfile(p4, f4);

    %% 2. 初始化参数
    % 获取帧数 (取最小值以防对不齐)
    info1 = imfinfo(path_raw_920);
    nFrames = numel(info1);
    % 简单检查
    fprintf('文件加载完成，共 %d 帧，准备合成...\n', nFrames);
    
    % 输出路径
    outputFile = fullfile(p1, 'Comparison_Quad_View.mp4');
    
    % 视频写入器设置 (最高画质)
    v = VideoWriter(outputFile, 'MPEG-4');
    v.FrameRate = 30;   % 默认帧率
    v.Quality = 100;    % 100 = 无压缩感 (最高画质)
    open(v);
    
    % 进度条
    hWait = waitbar(0, '正在逐帧合成视频...');
    
    %% 3. 逐帧处理循环
    % 预计算对比度限制 (基于第一帧，避免每帧闪烁)
    % 这里我们动态计算每帧，或者你可以改为固定。动态计算对钙信号更好。
    
    for k = 1:nFrames
        % --- A. 读取数据 ---
        I_R9  = double(imread(path_raw_920, k));
        I_C9  = double(imread(path_cor_920, k));
        I_R10 = double(imread(path_raw_1030, k));
        I_C10 = double(imread(path_cor_1030, k));
        
        % --- B. 图像增强 (关键：转8bit + 增强可见度) ---
        % 使用 smart_enhance 函数将 16bit 压成 8bit 并提亮
        Vis_R9  = smart_enhance(I_R9);
        Vis_C9  = smart_enhance(I_C9);
        Vis_R10 = smart_enhance(I_R10);
        Vis_C10 = smart_enhance(I_C10);
        
        % --- C. 添加文字标签 (Burn-in text) ---
        % insertText 需要 uint8 输入
        Vis_R9  = insertText(Vis_R9, [10 10], 'Raw 920nm', 'FontSize', 18, 'BoxColor', 'black', 'BoxOpacity', 0.6, 'TextColor', 'white');
        Vis_C9  = insertText(Vis_C9, [10 10], 'Corrected 920nm', 'FontSize', 18, 'BoxColor', 'black', 'BoxOpacity', 0.6, 'TextColor', 'green');
        Vis_R10 = insertText(Vis_R10, [10 10], 'Raw 1030nm', 'FontSize', 18, 'BoxColor', 'black', 'BoxOpacity', 0.6, 'TextColor', 'white');
        Vis_C10 = insertText(Vis_C10, [10 10], 'Corrected 1030nm', 'FontSize', 18, 'BoxColor', 'black', 'BoxOpacity', 0.6, 'TextColor', 'red');
        
        % --- D. 拼合 (2x2 Grid) ---
        % [ R9  | C9  ]
        % [ R10 | C10 ]
        % 在中间加一条白线分割
        [h, w, ~] = size(Vis_R9);
        SeparatorV = 255 * ones(h, 4, 3, 'uint8'); % 垂直分割线
        SeparatorH = 255 * ones(4, w*2 + 4, 3, 'uint8'); % 水平分割线
        
        Row1 = [Vis_R9, SeparatorV, Vis_C9];
        Row2 = [Vis_R10, SeparatorV, Vis_C10];
        
        FinalFrame = [Row1; SeparatorH; Row2];
        
        % --- E. 写入视频 ---
        writeVideo(v, FinalFrame);
        
        % 更新进度
        if mod(k, 10) == 0
            waitbar(k/nFrames, hWait, sprintf('处理中: %d / %d 帧', k, nFrames));
        end
    end
    
    close(hWait);
    close(v);
    
    fprintf('转换成功！视频已保存至:\n%s\n', outputFile);
    msgbox('视频生成完毕！', 'Success');
    
catch ME
    if exist('hWait', 'var'), close(hWait); end
    if exist('v', 'var'), close(v); end
    errordlg(ME.message, '出错');
end

%% --- 辅助函数：智能对比度增强 (防止漆黑) ---
function img8 = smart_enhance(imgDouble)
    % 1. 归一化 (排除 0 值背景的影响)
    mask = imgDouble > 0;
    if ~any(mask(:))
        img8 = uint8(zeros(size(imgDouble))); % 全黑
        % 转成 RGB 格式方便 insertText
        img8 = cat(3, img8, img8, img8);
        return;
    end
    
    val_min = min(imgDouble(mask));
    val_max = max(imgDouble(mask));
    
    % 线性归一化到 0-1
    imgNorm = (imgDouble - val_min) / (val_max - val_min + eps);
    imgNorm(imgNorm < 0) = 0;
    imgNorm(imgNorm > 1) = 1;
    
    % 2. 自适应直方图均衡 (CLAHE) - 显微镜图像神器
    % ClipLimit 控制对比度强度，0.01 比较自然
    imgEq = adapthisteq(imgNorm, 'ClipLimit', 0.02, 'Distribution', 'rayleigh');
    
    % 3. 转 8-bit RGB
    img8_gray = uint8(imgEq * 255);
    img8 = cat(3, img8_gray, img8_gray, img8_gray); % 复制成 3 通道 RGB
end