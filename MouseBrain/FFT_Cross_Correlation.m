classdef FFT_Cross_Correlation < matlab.apps.AppBase
    % FFT Cross-Correlation Author: yangbingyi 2025/12/29
    % Update:
    % 1. 弃用 SURF，改用 imregcorr (FFT互相关)，彻底解决 Beads 匹配乱飞的问题。
    % 2. 加入高斯模糊预处理，增强稀疏光点的对齐稳定性。
    
    properties (Access = public)
        UIFigure             matlab.ui.Figure
        GridLayout           matlab.ui.container.GridLayout
        LeftPanel            matlab.ui.container.Panel
        RightPanel           matlab.ui.container.Panel
        
        % --- 畸变配置 ---
        PanelJson            matlab.ui.container.Panel
        BtnJson920           matlab.ui.control.Button
        LblJson920           matlab.ui.control.Label
        BtnJson1030          matlab.ui.control.Button
        LblJson1030          matlab.ui.control.Label
        
        % --- 对准控制 ---
        PanelAlign           matlab.ui.container.Panel
        BtnLoadBead920       matlab.ui.control.Button
        LblBead920           matlab.ui.control.Label
        BtnLoadBead1030      matlab.ui.control.Button
        LblBead1030          matlab.ui.control.Label
        BtnAutoAlign         matlab.ui.control.Button
        LblAutoStatus        matlab.ui.control.Label
        
        % --- 文件夹操作 ---
        TabGroup             matlab.ui.container.TabGroup
        TabSingle            matlab.ui.container.Tab
        BtnSelectFolder      matlab.ui.control.Button
        LblFolder            matlab.ui.control.Label
        BtnPreview           matlab.ui.control.Button
        BtnExport            matlab.ui.control.Button
        TxtLog               matlab.ui.control.TextArea
        
        % --- 预览区 ---
        AxMerged             matlab.ui.control.UIAxes
        
        % --- 图像微调 ---
        PanelTuning          matlab.ui.container.Panel
        SliderX              matlab.ui.control.Slider
        SliderY              matlab.ui.control.Slider
        BtnLeft              matlab.ui.control.Button
        BtnRight             matlab.ui.control.Button
        BtnUp                matlab.ui.control.Button
        BtnDown              matlab.ui.control.Button
        LblShiftInfo         matlab.ui.control.Label
        BtnContrast          matlab.ui.control.StateButton
        
        SwitchViewMode       matlab.ui.control.Switch
        BtnGroupView         matlab.ui.container.ButtonGroup
        RadMerge             matlab.ui.control.RadioButton
        RadGreen             matlab.ui.control.RadioButton
        RadRed               matlab.ui.control.RadioButton
        
        PanelPlayer          matlab.ui.container.Panel
        BtnPlay              matlab.ui.control.Button
        SliderFrame          matlab.ui.control.Slider
        LblFrameInfo         matlab.ui.control.Label
    end

    properties (Access = private)
        PathJson920=''; PathJson1030=''; SingleFolderPath='';
        Tform920; Tform1030;
        SingleFolderPaths;
        
        BeadImg920; BeadImg1030;
        Stack_G; Stack_R; 
        
        NumPreviewFrames = 0;
        CurrentFrameIdx = 1;
        IsPlaying = false;
        PlayTimer
    
        AutoShiftX = 0; AutoShiftY = 0;
        ManualShiftX = 0; ManualShiftY = 0;
        
        TiffInfo920; TiffInfo1030;
        HImageObject 
    end

    methods (Access = private)

        function log(app, msg)
            t = datestr(now, 'HH:MM:SS');
            app.TxtLog.Value = [app.TxtLog.Value; {sprintf('[%s] %s', t, msg)}];
            scroll(app.TxtLog, 'bottom');
            drawnow limitrate;
        end

        % === 1. 畸变校正加载 ===
        function success = load_json(app, path, ch)
            success=false;
            try
                str=fileread(path); data=jsondecode(str); pts=data.Centroids; n=sqrt(length(pts));
                raw=zeros(length(pts),2); for i=1:length(pts), raw(i,:)=[pts(i).X,pts(i).Y]; end
                sortedY=sortrows(raw,2);
                moving=zeros(length(pts),2); for i=1:n, idx=(i-1)*n+1:i*n; moving(idx,:)=sortrows(sortedY(idx,:),1); end
                [xg,yg]=meshgrid(linspace(min(moving(:,1)),max(moving(:,1)),n), linspace(min(moving(:,2)),max(moving(:,2)),n));
                fixed=zeros(length(pts),2); c=1; for i=1:n, for j=1:n, fixed(c,:)=[xg(i,j),yg(i,j)]; c=c+1; end; end
                tform=fitgeotrans(moving,fixed,'polynomial',3);
                if contains(ch,'920'), app.Tform920=tform; else, app.Tform1030=tform; end
                success=true;
                app.log(['√ ' ch ' 矩阵加载成功']);
            catch ME, uialert(app.UIFigure,ME.message,'JSON Error'); end
        end

        % === 2. Beads 自动对齐 (改为互相关算法) ===
        function run_auto_alignment(app)
            if isempty(app.BeadImg920) || isempty(app.BeadImg1030)
                uialert(app.UIFigure, '请先加载两个通道的 Beads 图像', 'Error'); return;
            end
            
            app.log('开始自动对齐 (FFT互相关)...');
            try
                % A. 预处理：归一化
                I1_raw = app.robust_scale(app.BeadImg920);
                I2_raw = app.robust_scale(app.BeadImg1030);
                
                % B. 畸变校正 (必须在对齐前执行)
                if ~isempty(app.Tform920)
                    ref = imref2d(size(I1_raw));
                    I1_raw = imwarp(I1_raw, app.Tform920, 'OutputView', ref, 'FillValues', 0);
                end
                if ~isempty(app.Tform1030)
                    ref = imref2d(size(I2_raw));
                    I2_raw = imwarp(I2_raw, app.Tform1030, 'OutputView', ref, 'FillValues', 0);
                end
                
                % C. 【关键优化】高斯模糊 + 互相关
                % 1. 高斯模糊：将稀疏的光点变成大的光晕，增加重叠面积，
                %    防止因为光点太小错开几个像素就算不出相关性。
                sigma = 3; % 模糊半径，针对稀疏 Beads 设大一点
                I1_blur = imgaussfilt(I1_raw, sigma);
                I2_blur = imgaussfilt(I2_raw, sigma);
                
                % 2. 使用 MATLAB 内置的平移配准函数 (基于相位相关性)
                % 计算将 I2 (Red/Moving) 移动到 I1 (Green/Fixed) 所需的变换
                tform = imregcorr(I2_blur, I1_blur, 'translation');
                
                % D. 提取结果
                dx = tform.T(3,1);
                dy = tform.T(3,2);
                
                app.AutoShiftX = dx;
                app.AutoShiftY = dy;
                
                app.LblAutoStatus.Text = sprintf('dX: %.1f, dY: %.1f', dx, dy);
                app.LblAutoStatus.FontColor = [0 0.6 0];
                app.log(sprintf('互相关计算成功: X=%.2f, Y=%.2f', dx, dy));
                
                % 立即刷新预览
                app.update_display_frame();
                
            catch ME
                app.log(['对齐异常: ' ME.message]);
                uialert(app.UIFigure, ME.message, 'Align Error');
            end
        end

        % === 3. 预览加载 ===
        function run_preview(app, p920_list, p1030_list)
             if isempty(app.Tform920), uialert(app.UIFigure,'请先加载畸变配置(JSON)','Err'); return; end
             
             d = uiprogressdlg(app.UIFigure, 'Title', '读取预览...', 'Indeterminate','on');
             try
                 app.TiffInfo920 = app.get_tiff_info(p920_list);
                 app.TiffInfo1030 = app.get_tiff_info(p1030_list);
                 
                 if isempty(app.TiffInfo920.file_list), error('未找到 TIFF 文件'); end
                 
                 nRead = min(app.TiffInfo920.total_frames, 20);
                 app.NumPreviewFrames = nRead;
                 
                 tmp = app.read_tiff_frame(app.TiffInfo920, 1);
                 [h,w] = size(tmp);
                 ref = imref2d([h,w]);
                 
                 S9 = zeros(h,w, nRead, 'uint8');
                 S10 = zeros(h,w, nRead, 'uint8');
                 
                 for k=1:nRead
                     raw9 = double(app.read_tiff_frame(app.TiffInfo920, k));
                     raw10 = double(app.read_tiff_frame(app.TiffInfo1030, k));
                     
                     % 畸变校正
                     corr9 = imwarp(raw9, app.Tform920, 'OutputView', ref, 'FillValues', mean(raw9(:)));
                     corr10 = imwarp(raw10, app.Tform1030, 'OutputView', ref, 'FillValues', mean(raw10(:)));
                     
                     % 归一化显示
                     S9(:,:,k) = app.robust_scale(corr9);
                     S10(:,:,k) = app.robust_scale(corr10);
                 end
                 
                 app.Stack_G = S9;
                 app.Stack_R = S10;
                 
                 app.SliderFrame.Limits = [1, nRead];
                 app.SliderFrame.Value = 1;
                 app.CurrentFrameIdx = 1;
                 app.enable_controls();
                 
                 cla(app.AxMerged);
                 app.HImageObject = imshow(zeros(h,w,'uint8'), 'Parent', app.AxMerged);
                 app.AxMerged.XLim = [0.5, w+0.5];
                 app.AxMerged.YLim = [0.5, h+0.5];
                 axis(app.AxMerged, 'image');
                 
                 app.update_display_frame();
                 app.log('预览就绪');
                 
             catch ME
                 app.log(['Preview Error: ' ME.message]);
                 uialert(app.UIFigure, ME.message, 'Err');
             end
             close(d);
        end

        % === 4. 显示更新 ===
        function update_display_frame(app)
            if isempty(app.Stack_G), return; end
            f = round(app.SliderFrame.Value);
            
            ImgG = app.Stack_G(:,:,f);
            ImgR = app.Stack_R(:,:,f);
            
            finalDx = app.AutoShiftX + app.ManualShiftX;
            finalDy = app.AutoShiftY + app.ManualShiftY;
            
            isRaw = strcmp(app.SwitchViewMode.Value, '原始(Raw)');
            
            if ~isRaw
                % 应用平移
                ImgR = imtranslate(ImgR, [finalDx, finalDy], 'FillValues', 0);
                titleStr = sprintf('Frame %d [Align X:%.1f Y:%.1f]', f, finalDx, finalDy);
            else
                titleStr = sprintf('Frame %d [Raw]', f);
            end
            
            [VisG, VisR] = app.get_display_channels(ImgG, ImgR);
            Z = zeros(size(VisG), 'uint8'); 
            sel = app.BtnGroupView.SelectedObject;
            
            if sel == app.RadMerge, F = cat(3, VisR, VisG, Z);
            elseif sel == app.RadGreen, F = cat(3, Z, VisG, Z);
            elseif sel == app.RadRed, F = cat(3, VisR, Z, Z);
            end
            
            if isvalid(app.HImageObject)
                app.HImageObject.CData = F;
                title(app.AxMerged, titleStr, 'Color','w', 'FontSize', 10);
                drawnow limitrate; 
            end
            
            app.LblFrameInfo.Text = sprintf('%d / %d', f, app.NumPreviewFrames);
            app.LblShiftInfo.Text = sprintf('Manual: X %d | Y %d', round(app.ManualShiftX), round(app.ManualShiftY));
        end

        % === 5. 辅助函数 ===
        function out = robust_scale(~, img)
             img = double(img);
             v_sorted = sort(img(:));
             n = numel(v_sorted);
             if n==0, out=uint8(img); return; end
             % 0.1% - 99.9% 动态范围，去除极亮噪点干扰
             low = v_sorted(max(1, round(0.001 * n)));
             high = v_sorted(min(n, round(0.999 * n)));
             if high <= low, low = min(img(:)); high = max(img(:)); end
             
             if high == low
                 out = uint8(zeros(size(img)));
             else
                 img_norm = (img - low) / (high - low);
                 img_norm(img_norm < 0) = 0; img_norm(img_norm > 1) = 1;
                 out = uint8(img_norm * 255);
             end
        end

        function [outG, outR] = get_display_channels(app, inG, inR)
             if app.BtnContrast.Value
                 outG = adapthisteq(inG); outR = adapthisteq(inR);
             else
                 outG = inG; outR = inR;
             end
        end

        function process_export(app)
            if isempty(app.TiffInfo920), return; end
            outDir = fullfile(app.SingleFolderPath, 'Aligned_Results');
            if ~isfolder(outDir), mkdir(outDir); end
            
            d = uiprogressdlg(app.UIFigure, 'Title', '导出中', 'Cancelable','on');
            finalDx = app.AutoShiftX + app.ManualShiftX;
            finalDy = app.AutoShiftY + app.ManualShiftY;
            ref = imref2d(size(app.Stack_G(:,:,1)));
            
            files920 = app.TiffInfo920.file_list;
            nF = app.TiffInfo920.total_frames;
            [~,n,~] = fileparts(files920{1});
            outNameG = fullfile(outDir, ['Aligned_920_' n '.tif']);
            outNameR = fullfile(outDir, ['Aligned_1030_' n '.tif']);
            if isfile(outNameG), delete(outNameG); end
            if isfile(outNameR), delete(outNameR); end

            for k=1:nF
                if d.CancelRequested, break; end
                d.Value = k/nF; d.Message = sprintf('Exporting %d/%d', k, nF);
                
                raw9 = double(app.read_tiff_frame(app.TiffInfo920, k));
                raw10 = double(app.read_tiff_frame(app.TiffInfo1030, k));
                
                c9 = imwarp(raw9, app.Tform920, 'OutputView', ref, 'FillValues', mean(raw9(:)));
                c10 = imwarp(raw10, app.Tform1030, 'OutputView', ref, 'FillValues', mean(raw10(:)));
                c10_shifted = imtranslate(c10, [finalDx, finalDy], 'FillValues', 0);
                
                imwrite(uint16(c9), outNameG, 'WriteMode','append','Compression','none');
                imwrite(uint16(c10_shifted), outNameR, 'WriteMode','append','Compression','none');
            end
            close(d);
            uialert(app.UIFigure, '导出完成', 'Done');
        end

        function frame = read_tiff_frame(~, info, idx)
             file_idx = find(info.cumulative_frames >= idx, 1, 'first');
             if file_idx > 1, local_idx = idx - info.cumulative_frames(file_idx-1); else, local_idx = idx; end
             frame = imread(info.file_list{file_idx}, local_idx);
        end
        function info = get_tiff_info(~, flist)
            if isempty(flist), info=[]; return; end
            info.file_list = flist; 
            info.cumulative_frames = cumsum(arrayfun(@(x) numel(imfinfo(x{1})), flist)); 
            info.total_frames = info.cumulative_frames(end);
        end
        function file_list = get_sorted_tiff_files(~, folder_path)
            if ~isfolder(folder_path), file_list = {}; return; end
            d = [dir(fullfile(folder_path, '*.tif')); dir(fullfile(folder_path, '*.tff'))];
            nums = zeros(length(d), 1);
            for i = 1:length(d), num_str = regexp(d(i).name, '\d+', 'match'); if ~isempty(num_str), nums(i) = str2double(num_str{end}); end; end
            [~, sort_idx] = sort(nums); d_sorted = d(sort_idx);
            file_list = fullfile({d_sorted.folder}, {d_sorted.name});
        end
        function paths = check_struct(app, f)
            paths.p1 = app.get_sorted_tiff_files(fullfile(f, 'CellVideo1', 'CellVideo'));
            paths.p2 = app.get_sorted_tiff_files(fullfile(f, 'CellVideo2', 'CellVideo'));
            if isempty(paths.p1), app.log('Warning: No tiffs in CellVideo1'); end
        end
        function enable_controls(app)
             app.SliderX.Enable='on'; app.SliderY.Enable='on'; app.BtnPlay.Enable='on';
             app.SliderFrame.Enable='on'; app.BtnLeft.Enable='on'; app.BtnRight.Enable='on';
             app.BtnUp.Enable='on'; app.BtnDown.Enable='on';
        end

       % --- Modified Callback: Load Bead/Ref with Averaging ---
        function OnLoadBead(app, ch)
            [f,p] = uigetfile({'*.tif';'*.tiff';'*.png';'*.jpg'}, ['Select ' ch ' Bead/Ref']);
            if f == 0, return; end
            
            filepath = fullfile(p,f);
            
            % 1. 获取文件信息以确定帧数
            try
                info = imfinfo(filepath);
                numFrames = numel(info);
            catch
                numFrames = 1; % 如果读取信息失败，默认单帧
            end
            
            % 2. 读取第一帧并初始化
            d = uiprogressdlg(app.UIFigure, 'Title', ['Loading ' ch], 'Message', 'Initializing...');
            
            rawFrame = imread(filepath, 1);
            if size(rawFrame,3) > 1, rawFrame = rgb2gray(rawFrame); end
            
            % 使用 double 进行累加，防止溢出
            sumImg = double(rawFrame);
            
            % 3. 如果是多帧，循环读取并累加
            if numFrames > 1
                d.Message = sprintf('Averaging %d frames...', numFrames);
                for k = 2:numFrames
                    % 更新进度条 (每10帧更新一次，提高速度)
                    if mod(k, 10) == 0, d.Value = k/numFrames; end
                    
                    tmpFrame = imread(filepath, k);
                    if size(tmpFrame,3) > 1, tmpFrame = rgb2gray(tmpFrame); end
                    sumImg = sumImg + double(tmpFrame);
                end
                
                % 计算平均值
                avgImg = sumImg / numFrames;
                app.log(sprintf('[%s] 已加载并平均 %d 帧 Beads 图像', ch, numFrames));
            else
                avgImg = sumImg;
                app.log(sprintf('[%s] 加载单帧 Beads 图像', ch));
            end
            
            % 4.以此作为最终图像 (转回 uint8 方便后续处理，或者保留 double 也可以，robust_scale 兼容)
            FinalImg = uint8(avgImg);
            
            % 5. 赋值给 App 属性
            if strcmp(ch,'920')
                app.BeadImg920 = FinalImg; 
                app.LblBead920.Text = sprintf('Loaded (%d frames)', numFrames); 
                app.LblBead920.FontColor = [0 0.5 0];
            else
                app.BeadImg1030 = FinalImg; 
                app.LblBead1030.Text = sprintf('Loaded (%d frames)', numFrames); 
                app.LblBead1030.FontColor = [0.5 0 0];
            end
            
            close(d);
        end
        function OnSingleSelect(app, p)
            if p==0, return; end
            app.SingleFolderPath=p; 
            app.SingleFolderPaths = app.check_struct(p);
            [~,n]=fileparts(p); app.LblFolder.Text=n;
            app.log(['Selected: ' n]);
        end
        function OnSlider(app, ~)
            app.ManualShiftX = app.SliderX.Value;
            app.ManualShiftY = app.SliderY.Value;
            app.update_display_frame();
        end
        function OnNudge(app, ax, val)
            if strcmp(ax,'x')
                app.SliderX.Value = min(max(app.SliderX.Value + val, -50), 50);
                app.ManualShiftX = app.SliderX.Value;
            else
                app.SliderY.Value = min(max(app.SliderY.Value + val, -50), 50);
                app.ManualShiftY = app.SliderY.Value;
            end
            app.update_display_frame();
        end
        function OnPlay(app)
            if app.IsPlaying, stop(app.PlayTimer); app.IsPlaying=false; app.BtnPlay.Text='▶';
            else, start(app.PlayTimer); app.IsPlaying=true; app.BtnPlay.Text='⏸'; end
        end
        function on_timer(app)
            if ~app.IsPlaying, return; end
            nx=app.CurrentFrameIdx+1; if nx>app.NumPreviewFrames, nx=1; end
            app.SliderFrame.Value=nx; app.update_display_frame();
        end
    end

    % =====================================================================
    % 4. UI 布局
    % =====================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible','off','Position',[50 50 1200 800],'Name','Microscope Lite v16.3 (FFT Cross-Corr)');
            app.GridLayout = uigridlayout(app.UIFigure,[1 2]); app.GridLayout.ColumnWidth={300,'1x'};
            
            app.LeftPanel = uipanel(app.GridLayout);
            
            app.PanelJson = uipanel(app.LeftPanel, 'Title','1. 畸变校正','Position',[10 650 280 120]);
            app.BtnJson920 = uibutton(app.PanelJson, 'Text','920 JSON','Position',[10 65 80 30], 'ButtonPushedFcn', @(~,~) app.load_json(uigetfile('*.json'),'920'));
            app.LblJson920 = uilabel(app.PanelJson, 'Text','...','Position',[100 70 150 20]);
            app.BtnJson1030 = uibutton(app.PanelJson, 'Text','1030 JSON','Position',[10 20 80 30], 'ButtonPushedFcn', @(~,~) app.load_json(uigetfile('*.json'),'1030'));
            app.LblJson1030 = uilabel(app.PanelJson, 'Text','...','Position',[100 25 150 20]);
            
            app.PanelAlign = uipanel(app.LeftPanel, 'Title','2. 通道对准 (Beads)','Position',[10 450 280 180]);
            app.BtnLoadBead920 = uibutton(app.PanelAlign, 'Text','Beads 920','Position',[10 110 90 30], 'ButtonPushedFcn', @(~,~) app.OnLoadBead('920'));
            app.LblBead920 = uilabel(app.PanelAlign, 'Text','-','Position',[110 115 60 20]);
            app.BtnLoadBead1030 = uibutton(app.PanelAlign, 'Text','Beads 1030','Position',[10 70 90 30], 'ButtonPushedFcn', @(~,~) app.OnLoadBead('1030'));
            app.LblBead1030 = uilabel(app.PanelAlign, 'Text','-','Position',[110 75 60 20]);
            app.BtnAutoAlign = uibutton(app.PanelAlign, 'Text','自动对齐 (互相关)','Position',[10 20 120 30], 'BackgroundColor',[0.8 0.9 1], 'ButtonPushedFcn', @(~,~) app.run_auto_alignment());
            app.LblAutoStatus = uilabel(app.PanelAlign, 'Text','','Position',[140 25 120 20]);
            
            app.TabGroup = uitabgroup(app.LeftPanel, 'Position',[10 150 280 280]);
            app.TabSingle = uitab(app.TabGroup, 'Title','单次处理');
            app.BtnSelectFolder = uibutton(app.TabSingle, 'Text','选择数据文件夹', 'Position',[10 200 200 40], 'ButtonPushedFcn', @(~,~) app.OnSingleSelect(uigetdir));
            app.LblFolder = uilabel(app.TabSingle, 'Text','-','Position',[10 170 200 20]);
            app.BtnPreview = uibutton(app.TabSingle, 'Text','预览', 'Position',[10 100 200 40], 'ButtonPushedFcn', @(~,~) app.run_preview(app.SingleFolderPaths.p1, app.SingleFolderPaths.p2));
            app.BtnExport = uibutton(app.TabSingle, 'Text','导出结果', 'Position',[10 40 200 40], 'BackgroundColor',[0.6 1 0.6], 'ButtonPushedFcn', @(~,~) app.process_export());
            
            app.TxtLog = uitextarea(app.LeftPanel, 'Position',[10 10 280 130]);
            
            app.RightPanel = uipanel(app.GridLayout); app.RightPanel.BackgroundColor='k';
            app.AxMerged = uiaxes(app.RightPanel, 'Position',[20 220 800 500], 'Color','k', 'XColor','none', 'YColor','none');
            
            app.PanelPlayer = uipanel(app.RightPanel, 'Position',[20 170 800 40], 'BackgroundColor',[0.2 0.2 0.2], 'BorderType','none');
            app.BtnPlay = uibutton(app.PanelPlayer, 'Text','▶', 'Position',[10 5 40 30], 'Enable','off', 'ButtonPushedFcn', @(~,~) app.OnPlay());
            app.SliderFrame = uislider(app.PanelPlayer, 'Position',[70 15 600 3], 'Limits',[1 50], 'Enable','off', 'ValueChangedFcn', @(s,e) app.update_display_frame());
            app.LblFrameInfo = uilabel(app.PanelPlayer, 'Text', 'Frame: 0/0', 'Position', [700 10 100 20], 'FontColor','w');
            
            app.PanelTuning = uipanel(app.RightPanel, 'Title','图像控制', 'Position',[20 10 800 150], 'BackgroundColor',[0.9 0.9 0.9]);
            app.SwitchViewMode = uiswitch(app.PanelTuning, 'Items',{'原始(Raw)','已对齐'}, 'Position',[650 110 80 30], 'ValueChangedFcn', @(~,~) app.update_display_frame());
            
            x = 220;
            app.BtnLeft = uibutton(app.PanelTuning, 'Text','◀', 'Position',[x 95 30 30], 'Enable','off', 'ButtonPushedFcn', @(~,~) app.OnNudge('x', -1));
            app.SliderX = uislider(app.PanelTuning, 'Limits',[-50 50], 'Position',[x+40 109 300 3], 'Enable','off', 'ValueChangedFcn', @(s,e) app.OnSlider());
            app.BtnRight = uibutton(app.PanelTuning, 'Text','▶', 'Position',[x+350 95 30 30], 'Enable','off', 'ButtonPushedFcn', @(~,~) app.OnNudge('x', 1));
            
            app.BtnUp = uibutton(app.PanelTuning, 'Text','▲', 'Position',[x 35 30 30], 'Enable','off', 'ButtonPushedFcn', @(~,~) app.OnNudge('y', -1));
            app.SliderY = uislider(app.PanelTuning, 'Limits',[-50 50], 'Position',[x+40 49 300 3], 'Enable','off', 'ValueChangedFcn', @(s,e) app.OnSlider());
            app.BtnDown = uibutton(app.PanelTuning, 'Text','▼', 'Position',[x+350 35 30 30], 'Enable','off', 'ButtonPushedFcn', @(~,~) app.OnNudge('y', 1));
            
            app.LblShiftInfo = uilabel(app.PanelTuning, 'Text','Manual: X 0 | Y 0', 'Position',[x+400 70 150 30], 'FontSize',14, 'FontWeight','bold');
            
            app.BtnGroupView = uibuttongroup(app.PanelTuning, 'Position', [20 20 180 100], 'Title', '通道', 'SelectionChangedFcn', @(~,~) app.update_display_frame());
            app.RadMerge = uiradiobutton(app.BtnGroupView, 'Text','Merge', 'Position',[10 70 80 20]);
            app.RadGreen = uiradiobutton(app.BtnGroupView, 'Text','Green (920)', 'Position',[10 40 120 20]);
            app.RadRed = uiradiobutton(app.BtnGroupView, 'Text','Red (1030)', 'Position',[10 10 120 20]);
            
            app.BtnContrast = uibutton(app.PanelTuning, 'state', 'Text', '增强显示', 'Position', [650 30 100 30], 'ValueChangedFcn', @(~,~) app.update_display_frame());
            
            app.PlayTimer = timer('ExecutionMode','fixedRate','Period',0.1,'TimerFcn',@(~,~) app.on_timer());
            app.UIFigure.Visible='on';
        end
    end
    
    methods (Access = public)
        function app = FFT_Cross_Correlation
            createComponents(app);
            registerApp(app, app.UIFigure);
            app.log('v16.3 就绪 (互相关对齐)');
        end
        function delete(app), delete(app.UIFigure); delete(app.PlayTimer); end
    end
end