classdef Microscope_RefExport_v27 < matlab.apps.AppBase
    % Microscope RefExport v27.0 (Fixed for 16-bit Batch Export)
    % Update Log:
    % 1. 导出逻辑：严格按照输入文件列表 (CellVideo 1, 2...) 逐个导出，不合并。
    % 2. 命名格式：输出为 Corrected_920nm_CellVideo X.tif，与截图一致。
    % 3. 数据深度：全程保留 16-bit (uint16)，移除所有压缩到 8-bit 的操作。
    % 4. 文件夹选择：允许分别选择 920 和 1030 文件夹，更灵活。
    
    properties (Access = public)
        UIFigure             matlab.ui.Figure
        GridLayout           matlab.ui.container.GridLayout
        LeftPanel            matlab.ui.container.Panel
        RightPanel           matlab.ui.container.Panel
        
        % --- 左侧控制区 ---
        PanelStatic          matlab.ui.container.Panel
        BtnJson920           matlab.ui.control.Button
        BtnJson1030          matlab.ui.control.Button
        BtnLoadRef920        matlab.ui.control.Button
        BtnLoadRef1030       matlab.ui.control.Button
        BtnAlignStatic       matlab.ui.control.Button 
        BtnExportRef         matlab.ui.control.Button 
        LblStaticStatus      matlab.ui.control.Label
        
        PanelMotion          matlab.ui.container.Panel
        BtnLoadToolbox       matlab.ui.control.Button
        ChkNoRMCorre         matlab.ui.control.CheckBox
        LblToolbox           matlab.ui.control.Label
        
        PanelAction          matlab.ui.container.Panel
        BtnSelectFolder      matlab.ui.control.Button
        LblFolder            matlab.ui.control.Label
        BtnPreview           matlab.ui.control.Button
        BtnExport            matlab.ui.control.Button
        TxtLog               matlab.ui.control.TextArea
        
        % --- 右侧预览区 ---
        TabGroupPreview      matlab.ui.container.TabGroup
        TabStatic            matlab.ui.container.Tab
        GridStatic           matlab.ui.container.GridLayout
        AxRef920             matlab.ui.control.UIAxes
        AxRef1030            matlab.ui.control.UIAxes
        TabRefCheck          matlab.ui.container.Tab
        AxRefCheck           matlab.ui.control.UIAxes
        TabOverlay           matlab.ui.container.Tab
        AxOverlay            matlab.ui.control.UIAxes
        TabSideBySide        matlab.ui.container.Tab
        GridSide             matlab.ui.container.GridLayout
        AxSideG              matlab.ui.control.UIAxes
        AxSideR              matlab.ui.control.UIAxes
        
        PanelPlayer          matlab.ui.container.Panel
        BtnPlay              matlab.ui.control.Button
        SliderFrame          matlab.ui.control.Slider
        LblFrameInfo         matlab.ui.control.Label
        
        PanelTuning          matlab.ui.container.Panel
        SliderX              matlab.ui.control.Slider
        SliderY              matlab.ui.control.Slider
        LblShiftInfo         matlab.ui.control.Label
        BtnContrast          matlab.ui.control.StateButton
    end
    properties (Access = private)
        Tform920; Tform1030;
        RefImg920; RefImg1030; 
        
        RefPath920 = ''; 
        RefPath1030 = '';
        
        Shift_ChannelX = 0; Shift_ChannelY = 0; 
        Shift_ManualX = 0;  Shift_ManualY = 0;
        
        SingleFolderPath=''; % 基础导出路径
        TiffInfo920; TiffInfo1030; % 包含 file_list
        Stack_Corr_G; Stack_Corr_R; % 仅用于预览
        NumPreviewFrames=0; CurrentFrameIdx=1; IsPlaying=false; PlayTimer;
    end
    methods (Access = private)
        
        function log(app, msg)
            t = datestr(now, 'HH:MM:SS');
            app.TxtLog.Value = [app.TxtLog.Value; {sprintf('[%s] %s', t, msg)}];
            scroll(app.TxtLog, 'bottom'); drawnow limitrate;
        end
        
        % === 1. 文件夹选择 (修正版：分别选择文件夹，避免路径报错) ===
        function OnSingleSelect(app)
            % 1. 选择 920 (Green) 所在的文件夹
            p1 = uigetdir(pwd, '1. Select Folder containing 920nm TIFFs (Green)');
            if p1 == 0, return; end
            
            % 2. 选择 1030 (Red) 所在的文件夹
            p2 = uigetdir(p1, '2. Select Folder containing 1030nm TIFFs (Red)');
            if p2 == 0, return; end
            
            % 记录保存路径 (以920文件夹的上级目录为准，或直接在p1旁建立)
            app.SingleFolderPath = fileparts(p1); 
            if isempty(app.SingleFolderPath), app.SingleFolderPath = p1; end
            
            % 获取文件列表 (按数字顺序排序)
            l1 = app.get_tiff_list(p1);
            l2 = app.get_tiff_list(p2);
            
            if isempty(l1) || isempty(l2)
                uialert(app.UIFigure, 'No tiff files found in selected folders.', 'Error');
                return;
            end
            
            % 检查文件数量是否一致
            if length(l1) ~= length(l2)
                msg = sprintf('File count mismatch!\n920: %d files\n1030: %d files\nProceed anyway?', length(l1), length(l2));
                selection = uiconfirm(app.UIFigure, msg, 'Warning', 'Options',{'Yes','Cancel'});
                if strcmp(selection, 'Cancel'), return; end
            end
            
            % 记录信息
            app.TiffInfo920 = app.get_tiff_info(l1);
            app.TiffInfo1030 = app.get_tiff_info(l2);
            
            [~, n] = fileparts(p1);
            app.LblFolder.Text = ['Src: ' n ' (' num2str(length(l1)) ' files)'];
            app.BtnPreview.Enable = 'on';
            app.BtnExport.Enable = 'on';
            app.log('Folders Selected. Ready.');
        end

        % === 2. 加载 Ref 和计算对齐 ===
        function load_json(app, ch)
            [f,p]=uigetfile('*.json', ['JSON ' ch]); if f==0, return; end
            try
                str=fileread(fullfile(p,f)); data=jsondecode(str); pts=data.Centroids; n=sqrt(length(pts));
                raw=zeros(length(pts),2); for i=1:length(pts), raw(i,:)=[pts(i).X,pts(i).Y]; end
                sortedY=sortrows(raw,2); moving=zeros(length(pts),2); for i=1:n, idx=(i-1)*n+1:i*n; moving(idx,:)=sortrows(sortedY(idx,:),1); end
                [xg,yg]=meshgrid(linspace(min(moving(:,1)),max(moving(:,1)),n), linspace(min(moving(:,2)),max(moving(:,2)),n));
                fixed=zeros(length(pts),2); c=1; for i=1:n, for j=1:n, fixed(c,:)=[xg(i,j),yg(i,j)]; c=c+1; end; end
                tform=fitgeotrans(moving,fixed,'polynomial',3);
                if contains(ch,'920'), app.Tform920=tform; app.BtnJson920.Text='920 √';
                else, app.Tform1030=tform; app.BtnJson1030.Text='1030 √'; end
                app.log(['JSON ' ch ' OK']);
            catch ME, app.log(['Err: ' ME.message]); end
        end
        
        function OnLoadRef(app, ch)
            [f,p]=uigetfile({'*.tif';'*.tiff'}, ['Select Ref Stack ' ch]); 
            if f==0, return; end
            filepath = fullfile(p,f);
            if strcmp(ch,'920'), app.RefPath920 = filepath; else, app.RefPath1030 = filepath; end
            
            info = imfinfo(filepath); numFrames = numel(info);
            rawFrame = double(imread(filepath, 1));
            sumImg = rawFrame;
            if numFrames > 1
                d = uiprogressdlg(app.UIFigure, 'Title', 'Ref Averaging...', 'Message', 'Calculating...');
                for k = 2:numFrames, sumImg = sumImg + double(imread(filepath, k)); end
                raw = sumImg / numFrames; close(d);
            else, raw = rawFrame; end
            
            tform = [];
            if strcmp(ch,'920'), tform = app.Tform920; elseif strcmp(ch,'1030'), tform = app.Tform1030; end
            if ~isempty(tform), raw = imwarp(raw, tform, 'OutputView', imref2d(size(raw)), 'FillValues', mean(raw(:))); end
            
            % 显示用 uint8，但保存 Ref 时应保留原始数据 (在export_refs里处理)
            imgDisp = app.to_uint8_display(raw);
            
            if strcmp(ch,'920')
                app.RefImg920=raw; % 保留 double 精度用于计算
                app.BtnLoadRef920.Text='Ref 920 √';
                imshow(imgDisp, [], 'Parent', app.AxRef920); title(app.AxRef920, 'Ref 920 (Master)', 'Color','g');
            else
                app.RefImg1030=raw; 
                app.BtnLoadRef1030.Text='Ref 1030 √';
                imshow(imgDisp, [], 'Parent', app.AxRef1030); title(app.AxRef1030, 'Ref 1030 (Unaligned)', 'Color','r');
            end
            app.TabGroupPreview.SelectedTab = app.TabStatic;
        end
        
        function calc_static_alignment(app)
            if isempty(app.RefImg920) || isempty(app.RefImg1030), uialert(app.UIFigure,'Need 2 Refs','Err'); return; end
            % 使用 double 进行高斯滤波和配准计算
            sigma = 2; G = imgaussfilt(app.RefImg920, sigma); R = imgaussfilt(app.RefImg1030, sigma);
            t = imregcorr(app.to_uint8_display(R), app.to_uint8_display(G), 'translation'); % imregcorr 最好用归一化后的图
            app.Shift_ChannelX = t.T(3,1); app.Shift_ChannelY = t.T(3,2);
            app.LblStaticStatus.Text = sprintf('dX:%.1f dY:%.1f', app.Shift_ChannelX, app.Shift_ChannelY);
            
            % Check
            R_Shifted = imtranslate(app.RefImg1030, [app.Shift_ChannelX, app.Shift_ChannelY], 'FillValues', 0);
            Fused = cat(3, app.to_uint8_display(R_Shifted), app.to_uint8_display(app.RefImg920), zeros(size(R_Shifted), 'uint8')); 
            imshow(Fused, [], 'Parent', app.AxRefCheck);
            title(app.AxRefCheck, sprintf('Shifted [%.1f, %.1f]', app.Shift_ChannelX, app.Shift_ChannelY), 'Color', 'y');
            app.TabGroupPreview.SelectedTab = app.TabRefCheck;
            app.BtnExportRef.Enable = 'on';
        end
        
        % === 3. 导出 (核心修改：按文件循环，16-bit) ===
        function process_export(app)
            if isempty(app.TiffInfo920), return; end
            
            % 创建输出文件夹 Corrected_Results
            outDir = fullfile(app.SingleFolderPath, 'Corrected_Results');
            if ~isfolder(outDir), mkdir(outDir); end
            
            d = uiprogressdlg(app.UIFigure, 'Title', 'Exporting 16-bit Stacks...', 'Cancelable','on');
            
            files920 = app.TiffInfo920.file_list;
            files1030 = app.TiffInfo1030.file_list;
            nFiles = min(length(files920), length(files1030));
            
            % 获取第一帧大小用于 imwarp
            tmp = imread(files920{1}, 1);
            refView = imref2d(size(tmp));
            doMotion = app.ChkNoRMCorre.Value;
            
            try
                % --- 按文件循环 (File 1, File 2 ...) ---
                for i = 1:nFiles
                    if d.CancelRequested, break; end
                    d.Value = i/nFiles; 
                    d.Message = sprintf('Processing File %d/%d', i, nFiles);
                    
                    % 1. 读取整个 Stack (保持原始深度，通常是 uint16)
                    [path9, name9, ext9] = fileparts(files920{i});
                    [path10, name10, ext10] = fileparts(files1030{i});
                    
                    Stack9 = app.read_entire_tiff(files920{i});  % Returns double for processing
                    Stack10 = app.read_entire_tiff(files1030{i});
                    
                    [h, w, nF] = size(Stack9);
                    
                    % 2. 畸变校正 (Unwarp)
                    if ~isempty(app.Tform920)
                        for k=1:nF, Stack9(:,:,k) = imwarp(Stack9(:,:,k), app.Tform920, 'OutputView', refView, 'FillValues', mean(mean(Stack9(:,:,k)))); end
                    end
                    if ~isempty(app.Tform1030)
                        for k=1:nF, Stack10(:,:,k) = imwarp(Stack10(:,:,k), app.Tform1030, 'OutputView', refView, 'FillValues', mean(mean(Stack10(:,:,k)))); end
                    end
                    
                    % 3. 运动去抖 (Motion Correction)
                    if doMotion
                        % 计算绿光通道的运动
                        Template = mean(Stack9, 3);
                        opt = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[h,w], 'mot_uf',4, 'bin_width',50, 'max_shift',20, 'use_parallel',false);
                        [Stack9, shifts, ~] = normcorre_batch(Stack9, opt, Template);
                        % 将相同位移应用到红光
                        Stack10 = apply_shifts(Stack10, shifts, opt);
                    end
                    
                    % 4. 全局对齐 (Alignment to Master Ref)
                    % 计算当前文件平均值相对于 Ref920 的位移
                    cur_dx = 0; cur_dy = 0;
                    if ~isempty(app.RefImg920)
                        AvgBatch = mean(Stack9, 3);
                        % 使用高斯滤波平滑后计算相关性
                        t = imregcorr(app.to_uint8_display(imgaussfilt(AvgBatch,2)), ...
                                      app.to_uint8_display(imgaussfilt(app.RefImg920,2)), 'translation');
                        cur_dx = t.T(3,1); cur_dy = t.T(3,2);
                    end
                    
                    txG = cur_dx + app.Shift_ManualX; 
                    tyG = cur_dy + app.Shift_ManualY;
                    txR = txG + app.Shift_ChannelX; 
                    tyR = tyG + app.Shift_ChannelY;
                    
                    % 5. 应用位移并保存 (关键：转回 uint16)
                    
                    % 构造文件名: Corrected_920nm_CellVideo 1.tif
                    % 假设原始文件名是 "CellVideo 1.tif"
                    outName9 = fullfile(outDir, ['Corrected_920nm_' name9 ext9]);
                    outName10 = fullfile(outDir, ['Corrected_1030nm_' name10 ext10]);
                    
                    % 删除旧文件
                    if isfile(outName9), delete(outName9); end
                    if isfile(outName10), delete(outName10); end
                    
                    % 写入循环
                    for k = 1:nF
                        % Translate
                        ImgG = imtranslate(Stack9(:,:,k), [txG, tyG], 'FillValues', 0);
                        ImgR = imtranslate(Stack10(:,:,k), [txR, tyR], 'FillValues', 0);
                        
                        % Cast to uint16 (保留原始深度，裁掉负值)
                        OutG = uint16(max(0, ImgG));
                        OutR = uint16(max(0, ImgR));
                        
                        % Save
                        imwrite(OutG, outName9, 'WriteMode','append', 'Compression','none');
                        imwrite(OutR, outName10, 'WriteMode','append', 'Compression','none');
                    end
                end
                
                app.log('Batch Export Complete!');
                close(d);
                uialert(app.UIFigure, ['Export Finished. Files saved to: ' outDir], 'Success');
                
            catch ME
                app.log(['Export Fail: ' ME.message]);
                close(d);
                uialert(app.UIFigure, ME.message, 'Error');
            end
        end
        
        % === Helpers ===
        function stack = read_entire_tiff(~, path)
            info = imfinfo(path);
            n = numel(info);
            tmp = imread(path, 1);
            [h,w] = size(tmp);
            stack = zeros(h,w,n, 'double'); % Use double for processing
            for k=1:n
                stack(:,:,k) = double(imread(path, k));
            end
        end
        
        function out = to_uint8_display(~, img)
            % 仅用于显示或 imregcorr 输入，不用于导出
            img=double(img); v=sort(img(:)); n=numel(v); 
            if n==0, out=uint8(img); return; end
            low=v(max(1,floor(0.001*n))); high=v(min(n,ceil(0.999*n))); 
            if high<=low, low=min(img(:)); high=max(img(:)); end
            if high==low, out=uint8(zeros(size(img))); else, out=uint8(255*(img-low)/(high-low)); end
        end
        
        function update_display_frame(app)
            if isempty(app.Stack_Corr_G), return; end
            f = round(app.SliderFrame.Value);
            % 这里预览还是用 uint8 (app.Stack_Corr_G 已经是 uint8)
            I9 = app.Stack_Corr_G(:,:,f); I10 = app.Stack_Corr_R(:,:,f);
            if app.BtnContrast.Value, I9=adapthisteq(I9); I10=adapthisteq(I10); end
            
            curTab = app.TabGroupPreview.SelectedTab;
            if curTab == app.TabOverlay
                F = cat(3, I10, I9, zeros(size(I9),'uint8'));
                imshow(F, 'Parent', app.AxOverlay); title(app.AxOverlay, sprintf('Frame %d Overlay', f), 'Color','w');
            elseif curTab == app.TabSideBySide
                imshow(I9, [], 'Parent', app.AxSideG); title(app.AxSideG, 'Green', 'Color','g');
                imshow(I10, [], 'Parent', app.AxSideR); title(app.AxSideR, 'Red', 'Color','r');
            end
            app.LblFrameInfo.Text = sprintf('%d/%d', f, app.NumPreviewFrames);
            app.LblShiftInfo.Text = sprintf('Man: %.0f, %.0f', app.Shift_ManualX, app.Shift_ManualY);
        end
        
        % 预览仍保留小样本，快速计算
        function run_preview_calc(app)
            if isempty(app.TiffInfo920), return; end
            d = uiprogressdlg(app.UIFigure, 'Title', 'Previewing...', 'Indeterminate','on');
            try
                nRead = min(app.TiffInfo920.total_frames, 30); app.NumPreviewFrames = nRead;
                % 仅读第一个文件的前30帧
                tmp = imread(app.TiffInfo920.file_list{1}, 1); [h,w] = size(tmp);
                
                Raw9 = zeros(h,w,nRead,'double'); Raw10 = zeros(h,w,nRead,'double');
                for k=1:nRead
                    Raw9(:,:,k) = double(app.read_tiff_frame(app.TiffInfo920, k));
                    Raw10(:,:,k) = double(app.read_tiff_frame(app.TiffInfo1030, k));
                end
                
                % Unwarp & Motion (同 Export 逻辑)
                refView = imref2d([h,w]);
                if ~isempty(app.Tform920), for k=1:nRead, Raw9(:,:,k)=imwarp(Raw9(:,:,k), app.Tform920, 'OutputView', refView, 'FillValues', mean(mean(Raw9(:,:,k)))); end, end
                if ~isempty(app.Tform1030), for k=1:nRead, Raw10(:,:,k)=imwarp(Raw10(:,:,k), app.Tform1030, 'OutputView', refView, 'FillValues', mean(mean(Raw10(:,:,k)))); end, end
                
                if app.ChkNoRMCorre.Value
                    Template = mean(Raw9, 3);
                    opt = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[h,w], 'mot_uf',4, 'bin_width',50, 'max_shift',20, 'use_parallel',false);
                    [Raw9, shifts, ~] = normcorre_batch(Raw9, opt, Template);
                    Raw10 = apply_shifts(Raw10, shifts, opt);
                end
                
                dx=0; dy=0;
                if ~isempty(app.RefImg920)
                    t = imregcorr(app.to_uint8_display(mean(Raw9, 3)), app.to_uint8_display(app.RefImg920), 'translation');
                    dx = t.T(3,1); dy = t.T(3,2);
                end
                
                for k=1:nRead
                    Raw9(:,:,k) = imtranslate(Raw9(:,:,k), [dx, dy], 'FillValues', 0);
                    Raw10(:,:,k) = imtranslate(Raw10(:,:,k), [dx + app.Shift_ChannelX, dy + app.Shift_ChannelY], 'FillValues', 0);
                end
                
                % 预览转 uint8 方便显示
                app.Stack_Corr_G = zeros(h,w,nRead,'uint8'); 
                app.Stack_Corr_R = zeros(h,w,nRead,'uint8');
                for k=1:nRead
                    app.Stack_Corr_G(:,:,k) = app.to_uint8_display(Raw9(:,:,k));
                    app.Stack_Corr_R(:,:,k) = app.to_uint8_display(Raw10(:,:,k));
                end
                
                app.SliderFrame.Limits=[1, nRead]; app.SliderFrame.Value=1; app.CurrentFrameIdx=1; 
                app.enable_controls(); app.TabGroupPreview.SelectedTab = app.TabOverlay;
                app.update_display_frame(); app.BtnExport.Enable='on';
            catch ME, app.log(['Err: ' ME.message]); uialert(app.UIFigure, ME.message,'Error'); end
            close(d);
        end
        
        function export_processed_refs(app)
            % 导出 Ref Stack 也需要保持 uint16
            if isempty(app.RefPath920) || isempty(app.RefPath1030), uialert(app.UIFigure, 'Please load refs.', 'Err'); return; end
            p = uigetdir(pwd, 'Save Ref Stacks'); if p==0, return; end
            out9 = fullfile(p, 'Ref_Master_920_Stack.tif'); out10 = fullfile(p, 'Ref_Aligned_1030_Stack.tif');
            if isfile(out9), delete(out9); end; if isfile(out10), delete(out10); end
            
            d=uiprogressdlg(app.UIFigure,'Title','Exporting Ref Stacks','Indeterminate','on');
            
            % Process 920
            info = imfinfo(app.RefPath920); n=numel(info);
            tmp=imread(app.RefPath920,1); refView=imref2d(size(tmp));
            for k=1:n
                img = double(imread(app.RefPath920, k));
                if ~isempty(app.Tform920), img=imwarp(img,app.Tform920,'OutputView',refView,'FillValues',mean(img(:))); end
                imwrite(uint16(img), out9, 'WriteMode','append','Compression','none');
            end
            
            % Process 1030
            info = imfinfo(app.RefPath1030); n=numel(info);
            for k=1:n
                img = double(imread(app.RefPath1030, k));
                if ~isempty(app.Tform1030), img=imwarp(img,app.Tform1030,'OutputView',refView,'FillValues',mean(img(:))); end
                img = imtranslate(img, [app.Shift_ChannelX, app.Shift_ChannelY], 'FillValues', 0);
                imwrite(uint16(img), out10, 'WriteMode','append','Compression','none');
            end
            close(d); uialert(app.UIFigure,'Ref Stacks Exported','Success');
        end

        % Utils
        function frame=read_tiff_frame(~,info,idx), nF=length(info.file_list); nP=info.total_frames/nF; fI=ceil(idx/nP); lI=mod(idx-1,nP)+1; frame=imread(info.file_list{fI},lI); end
        function info=get_tiff_info(~,flist), info.file_list=flist; info.total_frames=0; if ~isempty(flist), info.total_frames=numel(imfinfo(flist{1}))*length(flist); end, end
        function list=get_tiff_list(~,p), d=dir(fullfile(p,'*.tif')); nums=arrayfun(@(x) str2double(regexp(x.name,'\d+','match','once')), d); [~,i]=sort(nums); d=d(i); list=fullfile({d.folder},{d.name}); end
        function enable_controls(app), app.BtnPlay.Enable='on'; app.SliderFrame.Enable='on'; app.SliderX.Enable='on'; app.SliderY.Enable='on'; end
        function OnLoadToolbox(app), f=uigetdir; if f, addpath(genpath(f)); app.LblToolbox.Text='Ready'; app.ChkNoRMCorre.Enable='on'; end, end
        function OnPlay(app), if app.IsPlaying, stop(app.PlayTimer); app.IsPlaying=false; app.BtnPlay.Text='▶'; else, start(app.PlayTimer); app.IsPlaying=true; app.BtnPlay.Text='⏸'; end, end
        function on_timer(app), if ~app.IsPlaying, return; end; nx=app.CurrentFrameIdx+1; if nx>app.NumPreviewFrames, nx=1; end; app.SliderFrame.Value=nx; app.update_display_frame(); end
        function OnSlider(app), app.Shift_ManualX=app.SliderX.Value; app.Shift_ManualY=app.SliderY.Value; app.update_display_frame(); end
    end
    
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible','off','Position',[50 50 1300 900],'Name','Microscope RefExport v27.0');
            app.GridLayout = uigridlayout(app.UIFigure,[1 2]); app.GridLayout.ColumnWidth={300,'1x'};
            
            % === Left Panel ===
            app.LeftPanel = uipanel(app.GridLayout);
            
            app.PanelStatic = uipanel(app.LeftPanel, 'Title','1. 静态参考 (Master)','Position',[10 580 280 280]);
            app.BtnJson920 = uibutton(app.PanelStatic,'Text','JSON 920','Position',[10 220 80 30], 'ButtonPushedFcn',@(~,~)app.load_json('920'));
            app.BtnJson1030 = uibutton(app.PanelStatic,'Text','JSON 1030','Position',[100 220 80 30], 'ButtonPushedFcn',@(~,~)app.load_json('1030'));
            app.BtnLoadRef920 = uibutton(app.PanelStatic,'Text','Ref 920','Position',[10 170 120 30], 'ButtonPushedFcn',@(~,~)app.OnLoadRef('920'));
            app.BtnLoadRef1030 = uibutton(app.PanelStatic,'Text','Ref 1030','Position',[10 130 120 30], 'ButtonPushedFcn',@(~,~)app.OnLoadRef('1030'));
            app.BtnAlignStatic = uibutton(app.PanelStatic,'Text','Calc Ref Align','Position',[10 80 120 30],'BackgroundColor',[0.8 0.9 1], 'ButtonPushedFcn',@(~,~)app.calc_static_alignment());
            app.LblStaticStatus = uilabel(app.PanelStatic,'Text','-','Position',[140 85 130 20]);
            app.BtnExportRef = uibutton(app.PanelStatic,'Text','Export Ref Stacks','Position',[10 30 180 30],'Enable','off','BackgroundColor',[1 0.9 0.6], 'ButtonPushedFcn',@(~,~)app.export_processed_refs());
            
            app.PanelMotion = uipanel(app.LeftPanel, 'Title','2. 运动去抖','Position',[10 440 280 130]);
            app.BtnLoadToolbox = uibutton(app.PanelMotion,'Text','Load NoRMCorre','Position',[10 70 120 30], 'ButtonPushedFcn',@(~,~)app.OnLoadToolbox());
            app.LblToolbox = uilabel(app.PanelMotion,'Text','-','Position',[140 75 100 20]);
            app.ChkNoRMCorre = uicheckbox(app.PanelMotion,'Text','启用去抖动 (De-jitter)','Position',[10 30 200 20],'Enable','off','Value',true);
            
            app.PanelAction = uipanel(app.LeftPanel, 'Title','3. 处理','Position',[10 20 280 400]);
            app.BtnSelectFolder = uibutton(app.PanelAction,'Text','Select Folders','Position',[10 330 260 40], 'ButtonPushedFcn',@(~,~)app.OnSingleSelect());
            app.LblFolder = uilabel(app.PanelAction,'Text','-','Position',[10 305 260 20]);
            app.BtnPreview = uibutton(app.PanelAction,'Text','Preview (First 30 Frames)','Position',[10 240 260 40],'Enable','off', 'ButtonPushedFcn',@(~,~)app.run_preview_calc());
            app.BtnExport = uibutton(app.PanelAction,'Text','Export All (16-bit)','Position',[10 180 260 50],'BackgroundColor',[0.6 1 0.6],'Enable','off','FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.process_export());
            app.TxtLog = uitextarea(app.PanelAction, 'Position',[10 10 260 150]);
            
            % === Right Panel ===
            app.RightPanel = uipanel(app.GridLayout); app.RightPanel.BackgroundColor='k'; app.RightPanel.Layout.Column = 2;
            app.TabGroupPreview = uitabgroup(app.RightPanel, 'Position', [10 200 950 650], 'SelectionChangedFcn', @(~,~)app.update_display_frame());
            
            app.TabStatic = uitab(app.TabGroupPreview, 'Title', '0. Ref Raw');
            app.GridStatic = uigridlayout(app.TabStatic, [1 2]);
            app.AxRef920 = uiaxes(app.GridStatic, 'Color','k', 'XColor','none', 'YColor','none');
            app.AxRef1030 = uiaxes(app.GridStatic, 'Color','k', 'XColor','none', 'YColor','none');
            
            app.TabRefCheck = uitab(app.TabGroupPreview, 'Title', '0.5 Ref Check');
            app.AxRefCheck = uiaxes(app.TabRefCheck, 'Position', [10 10 930 600], 'Color','k', 'XColor','none', 'YColor','none');
            
            app.TabOverlay = uitab(app.TabGroupPreview, 'Title', '1. Motion Overlay');
            app.AxOverlay = uiaxes(app.TabOverlay, 'Position', [10 10 930 600], 'Color','k', 'XColor','none', 'YColor','none');
            
            app.TabSideBySide = uitab(app.TabGroupPreview, 'Title', '2. Side-by-Side');
            app.GridSide = uigridlayout(app.TabSideBySide, [1 2]);
            app.AxSideG = uiaxes(app.GridSide, 'Color','k', 'XColor','none', 'YColor','none');
            app.AxSideR = uiaxes(app.GridSide, 'Color','k', 'XColor','none', 'YColor','none');
            
            app.PanelPlayer = uipanel(app.RightPanel,'Position',[10 160 950 30],'BackgroundColor',[0.2 0.2 0.2],'BorderType','none');
            app.BtnPlay = uibutton(app.PanelPlayer,'Text','▶','Position',[5 0 30 30],'Enable','off', 'ButtonPushedFcn',@(~,~)app.OnPlay());
            app.SliderFrame = uislider(app.PanelPlayer,'Position',[50 10 800 3],'Limits',[1 30],'Enable','off', 'ValueChangedFcn',@(~,~)app.update_display_frame());
            app.LblFrameInfo = uilabel(app.PanelPlayer,'Text','0/0','Position',[870 5 80 20],'FontColor','w');
            
            app.PanelTuning = uipanel(app.RightPanel, 'Title','微调','Position',[10 10 950 140], 'BackgroundColor',[0.9 0.9 0.9]);
            app.SliderX = uislider(app.PanelTuning,'Position',[100 90 300 3],'Limits',[-50 50],'Enable','off','ValueChangedFcn',@(~,~)app.OnSlider());
            app.SliderY = uislider(app.PanelTuning,'Position',[100 40 300 3],'Limits',[-50 50],'Enable','off','ValueChangedFcn',@(~,~)app.OnSlider());
            uilabel(app.PanelTuning,'Text','X:','Position',[80 80 20 20]); uilabel(app.PanelTuning,'Text','Y:','Position',[80 30 20 20]);
            app.LblShiftInfo = uilabel(app.PanelTuning,'Text','Manual: 0, 0','Position',[450 60 150 20]);
            app.BtnContrast = uibutton(app.PanelTuning,'state','Text','增强预览对比度','Position',[650 60 120 30],'ValueChangedFcn',@(~,~)app.update_display_frame());
            
            app.PlayTimer = timer('ExecutionMode','fixedRate','Period',0.1,'TimerFcn',@(~,~) app.on_timer());
            app.UIFigure.Visible='on';
        end
    end
    
    methods (Access = public)
        function app = Microscope_RefExport_v27
            createComponents(app); registerApp(app, app.UIFigure); app.log('v27.0 Ready');
        end
        function delete(app), delete(app.UIFigure); delete(app.PlayTimer); end
    end
end