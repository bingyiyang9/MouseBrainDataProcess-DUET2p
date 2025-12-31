classdef Microscope_Registration_new < matlab.apps.AppBase
    % Microscope Registration Tool v15.0 (Z-Drift + Rolling Template)
    % Author: yangbingyi 2025/12/29
    % Update v15.0: 新增 Z轴滑动窗平滑 和 动态滚动参考模板(解决Z轴漂移问题)
    
    % =====================================================================
    % 1. UI 组件
    % =====================================================================
    properties (Access = public)
        UIFigure             matlab.ui.Figure
        GridLayout           matlab.ui.container.GridLayout
    
        LeftPanel            matlab.ui.container.Panel
        RightPanel           matlab.ui.container.Panel
        
        PanelToolbox         matlab.ui.container.Panel
        BtnLoadToolbox       matlab.ui.control.Button
        LblToolboxStatus     matlab.ui.control.Label
        
        PanelJson            matlab.ui.container.Panel
        BtnJson920           matlab.ui.control.Button
        LblJson920           matlab.ui.control.Label
        BtnJson1030          matlab.ui.control.Button
        LblJson1030          matlab.ui.control.Label
        
        PanelPre             matlab.ui.container.Panel
        ChkMotion            matlab.ui.control.CheckBox
        
        % === 新增 UI 组件 ===
        ChkRolling           matlab.ui.control.CheckBox % 滚动模板开关
        ChkZSmooth           matlab.ui.control.CheckBox % Z轴平滑开关
        LblZWin              matlab.ui.control.Label
        EditZWin             matlab.ui.control.NumericEditField
        % ===================

        LblMaster            matlab.ui.control.Label
        DropDownMaster       matlab.ui.control.DropDown
        LblGrid              matlab.ui.control.Label
        EditGrid             matlab.ui.control.NumericEditField
        LblMaxShift          matlab.ui.control.Label
        EditMaxShift         matlab.ui.control.NumericEditField
        LblMethod            matlab.ui.control.Label
        DropDownMethod       matlab.ui.control.DropDown
        
        TabGroup             matlab.ui.container.TabGroup
        TabSingle            matlab.ui.container.Tab
        TabBatch             matlab.ui.container.Tab
        
        BtnSelectFolder      matlab.ui.control.Button
        LblFolder            matlab.ui.control.Label
        BtnPreview           matlab.ui.control.Button
        BtnExport            matlab.ui.control.Button
        
        BtnScan              matlab.ui.control.Button
        BtnClear             matlab.ui.control.Button
        ListBatch            matlab.ui.control.ListBox
        BtnBatchPreview      matlab.ui.control.Button
        BtnBatchRun          matlab.ui.control.Button
        
        TxtLog               matlab.ui.control.TextArea
        LblAuthor            matlab.ui.control.Label
        
        AxMerged             matlab.ui.control.UIAxes
        PanelTopCtrl         matlab.ui.container.Panel
        SwitchViewMode       matlab.ui.control.Switch
        LblViewMode          matlab.ui.control.Label
        
        PanelPlayer          matlab.ui.container.Panel
        BtnPlay              matlab.ui.control.Button
        SliderFrame          matlab.ui.control.Slider
        LblFrameInfo         matlab.ui.control.Label
        
        PanelTuning          matlab.ui.container.Panel
        SliderX              matlab.ui.control.Slider
        SliderY              matlab.ui.control.Slider
        BtnLeft              matlab.ui.control.Button
        BtnRight             matlab.ui.control.Button
        BtnUp                matlab.ui.control.Button
        BtnDown              matlab.ui.control.Button
        LblShiftInfo         matlab.ui.control.Label
        BtnContrast          matlab.ui.control.StateButton
        BtnGroupView         matlab.ui.container.ButtonGroup
        RadMerge             matlab.ui.control.RadioButton
        RadGreen             matlab.ui.control.RadioButton
        RadRed               matlab.ui.control.RadioButton
    end

    % =====================================================================
    % 2. 数据属性
    % =====================================================================
    properties (Access = private)
        PathJson920=''; PathJson1030=''; SingleFolderPath='';
        Tform920; Tform1030;
        
        Stack_Raw_G; Stack_Raw_R; 
        Stack_Corr_G; Stack_Corr_R; 
        
        NumPreviewFrames = 0;
        CurrentFrameIdx = 1;
        IsPlaying = false;
        PlayTimer
    
        CurrentShiftX = -3; CurrentShiftY = -32;
        BatchTasks = struct('Name', {}, 'Folder', {}, 'Paths920', {}, 'Paths1030', {});
        HImageObject

        SingleFolderPaths;
        TiffInfo920;
        TiffInfo1030;
    end

    % =====================================================================
    % 3. 核心逻辑
    % =====================================================================
    methods (Access = private)

        function log(app, msg)
            t = datestr(now, 'HH:MM:SS');
            app.TxtLog.Value = [app.TxtLog.Value; {sprintf('[%s] %s', t, msg)}];
            scroll(app.TxtLog, 'bottom');
            drawnow limitrate;
        end

        % --- TIFF Series Reader Helpers ---
        function file_list = get_sorted_tiff_files(~, folder_path)
            if ~isfolder(folder_path), file_list = {}; return; end
            d = [dir(fullfile(folder_path, '*.tif')); dir(fullfile(folder_path, '*.tff'))];
            if isempty(d), file_list = {}; return; end
            
            nums = zeros(length(d), 1);
            for i = 1:length(d)
                num_str = regexp(d(i).name, '\d+', 'match');
                if ~isempty(num_str)
                    nums(i) = str2double(num_str{end});
                end
            end
            [~, sort_idx] = sort(nums);
            d_sorted = d(sort_idx);
            file_list = fullfile({d_sorted.folder}, {d_sorted.name});
        end

        function info = get_tiff_info(~, file_list)
            info.file_list = file_list;
            info.num_files = length(file_list);
            info.frames_per_file = zeros(info.num_files, 1);
            for i = 1:info.num_files
                info.frames_per_file(i) = numel(imfinfo(file_list{i}));
            end
            info.cumulative_frames = cumsum(info.frames_per_file);
            info.total_frames = info.cumulative_frames(end);
        end

        function frame_data = read_tiff_frame(~, tiff_info, global_index)
            if global_index > tiff_info.total_frames || global_index < 1
                error('Frame index %d is out of bounds.', global_index);
            end
            
            file_idx = find(tiff_info.cumulative_frames >= global_index, 1, 'first');
            if file_idx == 1
                local_index = global_index;
            else
                local_index = global_index - tiff_info.cumulative_frames(file_idx - 1);
            end
            frame_data = imread(tiff_info.file_list{file_idx}, local_index);
        end

        % --- Core Functions ---
        function status = check_normcorre(app)
            if ~isempty(which('normcorre_batch'))
                status=true;
                app.LblToolboxStatus.Text='NoRMCorre: 就绪'; app.LblToolboxStatus.FontColor=[0 0.6 0]; 
                app.ChkMotion.Enable='on';
            else
                status=false;
                app.LblToolboxStatus.Text='未加载'; app.LblToolboxStatus.FontColor=[0.8 0 0]; 
                app.ChkMotion.Enable='off'; app.ChkMotion.Value=0;
            end
        end

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
        
        function Template = make_robust_template(app, stackData)
            app.log('生成初始参考模板...');
            [d1,d2,~] = size(stackData);
            opt_rigid = NoRMCorreSetParms('d1',d1, 'd2',d2, 'grid_size',[d1,d2], 'mot_uf',4, 'max_shift', app.EditMaxShift.Value, 'bin_width',50, 'use_parallel', false); 
            [M_rigid, ~, ~] = normcorre_batch(stackData, opt_rigid);
            Template = mean(M_rigid, 3);
        end

        % === 新增算法：Z轴滑动窗平滑 ===
        function stack_out = apply_z_sliding_window(app, stack_in)
            % 获取窗口大小 (确保为奇数)
            w_size = app.EditZWin.Value;
            if mod(w_size, 2) == 0, w_size = w_size + 1; end
            
            % 使用 MATLAB 内置 movmean 进行时域平滑
            % dim=3 表示沿时间轴处理, 'Endpoints','shrink' 处理边缘
            stack_out = movmean(stack_in, w_size, 3, 'Endpoints', 'shrink');
        end
        % ==============================

        function run_preview_calc(app, p920_list, p1030_list)
            if isempty(app.Tform920), uialert(app.UIFigure,'请加载920 JSON','Err'); return; end
            
            d = uiprogressdlg(app.UIFigure, 'Title', '预览', 'Message', '读取文件信息...', 'Indeterminate', 'on');
            drawnow;
            
            try
                app.TiffInfo920 = app.get_tiff_info(p920_list);
                app.TiffInfo1030 = app.get_tiff_info(p1030_list);
                
                if app.TiffInfo920.total_frames ~= app.TiffInfo1030.total_frames
                    error('Channels have different total frame counts!');
                end

                nTotalFrames = app.TiffInfo920.total_frames;
                nRead = min(nTotalFrames, 20); 
                app.NumPreviewFrames = nRead;
                
                d.Message = '读取前20帧...';
                
                tmp = app.read_tiff_frame(app.TiffInfo920, 1);
                ref = imref2d(size(tmp));
                U9 = zeros(size(tmp,1), size(tmp,2), nRead, 'single');
                U10 = zeros(size(tmp,1), size(tmp,2), nRead, 'single');
                Raw9 = zeros(size(tmp,1), size(tmp,2), nRead, 'uint8');
                Raw10 = zeros(size(tmp,1), size(tmp,2), nRead, 'uint8');
                
                for k=1:nRead
                    I9 = double(app.read_tiff_frame(app.TiffInfo920, k));
                    I10 = double(app.read_tiff_frame(app.TiffInfo1030, k));
                    
                    Raw9(:,:,k) = app.simple_uint8(I9);
                    Raw10(:,:,k) = app.simple_uint8(I10);
                    
                    U9(:,:,k) = imwarp(I9, app.Tform920, 'OutputView', ref, 'FillValues', mean(I9(:)));
                    U10(:,:,k) = imwarp(I10, app.Tform1030, 'OutputView', ref, 'FillValues', mean(I10(:)));
                end
                
                app.Stack_Raw_G = Raw9;
                app.Stack_Raw_R = Raw10;
                
                if app.ChkMotion.Value && app.check_normcorre()
                    app.log('NoRMCorre 计算中...');
                    d.Message = '计算位移场...';
                    isRigid = strcmp(app.DropDownMethod.Value, '刚性 (Rigid)');
                    masterCh = app.DropDownMaster.Value;
                    gridSz = app.EditGrid.Value; maxSh = app.EditMaxShift.Value;
                    [h,w,~] = size(U9);
                    if strcmp(masterCh, 'Green (920)'), MasterStack = U9; else, MasterStack = U10; end
                    
                    Template = app.make_robust_template(MasterStack);
                    
                    if isRigid
                        options = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[h,w], 'mot_uf',4,'bin_width',50, 'max_shift',maxSh, 'use_parallel', false);
                    else
                        options = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[gridSz,gridSz], 'mot_uf',4,'bin_width',50, 'max_shift',maxSh, 'use_parallel', false);
                    end
                    
                    if strcmp(masterCh, 'Green (920)')
                        [U9, shifts, ~] = normcorre_batch(U9, options, Template);
                        U10 = apply_shifts(U10, shifts, options);       
                    else
                        [U10, shifts, ~] = normcorre_batch(U10, options, Template);
                        U9 = apply_shifts(U9, shifts, options);           
                    end
                end
                
                % === 应用 Z 轴平滑 (仅在预览时简单应用) ===
                if app.ChkZSmooth.Value
                    app.log('应用 Z 轴平滑 (Preview)...');
                    U9 = app.apply_z_sliding_window(U9);
                    U10 = app.apply_z_sliding_window(U10);
                end
                % ======================================

                app.Stack_Corr_G = app.batch_convert_uint8(U9);
                app.Stack_Corr_R = app.batch_convert_uint8(U10);
                app.SliderFrame.Limits = [1, nRead]; app.SliderFrame.Value = 1;
                app.CurrentFrameIdx = 1; app.enable_controls();
                if app.TabGroup.SelectedTab==app.TabSingle, app.BtnExport.Enable='on'; end
                cla(app.AxMerged);
                app.HImageObject = imshow(zeros(size(tmp),'uint8'), 'Parent', app.AxMerged);
                app.update_display_frame();
                app.log('预览就绪。');
            catch ME
                app.log(['Err: ' ME.message]);
                uialert(app.UIFigure,ME.message,'Err');
            end
            close(d);
        end
        
        % === 全量导出 (包含 动态模板 和 缓冲Z平滑) ===
        function process_export(app, p920_list, p1030_list, outDir, dx, dy)
            tiff_info920 = app.get_tiff_info(p920_list);
            tiff_info1030 = app.get_tiff_info(p1030_list);
            
            if tiff_info920.total_frames ~= tiff_info1030.total_frames
                app.log('Export Error: Frame counts mismatch.');
                uialert(app.UIFigure, 'Export failed: Frame counts mismatch.', 'Error');
                return;
            end

            nF = tiff_info920.total_frames;
            tmp_frame = app.read_tiff_frame(tiff_info920, 1);
            [h, w] = size(tmp_frame);
            
            app.log('正在生成输出文件列表...');
            output_filenames_G = cell(size(p920_list));
            for i = 1:length(p920_list)
                [~, name, ext] = fileparts(p920_list{i});
                output_filenames_G{i} = fullfile(outDir, ['Corrected_920nm_' name ext]);
            end
            output_filenames_R = cell(size(p1030_list));
            for i = 1:length(p1030_list)
                [~, name, ext] = fileparts(p1030_list{i});
                output_filenames_R{i} = fullfile(outDir, ['Corrected_1030nm_' name ext]);
            end
            
            app.log('清理旧文件...');
            for i = 1:length(output_filenames_G), if isfile(output_filenames_G{i}), delete(output_filenames_G{i}); end; end
            for i = 1:length(output_filenames_R), if isfile(output_filenames_R{i}), delete(output_filenames_R{i}); end; end
            
            d = uiprogressdlg(app.UIFigure, 'Title', '导出', 'Message', '初始化...', 'Cancelable','on');
            
            useMotion = app.ChkMotion.Value && app.check_normcorre();
            useRolling = app.ChkRolling.Value; % 是否启用动态模板
            useZSmooth = app.ChkZSmooth.Value; % 是否启用Z轴平滑
            winSize = app.EditZWin.Value;
            pad = 0; 
            if useZSmooth, pad = ceil(winSize/2); end % 计算缓冲边缘大小

            CurrentTemplate = []; options = []; 
            masterCh = app.DropDownMaster.Value;
            ref = imref2d([h, w]);
            
            if useMotion
                d.Message = '生成初始参考模板 (前30帧)...';
                nTemp = min(nF, 30);
                TStack = zeros(h, w, nTemp, 'single');
                master_tiff_info = tiff_info920;
                if strcmp(masterCh, 'Red (1030)'), master_tiff_info = tiff_info1030; end
                tformRef = app.Tform920;
                if strcmp(masterCh, 'Red (1030)'), tformRef = app.Tform1030; end
                for k=1:nTemp
                    raw = double(app.read_tiff_frame(master_tiff_info, k));
                    TStack(:,:,k) = imwarp(raw, tformRef, 'OutputView', ref, 'FillValues', mean(raw(:)));
                end
                
                % 初始模板
                CurrentTemplate = app.make_robust_template(TStack);
                clear TStack;
                
                gridSz = app.EditGrid.Value; maxSh = app.EditMaxShift.Value;
                isRigid = strcmp(app.DropDownMethod.Value, '刚性 (Rigid)');
                if isRigid
                    options = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[h,w], 'mot_uf',4, 'max_shift',maxSh, 'bin_width',50, 'use_parallel',false);
                else
                    options = NoRMCorreSetParms('d1',h,'d2',w, 'grid_size',[gridSz,gridSz], 'mot_uf',4, 'max_shift',maxSh, 'bin_width',50, 'max_dev',8, 'us_fac',50, 'overlap_pre',16, 'iter',1, 'use_parallel',false);
                end
            end
            
            BlockSize = 50;
            nBlocks = ceil(nF / BlockSize);
            
            try
                for b = 1:nBlocks
                    if d.CancelRequested, break; end
                    
                    % 1. 计算核心区 (Core) 索引
                    idxS_core = (b-1)*BlockSize + 1;
                    idxE_core = min(b*BlockSize, nF);
                    nIn_core = idxE_core - idxS_core + 1;
                    
                    % 2. 计算带缓冲 (Padded) 索引
                    % 如果启用Z平滑，需多读前后 pad 帧，避免接缝处断层
                    if useZSmooth
                        idxS_read = max(1, idxS_core - pad);
                        idxE_read = min(nF, idxE_core + pad);
                    else
                        idxS_read = idxS_core;
                        idxE_read = idxE_core;
                    end
                    nIn_read = idxE_read - idxS_read + 1;

                    d.Value = (b-1)/nBlocks; 
                    if useRolling
                        d.Message = sprintf('处理块 %d/%d (动态模板更新中)...', b, nBlocks);
                    else
                        d.Message = sprintf('处理块 %d/%d...', b, nBlocks);
                    end
                    
                    % 3. 读取 (Padded Read)
                    B9 = zeros(h, w, nIn_read, 'single'); 
                    B10 = zeros(h, w, nIn_read, 'single');
                    
                    for c = 1:nIn_read
                         k = idxS_read + c - 1;
                         raw9 = double(app.read_tiff_frame(tiff_info920, k));
                         raw10 = double(app.read_tiff_frame(tiff_info1030, k));
                         B9(:,:,c) = imwarp(raw9, app.Tform920, 'OutputView', ref, 'FillValues', mean(raw9(:)));
                         B10(:,:,c) = imwarp(raw10, app.Tform1030, 'OutputView', ref, 'FillValues', mean(raw10(:)));
                    end
                    
                    % 4. 运动校正 (Motion Correction)
                    if useMotion
                        % 使用 CurrentTemplate 进行校正
                        if strcmp(masterCh, 'Green (920)')
                             [~, shifts, ~] = normcorre_batch(B9, options, CurrentTemplate);
                        else
                             [~, shifts, ~] = normcorre_batch(B10, options, CurrentTemplate);
                        end
                        B9 = apply_shifts(B9, shifts, options);
                        B10 = apply_shifts(B10, shifts, options);
                        
                        % 动态模板更新逻辑 (Rolling Template)
                        if useRolling
                            % 计算当前 Padded 块的均值作为新参考
                            % 为了稳定，取中间部分
                            if strcmp(masterCh, 'Green (920)')
                                NewRef = mean(B9, 3);
                            else
                                NewRef = mean(B10, 3);
                            end
                            % 采用平滑更新：新模板 = 0.7*新值 + 0.3*旧值
                            CurrentTemplate = 0.7 * NewRef + 0.3 * CurrentTemplate;
                        end
                    end
                    
                    % 5. Z轴滑动平滑 (Z-Smoothing)
                    if useZSmooth
                        B9 = movmean(B9, winSize, 3, 'Endpoints', 'shrink');
                        B10 = movmean(B10, winSize, 3, 'Endpoints', 'shrink');
                    end
                    
                    % 6. 裁切回核心区 (Crop to Core)
                    rel_start = idxS_core - idxS_read + 1;
                    rel_end = rel_start + nIn_core - 1;
                    
                    C9_Final = B9(:, :, rel_start:rel_end);
                    C10_Final = B10(:, :, rel_start:rel_end);
                    
                    % 7. 写入
                    for i = 1:nIn_core
                         global_frame_idx = idxS_core + i - 1;
                         file_idx_G = find(tiff_info920.cumulative_frames >= global_frame_idx, 1, 'first');
                         output_file_G = output_filenames_G{file_idx_G};
                         
                         file_idx_R = find(tiff_info1030.cumulative_frames >= global_frame_idx, 1, 'first');
                         output_file_R = output_filenames_R{file_idx_R};
                         
                         % 手动Shift (可选)
                         ImgG_out = uint16(C9_Final(:,:,i));
                         ImgR_out = uint16(C10_Final(:,:,i));
                         
                         % 如果有手动偏移 dx, dy
                         if dx~=0 || dy~=0
                             ImgR_out = imtranslate(ImgR_out, [dx, dy], 'FillValues', 0);
                         end
                         
                         imwrite(ImgG_out, output_file_G, 'WriteMode','append','Compression','none');
                         imwrite(ImgR_out, output_file_R, 'WriteMode','append','Compression','none');
                    end
                    drawnow;
                end
                if d.CancelRequested
                    app.log('Export cancelled by user.');
                else
                    app.log(['OK: Export completed for ' outDir]);
                    uialert(app.UIFigure, '完成', 'Success');
                end
            catch ME
                app.log(['Fail: ' ME.message]);
                uialert(app.UIFigure, ME.message, 'Fail');
            end
            close(d);
        end
        
        % --- Display & Utility Functions ---
        function update_display_frame(app)
            if isempty(app.Stack_Corr_G), return; end
            f = round(app.SliderFrame.Value);
            if f > size(app.Stack_Corr_G, 3), f = 1; app.SliderFrame.Value = 1; end
            app.CurrentFrameIdx = f;
            app.LblFrameInfo.Text = sprintf('%d / %d', f, app.NumPreviewFrames);
            isRaw = strcmp(app.SwitchViewMode.Value, '原始(Raw)');
            if isRaw
                ImgG = single(app.Stack_Raw_G(:,:,f));
                ImgR = single(app.Stack_Raw_R(:,:,f)); 
                dx=0; dy=0; titleStr = '原始数据 (Raw)';
            else
                ImgG = single(app.Stack_Corr_G(:,:,f));
                ImgR = single(app.Stack_Corr_R(:,:,f)); 
                dx = app.CurrentShiftX; dy = app.CurrentShiftY;
                titleStr = sprintf('校正后预览 (X:%d, Y:%d)', dx, dy);
            end
            if dx~=0 || dy~=0, ImgR = imtranslate(ImgR, [dx, dy], 'FillValues', 0); end
            [VisG, VisR] = app.get_display_channels(ImgG, ImgR);
            Z = zeros(size(VisG), 'uint8'); 
            sel = app.BtnGroupView.SelectedObject;
            if isRaw, F = cat(3, VisR, VisG, Z);
            else
                if sel == app.RadMerge, F = cat(3, VisR, VisG, Z);
                elseif sel == app.RadGreen, F = cat(3, Z, VisG, Z);
                elseif sel == app.RadRed, F = cat(3, VisR, Z, Z);
                end
            end
            app.HImageObject.CData = F;
            title(app.AxMerged, titleStr, 'Color','w');
            app.LblShiftInfo.Text = sprintf('X: %d | Y: %d', app.CurrentShiftX, app.CurrentShiftY);
        end
        
        function [outG, outR] = get_display_channels(app, inG, inR)
            if app.BtnContrast.Value
                outG = app.apply_smart_contrast(inG);
                outR = app.apply_smart_contrast(inR);
            else
                outG = app.apply_linear_stretch(inG);
                outR = app.apply_linear_stretch(inR);
            end
        end
        
        function out = apply_smart_contrast(~, img)
            mask = img > 0;
            if ~any(mask(:)), out = uint8(img); return; end
            v_min = min(img(mask));
            v_max = max(img(mask));
            img_norm = (img - v_min) / (v_max - v_min + eps); img_norm(img_norm<0)=0; img_norm(img_norm>1)=1;
            out = uint8(adapthisteq(img_norm, 'ClipLimit', 0.02) * 255);
        end
        
        function out = apply_linear_stretch(~, img)
             mask = img > 0;
             if ~any(mask(:)), out = uint8(img); return; end
             v = sort(img(mask));
             low = v(round(numel(v)*0.005)+1); high = v(round(numel(v)*0.995));
             img_norm = (img - low) / (high - low + eps);
             img_norm(img_norm < 0) = 0; img_norm(img_norm > 1) = 1;
             out = uint8(img_norm * 255);
        end

        function out = simple_uint8(~, img)
             v_min = min(img(:));
             v_max = max(img(:));
             if v_max==v_min, out=uint8(img); return; end
             n = (img - v_min) / (v_max - v_min);
             out = uint8(n * 255);
        end
        function stack8 = batch_convert_uint8(app, stackSingle)
             stack8 = zeros(size(stackSingle), 'uint8');
             for k=1:size(stackSingle,3), stack8(:,:,k) = app.simple_uint8(stackSingle(:,:,k)); end
        end
        
        % --- UI Callbacks ---
        function on_timer(app), if ~app.IsPlaying, return; end; nx=app.CurrentFrameIdx+1; if nx>app.NumPreviewFrames, nx=1; end; app.SliderFrame.Value=nx; app.update_display_frame(); end
        function enable_controls(app), app.SliderX.Enable='on'; app.SliderY.Enable='on';
            app.BtnLeft.Enable='on'; app.BtnRight.Enable='on'; app.BtnUp.Enable='on'; app.BtnDown.Enable='on'; app.SliderFrame.Enable='on'; app.BtnPlay.Enable='on'; app.SwitchViewMode.Enable='on'; app.BtnContrast.Enable='on'; app.RadMerge.Enable='on'; app.RadGreen.Enable='on'; app.RadRed.Enable='on';
        end
        function OnNudge(app, ax, d), if strcmp(ax,'x'), app.SliderX.Value=app.SliderX.Value+d; app.CurrentShiftX=app.SliderX.Value; else, app.SliderY.Value=app.SliderY.Value+d; app.CurrentShiftY=app.SliderY.Value; end;
            app.update_display_frame(); end
        function OnSlider(app, ~), app.CurrentShiftX=round(app.SliderX.Value); app.CurrentShiftY=round(app.SliderY.Value); app.update_display_frame();
        end
        function OnPlay(app), if app.IsPlaying, stop(app.PlayTimer); app.IsPlaying=false; app.BtnPlay.Text='▶'; else, start(app.PlayTimer); app.IsPlaying=true; app.BtnPlay.Text='⏸';
        end, end
        function OnSliderFrame(app), if app.IsPlaying, stop(app.PlayTimer); app.IsPlaying=false; app.BtnPlay.Text='▶'; end; app.update_display_frame();
        end
        
        function paths = check_struct(app, f)
            paths.p1 = app.get_sorted_tiff_files(fullfile(f, 'CellVideo1', 'CellVideo'));
            paths.p2 = app.get_sorted_tiff_files(fullfile(f, 'CellVideo2', 'CellVideo'));
            if isempty(paths.p1) || isempty(paths.p2)
                paths.p1 = {};
                paths.p2 = {};
                app.log(['Warning: Could not find valid TIFF series in ' f]);
            end
        end

        function OnClickLoadToolbox(app, ~)
            f=uigetdir(pwd,'Select NoRMCorre');
            if f~=0
                addpath(genpath(f)); 
                app.check_normcorre(); 
                app.auto_patch_nanmean(f);
            end
        end

        function auto_patch_nanmean(~, folder)
            p=fullfile(folder,'nanmean.m');
            if ~isfile(p)&&isempty(which('nanmean')), fid=fopen(p,'w'); fprintf(fid,'function m=nanmean(v,d),if nargin<2,m=mean(v,''omitnan'');else,m=mean(v,d,''omitnan'');end,end'); fclose(fid); end
            p2=fullfile(folder,'nanmedian.m');
            if ~isfile(p2)&&isempty(which('nanmedian')), fid=fopen(p2,'w'); fprintf(fid,'function m=nanmedian(v,d),if nargin<2,m=median(v,''omitnan'');else,m=median(v,d,''omitnan'');end,end'); fclose(fid); end
        end

        function OnJson920(app, ~), [f,p]=uigetfile('*.json');
            if f, app.PathJson920=fullfile(p,f); if app.load_json(app.PathJson920,'920nm'), app.LblJson920.Text=f; app.LblJson920.FontColor=[0 0.6 0]; end, end, end
        function OnJson1030(app, ~), [f,p]=uigetfile('*.json');
            if f, app.PathJson1030=fullfile(p,f); if app.load_json(app.PathJson1030,'1030nm'), app.LblJson1030.Text=f; app.LblJson1030.FontColor=[0.8 0 0]; end, end, end
        
        function OnSingleSelect(app, ~)
            p=uigetdir;
            if p
                paths = app.check_struct(p);
                if isempty(paths.p1)
                    uialert(app.UIFigure,'Folder does not contain valid CellVideo1/2 subfolders or TIFF files.','Error');
                    return;
                end
                app.SingleFolderPath = p;
                app.SingleFolderPaths = paths;
                [~,n] = fileparts(p); 
                app.LblFolder.Text = n; 
                app.BtnPreview.Enable = 'on';
            end
        end
        function OnSingleLoad(app, ~), paths = app.SingleFolderPaths;
            app.run_preview_calc(paths.p1, paths.p2); end
        function OnSingleExport(app, ~)
            if isempty(app.TiffInfo920)
                uialert(app.UIFigure, 'Please run preview before exporting.', 'Error');
                return;
            end
            out = fullfile(app.SingleFolderPath, 'Corrected_Results'); 
            if ~isfolder(out), mkdir(out); end
            app.process_export(app.TiffInfo920.file_list, app.TiffInfo1030.file_list, out, app.CurrentShiftX, app.CurrentShiftY);
        end
        
        function OnBatchScan(app, ~)
            p=uigetdir;
            if p
                app.OnBatchClear();
                d=dir(p); n={d([d.isdir]).name};
                n=n(~ismember(n,{'.','..'}));
                for i=1:length(n)
                    f=fullfile(p,n{i});
                    paths=app.check_struct(f);
                    if ~isempty(paths.p1)
                        T.Name = n{i};
                        T.Folder = f; T.Paths920 = paths.p1; T.Paths1030 = paths.p2; 
                        app.BatchTasks(end+1)=T;
                    end
                end
                app.ListBatch.Items={app.BatchTasks.Name};
                if ~isempty(app.BatchTasks), app.BtnBatchRun.Enable='on'; app.BtnBatchPreview.Enable='on'; end
            end
        end
        function OnBatchClear(app, ~), app.BatchTasks=[];
            app.ListBatch.Items={}; app.BtnBatchRun.Enable='off'; app.BtnBatchPreview.Enable='off'; end
        function OnBatchPrev(app, ~)
            v=app.ListBatch.Value;
            if isempty(v),return;end; if iscell(v),v=v{1};end
            idx=find(strcmp({app.BatchTasks.Name},v),1); T=app.BatchTasks(idx);
            app.run_preview_calc(T.Paths920, T.Paths1030);
        end
        function OnBatchRun(app, ~)
            n=length(app.BatchTasks);
            if n==0,return;end
            if ~strcmp(uiconfirm(app.UIFigure,['Run ' num2str(n) ' tasks?'],'Confirm Batch Run','Icon','question'),'OK'),return;end
            for i=1:n
                T=app.BatchTasks(i);
                out=fullfile(T.Folder,'Corrected_Results'); 
                if ~isfolder(out),mkdir(out);end
                app.process_export(T.Paths920, T.Paths1030, out, app.CurrentShiftX, app.CurrentShiftY);
            end
            uialert(app.UIFigure,'Batch processing complete.','Done');
        end
    end

    % =====================================================================
    % 4. UI建设
    % =====================================================================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible','off','Position',[50 50 1400 850],'Name','Microscope Tool v15.0 (Z-Drift + Rolling)');
            app.GridLayout = uigridlayout(app.UIFigure,[1 2]); app.GridLayout.ColumnWidth={320,'1x'};
            app.PlayTimer = timer('ExecutionMode','fixedRate','Period',0.1,'TimerFcn',@(~,~) app.on_timer());
            app.LeftPanel = uipanel(app.GridLayout); app.LeftPanel.BackgroundColor=[0.94 0.94 0.94];
            
            app.PanelToolbox = uipanel(app.LeftPanel, 'Title','0. 环境','Position',[10 730 300 70]);
            app.BtnLoadToolbox = uibutton(app.PanelToolbox, 'Text','挂载 NoRMCorre','Position',[10 10 160 30], 'ButtonPushedFcn', createCallbackFcn(app, @OnClickLoadToolbox, true));
            app.LblToolboxStatus = uilabel(app.PanelToolbox, 'Text','未加载', 'Position',[180 15 100 20]);
            
            app.PanelJson = uipanel(app.LeftPanel, 'Title','1. 畸变配置','Position',[10 600 300 120]);
            app.BtnJson920 = uibutton(app.PanelJson, 'Text','920 JSON','Position',[10 65 90 30],'ButtonPushedFcn', createCallbackFcn(app, @OnJson920, true));
            app.LblJson920 = uilabel(app.PanelJson, 'Text','...','Position',[110 65 180 30]);
            app.BtnJson1030 = uibutton(app.PanelJson, 'Text','1030 JSON','Position',[10 20 90 30],'ButtonPushedFcn', createCallbackFcn(app, @OnJson1030, true));
            app.LblJson1030 = uilabel(app.PanelJson, 'Text','...','Position',[110 20 180 30]);
            
            app.PanelPre = uipanel(app.LeftPanel, 'Title','2. 预处理 (去抖动 & Z平滑)','Position',[10 400 300 190]);
            
            % Row 1: Motion Correction & Method
            app.ChkMotion = uicheckbox(app.PanelPre, 'Text','XY 运动校正', 'Position',[10 145 100 20], 'Enable','off');
            app.LblMethod = uilabel(app.PanelPre, 'Text','模式:', 'Position',[130 145 40 20]);
            app.DropDownMethod = uidropdown(app.PanelPre, 'Items',{'刚性 (Rigid)', '非刚性 (Non-rigid)'}, 'Position',[170 145 120 20]);
            
            % Row 2: Z-Drift Rolling Template (New)
            app.ChkRolling = uicheckbox(app.PanelPre, 'Text','Z轴跟随 (动态模板)', 'Position',[10 115 150 20], 'Value', false, 'Tooltip', '参考模板会随时间更新，防止深层漂移无法配准');
            
            % Row 3: Master Channel
            app.LblMaster = uilabel(app.PanelPre, 'Text','主参考:', 'Position',[10 85 50 20]);
            app.DropDownMaster = uidropdown(app.PanelPre, 'Items',{'Green (920)', 'Red (1030)'}, 'Value', 'Red (1030)', 'Position',[70 85 100 20]);
            
            % Row 4: Grid & MaxShift
            app.LblGrid = uilabel(app.PanelPre, 'Text','网格:', 'Position',[180 85 40 20]);
            app.EditGrid = uieditfield(app.PanelPre, 'numeric', 'Position',[220 85 30 20], 'Value', 64);
            app.LblMaxShift = uilabel(app.PanelPre, 'Text','最大位移:', 'Position',[180 55 60 20]);
            app.EditMaxShift = uieditfield(app.PanelPre, 'numeric', 'Position',[240 55 30 20], 'Value', 30);

            % Row 5: Z-Smoothing (New)
            app.ChkZSmooth = uicheckbox(app.PanelPre, 'Text','Z轴滑动窗平滑', 'Position',[10 20 110 20], 'Value', false);
            app.LblZWin = uilabel(app.PanelPre, 'Text','Win:', 'Position',[130 20 30 20]);
            app.EditZWin = uieditfield(app.PanelPre, 'numeric', 'Position',[160 20 30 20], 'Value', 5, 'Limits', [1 50]);

            app.TabGroup = uitabgroup(app.LeftPanel, 'Position',[10 140 300 250]);
            app.TabSingle = uitab(app.TabGroup, 'Title','单次');
            uibutton(app.TabSingle, 'Text','选择文件夹','Position',[15 170 260 40], 'FontWeight','bold', 'ButtonPushedFcn', createCallbackFcn(app, @OnSingleSelect, true));
            app.LblFolder = uilabel(app.TabSingle, 'Text','-','Position',[15 140 260 20]);
            app.BtnPreview = uibutton(app.TabSingle, 'Text','预览 (前20帧)', 'Position',[15 90 260 40], 'Enable','off', 'BackgroundColor',[0.6 0.8 1], 'ButtonPushedFcn', createCallbackFcn(app, @OnSingleLoad, true));
            app.BtnExport = uibutton(app.TabSingle, 'Text','全量导出', 'Position',[15 30 260 40], 'Enable','off', 'BackgroundColor',[0.6 1 0.6], 'ButtonPushedFcn', createCallbackFcn(app, @OnSingleExport, true));
            
            app.TabBatch = uitab(app.TabGroup, 'Title','批量');
            uibutton(app.TabBatch, 'Text','扫描','Position',[10 180 100 30], 'ButtonPushedFcn', createCallbackFcn(app, @OnBatchScan, true));
            uibutton(app.TabBatch, 'Text','清空','Position',[120 180 60 30], 'ButtonPushedFcn', createCallbackFcn(app, @OnBatchClear, true));
            app.ListBatch = uilistbox(app.TabBatch, 'Position',[10 80 270 90]);
            app.BtnBatchPreview = uibutton(app.TabBatch, 'Text','预览', 'Position',[10 30 100 30], 'Enable','off', 'ButtonPushedFcn', createCallbackFcn(app, @OnBatchPrev, true));
            app.BtnBatchRun = uibutton(app.TabBatch, 'Text','批量', 'Position',[120 30 150 30], 'Enable','off', 'FontWeight','bold', 'BackgroundColor',[1 0.8 0.8], 'ButtonPushedFcn', createCallbackFcn(app, @OnBatchRun, true));
            
            app.TxtLog = uitextarea(app.LeftPanel, 'Position',[10 10 300 120], 'Editable','off','FontSize',10);
            app.LblAuthor = uilabel(app.LeftPanel, 'Position',[10 130 280 20], 'Text','Author: yangbingyi v15.0','HorizontalAlignment','right');
            
            app.RightPanel = uipanel(app.GridLayout); app.RightPanel.Layout.Column=2; app.RightPanel.Title='预览 (Preview)'; app.RightPanel.BackgroundColor=[0.1 0.1 0.1]; app.RightPanel.ForegroundColor='w';
            app.AxMerged = uiaxes(app.RightPanel, 'Position',[20 230 1000 510], 'BackgroundColor','k', 'XTick',[], 'YTick',[]);
            app.PanelTopCtrl = uipanel(app.RightPanel, 'Position',[20 750 1000 40], 'BackgroundColor',[0.2 0.2 0.2], 'BorderType','none');
            app.SwitchViewMode = uiswitch(app.RightPanel, 'slider', 'Items', {'原始(Raw)', '校正(Corrected)'}, 'Position', [120 750 100 30], 'Value', '校正(Corrected)', 'ValueChangedFcn', @(s,e) app.update_display_frame());
            app.LblViewMode = uilabel(app.RightPanel, 'Text', '对比模式:', 'Position', [40 750 80 30], 'FontColor','w', 'FontWeight','bold');
            app.PanelPlayer = uipanel(app.RightPanel, 'Position',[20 180 1000 40], 'BackgroundColor', [0.2 0.2 0.2], 'BorderType','none');
            app.BtnPlay = uibutton(app.PanelPlayer, 'Text','▶', 'Position',[10 5 40 30], 'Enable','off', 'ButtonPushedFcn', @(s,e) app.OnPlay());
            app.SliderFrame = uislider(app.PanelPlayer, 'Position',[70 15 800 3], 'Limits',[1 50], 'Enable','off', 'ValueChangedFcn', @(s,e) app.OnSliderFrame());
            app.LblFrameInfo = uilabel(app.PanelPlayer, 'Text', 'Frame: 0/0', 'Position', [900 10 100 20], 'FontColor','w');
            app.PanelTuning = uipanel(app.RightPanel, 'Position',[20 10 1000 160], 'Title','图像控制', 'BackgroundColor',[0.9 0.9 0.9]);
            app.BtnGroupView = uibuttongroup(app.PanelTuning,'Position',[20 20 200 110],'Title','通道','SelectionChangedFcn',@(s,e) update_display_frame(app));
            app.RadMerge = uiradiobutton(app.BtnGroupView,'Text','融合','Position',[10 65 100 20],'Value',true,'Enable','off');
            app.RadGreen = uiradiobutton(app.BtnGroupView,'Text','Green','Position',[10 40 100 20],'Enable','off');
            app.RadRed = uiradiobutton(app.BtnGroupView,'Text','Red','Position',[10 15 100 20],'Enable','off');
            
            x=350;
            app.BtnLeft=uibutton(app.PanelTuning,'Text','◀','Position',[x 95 30 30],'Enable','off','ButtonPushedFcn',@(s,e) OnNudge(app,'x',-1));
            app.SliderX=uislider(app.PanelTuning,'Position',[x+40 104 300 3],'Limits',[-100 100],'Value',-3,'Enable','off','ValueChangedFcn',createCallbackFcn(app,@OnSlider,true));
            app.BtnRight=uibutton(app.PanelTuning,'Text','▶','Position',[x+350 95 30 30],'Enable','off','ButtonPushedFcn',@(s,e) OnNudge(app,'x',1));
            app.BtnUp=uibutton(app.PanelTuning,'Text','▲','Position',[x 35 30 30],'Enable','off','ButtonPushedFcn',@(s,e) OnNudge(app,'y',-1));
            app.SliderY=uislider(app.PanelTuning,'Position',[x+40 44 300 3],'Limits',[-100 100],'Value',-32,'Enable','off','ValueChangedFcn',createCallbackFcn(app,@OnSlider,true));
            app.BtnDown=uibutton(app.PanelTuning,'Text','▼','Position',[x+350 35 30 30],'Enable','off','ButtonPushedFcn',@(s,e) OnNudge(app,'y',1));
            app.LblShiftInfo=uilabel(app.PanelTuning,'Text','X: -3 | Y: -32','Position',[x+400 70 150 30],'FontSize',16,'FontWeight','bold','FontColor','b');
            app.BtnContrast=uibutton(app.PanelTuning,'state','Text','增强对比度','Position',[x+400 30 120 30],'Enable','off','ValueChangedFcn',@(s,e) update_display_frame(app));
            
            app.UIFigure.Visible='on';
        end
    end
    
    % =====================================================================
    % 5. App 构造与析构
    % =====================================================================
    methods (Access = public)
        function app = Microscope_Registration_new
            createComponents(app);
            registerApp(app, app.UIFigure);
            app.log('系统就绪 (v15.0 Rolling+ZSmooth)');
            if ~isdeployed
                app.check_normcorre();
            end
        end
        function delete(app)
            delete(app.PlayTimer);
            delete(app.UIFigure);
        end
    end
end