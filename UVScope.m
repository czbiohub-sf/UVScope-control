% Author: Paul Lebel
% czbiohub
% 2018

classdef UVScope < handle
    
    %=========================================================================
    %   PRIVATE PROPERTIES
    %=========================================================================
    properties (Access = protected)
       
        % Multidimensional acquisition object
        MDA
        
        % GUI OBJECTS--------------------------------------------------
        % Main figure handle
        mainHandle
        
        MDParams = struct('positions_um',[],'presets',[], ...
            'timeVec_s',[], 'zStackVec_um',[], 'acquisitionOrder',[], ...
            'presetMap',[], 'channels',[], 'frameDims',[]);
        
        % Camera control GUI objects
        exposureEdit
        binningDropdown
        camInitText
        snapImageButton
        previewButton
        stopPreviewButton
        createAlbumButton
        accumulateFramesEdit
        
        % Misc GUI objects
        presetsDropdown
        previewAxes
        previewData
        errorMessageBox
        stagePosText
        quitButton
        reloadPresetsButton
        savePresetsButton
        autofocusNowButton
        subtractBGCheckbox
        calibrationsButton
        acqBGButton
        
        % LED control GUI objects
        LEDChoice
        powerSlider
        LEDList
        
        % MultiD GUI objects
        defineAreaButton
        addPositionButton
        removePositionButton
        clearListButton
        positionListTable
        selectedPositionListCell = [1 1];
        zStackRangeText
        zStackStepsizeText
        delayTimeText
        nTimesText
        presetListBoxMD
        acquisitionOrderDropdown
        acquireMDAButton
        timeSeriesButton
        stopMDAButton
        autoFocusPopup
        afChanDropdown
        
        % Manual album GUI objects
        album
        albumConfig
        
        % END GUI OBJECTS--------------------------------------------------
          
    end
    
    properties (Constant, Access = protected)
        % LEDList = {'M265L3','M285L4','M565F3','M285F3'};
        okColor = [173,255,47]/255;
        warningColor = [255,255,100]/255;
        errorColor = [255,99,71]/255;
        grayedOutColor = [.5 .5 .5];
        zStackMotionTol_mm = 0.001;
        autofocusRange_mm = 0.04;
        autofocusStep_mm = 0.002;
        
        GUITagList = {'subtractBGCheckbox','stopMDAButton','autofocusNowButton',...
            'exposureEdit', 'binningDropdown','accumulateFramesEdit',...
            'snapImageButton', 'previewButton','stopPreviewButton', 'calibrationsButton',...
            'createAlbumButton', 'presetsDropdown','LEDChoice','powerSlider',...
            'defineAreaButton','addPositionButton','removePositionButton','acqBGButton',...
            'clearListButton','quitButton','timeSeriesButton','afChanDropdown',...
            'zStackRangeText','zStackStepsizeText','presetListBoxMD',...
            'acquisitionOrderDropdown', 'delayTimeText','reloadPresetsButton' ...
            'savePresetsButton','nTimesText','acquireMDAButton','autoFocusPopup',...
            'camInitText','previewAxes','previewData','errorMessageBox',...
            'stagePosText','positionListTable'};
        
        % Which of these objects have callbacks
        callbackInds = 1:32;
    end
    
    properties (GetAccess = public, SetAccess = private)
        presetMap
        bgMap
        presetPath
        selectedPresetInd
        selectedPresetString
        percentLEDPower
        exposureTime_ms = 20;
        binningValue = 1;
        framesToAccum = 1;
        vidRes
        isPreviewing = false;
        previewPaused = false;
        activeLED
        positionList = []
        errorLog
        doSubtractBG = false;
        
        timeSeriesImages
        
        % MultiD parameters
        acquisitionOrder
        acqOrderChoices = {'ZCXYT', 'CZXYT','TCZXY','T'}
        useAutofocus = false
        useTrackfocus = false
        afChannel
        
        % MD Acquisition parameters
        zStackStep_um
        zStackRange_um
        zStackVec_um
        timeStep_s
        nTimeSteps
        mdImage
        ts_metadata
        MDAisRunning = false;
        baseMDFilepath = '\\Flexo\MicroscopyData\Bioengineering\UV Microscopy\RawData';


        % HARDWARE---------------------------------------------------------
        
        % Camera
        vid
        src
        labjack
        TTLDevices
        multiLED
        thorZ
        oasis
    end
    
    %=========================================================================
    %
    %   PUBLIC METHODS
    %
    %=========================================================================
    methods (Access = public)
        
        % Class Constructor
        function this = UVScope(presetPath, vid, src, thorCOM, LEDList)
            this.vid = vid;
            this.src = src;
            this.vidRes = circshift(this.vid.VideoResolution,1);
            this.vid.ROIPosition = [0 0 this.vidRes(2) this.vidRes(1)];
            this.LEDList = LEDList;
            this.presetPath = presetPath;
            this.loadPresets(false);
            
            % Initialize labjack
            try
                this.labjack = LJackUD('U6');
                this.labjack.initializeLabjack();
                this.TTLDevices = containers.Map({'exacte'},{'EIO3'});
                this.multiLED = MultiLED(this.labjack,this.LEDList,{'EIO1','EIO2','EIO0','DAC0'},this.TTLDevices);
            catch ME
                uvError.message = [ME.message ':Problem initializing labjack. Using simulator.'];
                this.errorHandler(uvError);
                this.labjack = LJackUD('U6');
                this.TTLDevices = containers.Map({'exacte'},{'EIO3'});
                this.TTLDevices = containers.Map({'exacte'},{'EIO3'});
                this.multiLED = MultiLED(true, [], [],[]);
            end
            
            % Initialize Z Stage
            try
                this.thorZ = MCM3000Controller(thorCOM, 4725);
            catch ME
                this.thorZ = MCM3000Controller('',4725,true);
                uvError.message = [ME.message ':Problem connecting to Thorlabs Z stage'];
                this.errorHandler(uvError, 'Error');
            end
            
            % Initialize thorlabs Z stage
            try
                this.thorZ.initializeStage();
                this.thorZ.home(1);
                this.thorZ.moveAbs_mm(1,this.thorZ.axisLimits_mm(1,2),false);
            catch ME
                h = msgbox('Thorlabs initialization failed. Using simulated stage.');
                uiwait(h);
                uvError.message = [ME.message ':Could not initialize Thorlabs Z stage'];
                this.errorHandler(uvError, 'Error');
            end
            
            % Initialize XY Stage
            try
                this.oasis = oasisControllerGui(false, false, '',[]);
                this.oasis.setup();
                h = msgbox('XY Stage will now initialize and home. Please ensure that nothing is in the way!','Warning!','warn');
                uiwait(h);
                this.oasis.initializeXy();
            catch
                h = msgbox('Oasis initialization failed. Using simulated stage.');
                uiwait(h);
                this.oasis = oasisControllerGui(true, false, '',[]);
            end
            
            % Initialize GUI objects
            this.createGUI();
            
            if isa(this.vid, 'videoinput')
                set(this.camInitText,'String','Camera initialized');
                set(this.camInitText,'BackgroundColor',this.okColor);
            else
                set(this.camInitText, 'String', 'Camera NOT initialized');
                set(this.camInitText, 'BackgroundColor',this.warningColor);
            end
            
            presets = keys(this.presetMap);
            
            tempCell = cell(numel(presets),1);
            % Initialize background images to zero
            for i=1:numel(presets)
                tempCell{i} = zeros(this.vidRes,'uint16');
            end
            this.bgMap = containers.Map(presets, tempCell);
            clear tempCell;                
            
            try
                this.changePreset('x265nm_BF');
            catch
                this.changePreset(presets{1});
            end
            this.updateGUI();
%             this.presetsDropdown_Callback();
            this.showGUI();
            disp('Ready');
        end
        
        function displayImages(this)
            if ~isempty(this.MDA)
                this.MDA.MDImage.loadImages();
                this.MDA.MDImage.displayImages();
            end
        end
        
        function showGUI(this)
            set(this.mainHandle, 'visible','on');
        end
        
        function setBaseMDPath(this, filepath) 
            this.baseMDFilepath = filepath;
        end

        
        function hideGUI(this)
            set(this.mainHandle,'visible','off');
        end
        
        function stopMDAButton_Callback(this,~,~)
           this.MDAisRunning = false; 
        end
        
                %*************************************************************
        % Sets the current X & Y stage position
        % xyPos = Vector with position in counts, not microns
        % wait = Optional argument
        %        0/false -> Do not wait for stage to reach the position
        %                   (default)
        %        1/true -> Wait for the stage to reach the position before
        %                  returning
        function status = setXY_um(this, xyPos, wait)                       
            status = this.oasis.moveToXy([xyPos(1) xyPos(2)], wait);
        end
        
        function [status, xy] = readXy(this)
            [status, xy] = this.oasis.readXy();
        end
        
        % Move the stage by a relative distance, in microns
        function status = setXY_um_rel(this,xyPosRel_um, wait)
            
            if nargin < 2
                xyPosRel_um = [0 0];
            end
            
            % Get current position
            [status, xyNow] = this.oasis.readXy();
            
            if status == 0
                % Add relative position to current position
                status = this.setXY_um(xyNow + xyPosRel_um, wait);
            end
        end
        
        function acquireMDAButton_Callback(this,~,~)
            
            % Stop previewing
            this.isPreviewing = false;
            drawnow();
            this.configTrig('triggered');
            
            % Get most up to date parameters
            this.positionList = get(this.positionListTable, 'Data');
            this.nTimesText_Callback();
            this.zStackRangeText_Callback();
            this.acquisitionOrderDropdown_Callback();
            
            % Create the raw data directory
            this.MDParams.filepath = ...
                [this.baseMDFilepath, '\UVM-', ...
                datestr(now,'yyyy-mm-dd-HH-MM-SS')];
            
            % Populate MDParams
            prefix = inputdlg('Please enter a filename prefix','Filename prefix');
            this.MDParams.filePrefix = prefix{1};
            this.MDParams.positions_um = this.positionList;
            this.MDParams.presetMap = this.presetMap;
            this.MDParams.frameDims = size(this.previewData.CData);
            strs = get(this.presetListBoxMD,'String');
            vals = get(this.presetListBoxMD,'Value');
            this.MDParams.channels = strs(vals);
            this.MDParams.acquisitionOrder = this.acquisitionOrder;
            this.MDParams.zStackVec_um = this.zStackVec_um;
            this.MDA = MDEngine(this.MDParams);
            this.runMDA();
        end
        
        function loadPresets(this, isNotInitial)
            
            if nargin < 2
                isNotInitial = true;
            end
            % Import preset configurations from a file
            fid = fopen(this.presetPath,'r');
            A = jsondecode(fread(fid, '*char'));
            fclose(fid);
            keys = fields(A);
            values = cell(numel(keys,1));
            for i=1:numel(keys)
                values{i} = A.(keys{i});
            end
            this.presetMap = containers.Map(keys,values);
            set(this.presetsDropdown, 'string', keys);
            set(this.presetsDropdown, 'value', 1);
            if isNotInitial
                this.updateGUI();
            end
        end
        
        function savePresetsButton_Callback(this,~,~)
            this.savePresets();
        end
        
        function savePresets(this)
            % Save the current presets to file
            answer = yesNoDialog('Would you like to overwrite the existing preset file?',...
                'Write presets file', 'No', true);
            if answer
                try
                fid = fopen(this.presetPath);
                fprintf(fid,jsonencode(this.presetMap));
                fclose(fid);
                catch
                    this.errorHandler('Could not write .json file.','Error')
                end
            end
        end
        
        % Implement realtime loop addressing the requests of the MDA
        function runMDA(this)
            run(this.MDA);
            this.MDAisRunning = true;
            channel = this.MDA.requestedChannel;
            this.changePreset(channel);
            lastPosition = [0 0 0];
            this.multiLED.setActiveLED(this.activeLED, this.percentLEDPower);
            pause(0.5);
            
            deltaZ_mm = 0;
            frameCount = 0;
            
            progBar = waitbar(0,'Acquiring MD acquisition...');
            
            while (ishandle(this.mainHandle) && (~strcmp(this.MDA.state,'Idle')))&&this.MDAisRunning
                state =  this.MDA.state;
                switch state
                    case 'FrameRequest'
                        
                        position_um = this.MDA.requestedPosition_um;
                        requestedZStackDelta_um = this.MDA.requestedZStackDelta_um;
                        if isempty(requestedZStackDelta_um)
                            requestedZStackDelta_um = 0;
                        end
                        
                        this.oasis.moveToXy([position_um(1) position_um(2)], true);
                        
                        % If the XY position changed and autofocus was
                        % checked, then use autofocus
                        if any(lastPosition(1:2) ~= position_um(1:2))
                            
                            % Update waitbar
                            if exist('progBar','var')
                                waitbar(frameCount/this.MDA.nImages, progBar,'Acquiring MD acquisition...');
                            end
                            
                            if this.useAutofocus
                                % Move to the expected new z-position, then
                                % autofocus
                                this.thorZ.moveAbs_mm(1, position_um(3)/1000 + deltaZ_mm, true, this.zStackMotionTol_mm);
                                this.autofocusNowButton_Callback();
                                newZCenter_mm = this.thorZ.getPos_mm(1);
                                deltaZ_mm = newZCenter_mm -  position_um(3)/1000;
                                this.thorZ.moveAbs_mm(1, position_um(3)/1000 + deltaZ_mm + requestedZStackDelta_um/1000, true, this.zStackMotionTol_mm);
                            
                            elseif this.useTrackfocus
                                % MDEngine takes care of tracking focus by
                                % computing an autofocus on the most recent
                                % z-stack and tracking the corrective
                                % offset over time. 
                                this.MDA.trackFocus();
                                this.thorZ.moveAbs_mm(1, position_um(3)/1000 + this.MDA.focusOffset_um/1000, true, this.zStackMotionTol_mm);
                            end
                        else
                            this.thorZ.moveAbs_mm(1, position_um(3)/1000 + requestedZStackDelta_um/1000 + deltaZ_mm, true, this.zStackMotionTol_mm);
                        end
                        
                        newChannel = this.MDA.requestedChannel;
                        if ~strcmp(newChannel, this.getCurrentChannel())
                            this.changePreset(newChannel);
                            pause(0.5); % Allows time for LED to switch. Need to investigate why this takes so long!
                        end
                        
                        image = this.snapImageButton_Callback();
                        lastPosition = position_um;
                        this.MDA.addNextImage(image);
                        frameCount = frameCount + 1;
                        
                    case 'Waiting'
                        stop(this.vid);
                        timesUp = this.MDA.checkElapsedTime();
                        if timesUp
                            this.MDA.changeState('FrameRequest');
                            start(this.vid);
                        else
                            pause(.1);
                            disp('Still waiting');
                        end
                        
                        if this.MDA.fInd > this.MDA.nImages
                            this.MDA.changeStage('Idle');
                        end
                        
                    case 'Idle'
                        pause(.1);
                    otherwise
                        if this.MDA.fInd > this.MDA.nImages
                            this.MDA.changeStage('Idle');
                        end
                end
                
            end
            
            this.MDAisRunning = true;   
            delete(progBar);
            msgbox('All done!', 'Acquisition completed');
            
        end
        
        function channel = getCurrentChannel(this)
            strings = get(this.presetsDropdown,'String');
            val = get(this.presetsDropdown,'Value');
            channel = strings{val};
        end
        
        function createGUI(this)
            
%             try
                this.mainHandle = open('UVScope.fig');
                set(this.mainHandle, 'visible','off');
                set(this.mainHandle,'CloseRequestFcn',@mainCloseRequest_Callback);
                
                % Populate GUI objects
                for i=1:numel(this.GUITagList)
                    this.(this.GUITagList{i}) = this.mainHandle.findobj('tag', this.GUITagList{i});
                end
                
                % Initialize specific GUI features
                set(this.powerSlider, 'Min',0);
                set(this.powerSlider, 'Max',100);
                set(this.errorMessageBox, 'String', 'No errors detected');
                set(this.errorMessageBox, 'BackgroundColor',[.5 1 0.5]);
                set(this.LEDChoice, 'Value', 1);

%             catch ME
%                 uvError.message = [ME.message ':Problem initializing GUI'];
%                 uvError.code = 'Error';
%                 this.errorHandler(uvError);
%                 errordlg('uvError');
%             end
            
            % Assign all the callbacks. This will have to be enumerated
            % manually if we ever want to compile this into an executable!
            for i=1:numel(this.callbackInds)
                eval(['set(this.' this.GUITagList{this.callbackInds(i)} ', ''Callback'', @this.' this.GUITagList{this.callbackInds(i)} '_Callback);']);
            end
            
            set(this.positionListTable, 'CellSelectionCallback', @this.pltCellSelection_Callback);
          
            % Configure the preview window axes
            this.previewAxes = this.mainHandle.findobj('tag','previewAxes');
            this.previewData = imagesc(this.previewAxes, zeros([600 800]));
            colormap(this.previewAxes, 'gray');
            set(this.previewAxes, 'XTick',[]);
            set(this.previewAxes, 'YTick',[]);
            set(this.previewAxes, 'XTickLabel',[]);
            set(this.previewAxes, 'YTickLabel',[]);
            axis(this.previewAxes, 'image');
            
            % Configure the position list
            this.positionList = [];
            this.positionListTable.Data = [];
            
            % Populate dropdown menus
            set(this.LEDChoice, 'String', this.multiLED.connectedLEDs);
            set(this.LEDChoice,'Value',1);
            set(this.presetsDropdown, 'Value',1);
            set(this.presetsDropdown,'String', keys(this.presetMap));
            set(this.afChanDropdown,'String', keys(this.presetMap));
            set(this.acquisitionOrderDropdown, 'String', this.acqOrderChoices);
            set(this.previewButton,'interruptible','on');
        end
        
        function mainCloseRequest_Callback(this,~,~)
            this.quitButton_Callback();
        end
        
        function afChanDropdown_Callback(this,~,~)
            strings = get(this.afChanDropdown, 'String');
            val = get(this.afChanDropdown,'Value');
            this.afChannel = strings{val};
        end
        
        function setExposureTime_ms(this, exposure_ms)
            % Convert to us, which is used by the src
            if contains(this.vid.Name, 'pcocamera')
                try
                    this.src.E2ExposureTime = exposure_ms*1000;
                catch
                end
            end
            
            if contains(this.vid.Name, 'winvideo')
                try
                    this.src.Exposure = exposure_ms;
                catch
                end
            end
            
            this.exposureTime_ms = exposure_ms;
            this.updateGUI();
        end
        
        function setBinning(this, bin)
          if contains(this.vid.Name, 'pcocamera')
            wasPreviewing = this.isPreviewing;
            wasRunning = isrunning(this.vid);
            if wasPreviewing
                this.previewPaused = true;
            end
            
            stop(this.vid);

            if ismember(bin,['1','2','4'])
                this.binningValue = bin;
                binStr = ['0' bin];
                this.src.B1BinningHorizontal = binStr;
                this.src.B2BinningVertical = binStr;
                this.vidRes = circshift(this.vid.VideoResolution,1);
                this.previewData = imagesc(this.previewAxes, zeros(this.vidRes));
                colormap(this.previewAxes, 'gray');
                set(this.previewAxes, 'XTick',[]);
                set(this.previewAxes, 'YTick',[]);
                set(this.previewAxes, 'XTickLabel',[]);
                set(this.previewAxes, 'YTickLabel',[]);
                axis(this.previewAxes, 'image');
            else
                warning('bin value must be 1,2,or 4');
            end        
            
            if wasPreviewing
                this.previewPaused = false;
                start(this.vid);
            elseif wasRunning
                start(this.vid);
            end
          end
            
            this.updateGUI();
        end
        
        function changePreset(this,choice)
            
            % Check if choice is valid
            strings = get(this.presetsDropdown,'String');
            logicalVec = strfind(strings,choice);
            ind = 0;
            for i=1:numel(logicalVec)
                if logicalVec{i}
                    ind = i;
                end
            end
            
            if ~ind
                error('"choice" is not a valid preset!');
            end
            
            this.selectedPresetInd = ind;
            this.selectedPresetString = choice;

            settings = this.presetMap(choice);
            
            % Change settings based upon the preset values
            this.percentLEDPower = settings.percentPower;
            this.setExposureTime_ms(settings.exposure_ms);
            
            % Note: this can't be changed while previewing.
            this.setBinning(settings.binning);
            this.activeLED = settings.LED;
            this.multiLED.setActiveLED(this.activeLED, this.percentLEDPower);
            
            this.updateGUI();
            
        end
        
        % GUI callback functions
        function exposureEdit_Callback(this,hObject,~)
            exposure = str2double(get(hObject,'String'));
            this.setExposureTime_ms(exposure);
            this.updateGUI();
        end
        
        function binningDropdown_Callback(this,hObject,~)
            ind = get(hObject,'Value');
            strings = get(hObject,'String');
            bin = strings{ind};
            
            this.setBinning(bin); % Calls updateGUI()
           
        end
        
        function presetsDropdown_Callback(this, ~, ~)
            ind = get(this.presetsDropdown,'Value');
            if ~isscalar(ind)
                ind = 1;
            end
            strings= get(this.presetsDropdown,'String');
            if ind>numel(strings)
                ind = 1;
            end
            choice = strings{ind};
            this.changePreset(choice); % Calls updateGUI
        end
        
        % Method: snapImageButton_Callback
        % This button snaps and returns an image from the scope camera with the current
        % microscope settings. If the preview is currently on, a frame from
        % the live stream will be returned. If the preview is not on, a
        % frame will be triggered and returned. By default, the camera
        % should be set to manual trigger when the preview is not running.
        
        % Regarding LED operation: if the LED was previously off before
        % this function call, the LED will be turned on with a pause
        % afterwards, and after the snap is complete it will be turned off.
        % If the LED was on already, then nothing is done and it remains
        % on. Hardware sync of the LED enables it to be left in the on
        % state without photobleaching or UV dosing the sample extensively.
        % 
        function frame = snapImageButton_Callback(this, ~, ~)

            if ~isempty(this.album)
                this.album.snapAlbum_Callback()
            else
                frame = this.snapImage();
            end
        end
        
        function frame = snapImage(this)
            if this.multiLED.activeLEDPercent == 0
                this.multiLED.setActiveLED(this.activeLED, this.percentLEDPower);
                % LED is slow to turn on. Need to investigate this.
                pause(.5);
                wasOff = true;
            else
                wasOff = false;
            end
            
            if this.isPreviewing
                while this.vid.FramesAvailable < 1
                    pause(.001);
                end
%                 frame = rot90(peekdata(this.vid,1),2);
                frame = this.previewData.CData;
            else
                flushdata(this.vid);
                if ~isrunning(this.vid)
                    start(this.vid);
                end
                trigger(this.vid);
                while this.vid.FramesAcquired < this.framesToAccum
                    pause(.001);
                end                
                frame = uint16(mean(rot90(getdata(this.vid,this.framesToAccum),2),3));
                this.previewData.CData = mean(squeeze(frame),3);
%                                 stop(this.vid);
            end
            
            if this.doSubtractBG
                dims = size(frame);
                frame = frame - imresize(uint16(this.bgMap(this.selectedPresetString)), dims);
            end
            
            % Turn LED off after
            if wasOff
                this.multiLED.setActiveLED(this.activeLED, 0);
            end
        end
        
        function stdVec = autofocusNowButton_Callback(this,~,~)
            if this.isPreviewing
                wasPreviewing = true;
            else
                wasPreviewing = false;
            end
            
            currentChannel = this.getCurrentChannel;
            
            if ~isempty(this.afChannel)
                this.changePreset(this.afChannel);
            end
            this.stopPreviewButton_Callback();
            zNow = this.thorZ.getPos_mm(1);
            zVec = (zNow-this.autofocusRange_mm/2):(this.autofocusStep_mm):(zNow+this.autofocusRange_mm/2);
            stdVec = zeros(numel(zVec),1);
            if ~isrunning(this.vid)
                start(this.vid);
            end
            for i=1:numel(zVec)
                this.thorZ.moveAbs_mm(1,zVec(i), true, 0.001);
                trigger(this.vid);
                frame = getdata(this.vid,1);
                [~,~,gradX,gradY] = edge(frame, 'Sobel');
                this.previewData.CData = frame;
                stdVec(i) = sum(sum(gradX.^2 + gradY.^2))/(mean(double(frame(:))));
                drawnow();
            end
            
            maxInd = find(stdVec == max(stdVec),1);
         
%             pFit = polyfit(-2:2,stdVec((maxInd-2):(maxInd+2))',2);
%             maxInd = maxInd - pFit(2)/(2*pFit(1));
            fig = figure;
            plot(stdVec); hold all;
            plot(maxInd, stdVec(round(maxInd)),'Xr'); drawnow(); pause(1); delete(fig);
            
            % Move to optimal position
            this.thorZ.moveAbs_mm(1,zVec(1), true, 0.002);
            this.thorZ.moveAbs_mm(1,interp1(1:numel(zVec),zVec,maxInd),true,.001);
            stop(this.vid);
            
            this.changePreset(currentChannel);
            
            if wasPreviewing
                this.previewButton_Callback();
            end
                
        end
        
        function clearAlbum(this)
            this.album = [];
        end
        
        function previewButton_Callback(this, ~, ~)
            
            this.configTrig('preview');
            this.isPreviewing = true;
            set(this.previewButton, 'BackgroundColor',[0 1 0]);
            start(this.vid);
            
            if this.doSubtractBG
                bgFrame =  double(this.bgMap(this.selectedPresetString));
            else
                bgFrame = ones(this.vidRes,'double');
            end
                        
            while(this.isPreviewing)
                if ~this.previewPaused
                    flushdata(this.vid);
                    fa = 0;
                    while(fa < this.framesToAccum)&&(this.isPreviewing)&&isrunning(this.vid)
                        fa = this.vid.FramesAvailable;
                        pause(0.001);
                    end
                    try
                        
                        this.previewData.CData = rot90(mean(squeeze(double(peekdata(this.vid,this.framesToAccum))),3),2) - bgFrame;
                    catch
                    end
                    drawnow();
                end
            end
        end
        
        function LEDChoice_Callback(this, hObject, ~)
            choices = get(hObject, 'String');
            ind = get(hObject, 'Value');
            choice = choices{ind};
            this.percentLEDPower = get(this.powerSlider, 'Value');
            this.activeLED = choice;
            this.updateGUI();
        end
        
        function pltCellSelection_Callback(this, ~, event)
           this.selectedPositionListCell = event.Indices;
        end
        
        function powerSlider_Callback(this, ~, ~)
            choices = get(this.LEDChoice, 'String');
                ind = get(this.LEDChoice, 'Value');
                choice = choices{ind};
                this.percentLEDPower = get(this.powerSlider, 'Value');
            try
                this.multiLED.setActiveLED(choice, this.percentLEDPower);
            catch ME
                uvError.message = [ME.message ':Problem changing LED power'];
                this.errorHandler(uvError, 'Error');
            end
            this.updateGUI();
        end
        
        function createAlbumButton_Callback(this,~,~)
            
            % Create the GUI to grab the album settings
            myAlbumConfig = AlbumConfigGUI(this.presetMap);
            
            % Wait here for user to return from configuring the album
            albumChannels = myAlbumConfig.getAlbumSettings();
            
            delete(myAlbumConfig.mainHandle);
            
            if ~isempty(albumChannels)
    
                % Build the GUI once user confirms settings
                this.album = AlbumGUI(this, albumChannels);
            end
            
        end
        
        function defineAreaButton_Callback(this,~,~)
                        
            h = msgbox('Please go to the UPPER LEFT corner, then click ok');
            uiwait(h);
            z1 = this.thorZ.getPos_mm(1);
            [~, xy1] = this.oasis.readXy();
            
            h = msgbox('Please go to the LOWER RIGHT corner, then click ok');
            uiwait(h);
            z2 = this.thorZ.getPos_mm(1);
            [~, xy2] = this.oasis.readXy();
            
            xy3(1) = xy2(1);
            xy3(2) = xy1(2);
            this.oasis.moveToXy(xy3, true);
            h = msgbox('Please focus on the UPPER RIGHT corner, then click ok');
            uiwait(h);
            
            z3 = this.thorZ.getPos_mm(1);
            
%             [~, xy3] = this.oasis.readXy();
            
            tileStr = inputdlg('How many tiles? Enter a two-element vector in the format [nx, ny]');
            res = str2num(tileStr{1}); %#ok<ST2NM>
            
            xVec = linspace(xy1(1), xy2(1), res(1));
            yVec = linspace(xy1(2), xy2(2), res(2));
            [X,Y] = meshgrid(xVec,yVec);
            xSlope = (z3-z1)/(xy3(1)-xy1(1));
            ySlope = (z2-z3)/(xy2(2)-xy3(2));
            Z = z1 + xSlope*(X-xy1(1)) + ySlope*(Y-xy1(2));
            
            this.clearListButton_Callback();
            
            for i=1:numel(X)
                this.positionList(i,:) = [X(i),Y(i),Z(i)*1000];
            end
            
            set(this.positionListTable,'Data',this.positionList);
            
            this.updateGUI();
        end
        
        function addPositionButton_Callback(this,~,~)
            [status, xy] = this.oasis.readXy();
            z_mm = this.thorZ.getPos_mm(1);
            
            if status == 0
                posEntry = [xy(1), xy(2), z_mm*1000];
                this.positionList(end+1,:) = posEntry;
                set(this.positionListTable,'Data',this.positionList);
            else
                warning('Oasis status fault');
            end
            this.updateGUI();
        end
        
        function removePositionButton_Callback(this,~,~)
            if numel(this.positionList) > 0
                answer = yesNoDialog('Are you sure want to clear this position from the list?','Clear position list','No');
                if answer
                    selection = this.selectedPositionListCell;
                    if numel(selection) > 0
                        this.positionList(selection(1),:) = [];
                        set(this.positionListTable,'Data',this.positionList);
                    end
                end
            end
            this.updateGUI();
        end
        
        function clearListButton_Callback(this,~,~)
            answer = yesNoDialog('Are you sure want to clear the position list?','Clear position list','No');
            if answer
                this.positionList = [];
                set(this.positionListTable,'Data',[]);
            end
            this.updateGUI();
        end
        
        function positionListTable_Callback(this,~,~)
            this.positionList = get(this.positionListTable, 'Data');
            this.updateGUI();
        end
        
        function zStackRangeText_Callback(this,~,~)
            str = get(this.zStackRangeText,'String');
            range = str2double(str);
            str = get(this.zStackStepsizeText, 'String');
            step = str2double(str);
            this.zStackRange_um = range;
            this.zStackStep_um = step;
            this.zStackVec_um = linspace(-range/2, range/2, 1 + range/step);
            if numel(this.zStackVec_um) == 0
                this.zStackVec_um = 0;
            end
            this.MDParams.zStackVec_um = this.zStackVec_um;
            this.updateGUI();
        end
        
        function autoFocusPopup_Callback(this,~,~)
            this.useAutofocus = strcmp(get(this.autoFocusCheckbox,'String'), 'AutoFocus');
            this.useTrackfocus = strcmp(get(this.autoFocusCheckbox,'String'), 'AutoFocus');
        end
        
        function zStackStepsizeText_Callback(this,~,~)
            str = get(this.zStackRangeText,'String');
            range = str2double(str);
            str = get(this.zStackStepsizeText, 'String');
            step = str2double(str);
            this.zStackRange_um = range;
            this.zStackStep_um = step;
            this.zStackVec_um = linspace(-range/2, range/2, 1 + range/step);
            if numel(this.zStackVec_um) == 0
                this.zStackVec_um = 0;
            end
            this.MDParams.zStackVec_um = this.zStackVec_um;
            this.updateGUI();
        end
        
        function presetListBoxMD_Callback(this,~,~)
            strs = get(this.presetListBoxMD,'String');
            vals = get(this.presetListBoxMD,'Value');
            this.MDParams.channels = strs(vals);
        end
        
        function acquisitionOrderDropdown_Callback(this,~,~)
            val = get(this.acquisitionOrderDropdown, 'Value');
            strs = get(this.acquisitionOrderDropdown, 'String');
            this.acquisitionOrder = strs{val};
        end
        
        function nTimesText_Callback(this,~,~)
            str = get(this.delayTimeText, 'String');
            this.timeStep_s = str2double(str);
            str = get(this.nTimesText,'String');
            this.nTimeSteps = str2double(str);
            this.MDParams.timeVec_s = this.timeStep_s*(1:1:this.nTimeSteps);
        end
        
        function delayTimeText_Callback(this,~,~)
            str = get(this.delayTimeText, 'String');
            this.timeStep_s = str2double(str);
            str = get(this.nTimesText,'String');
            this.nTimeSteps = str2double(str);
            this.MDParams.timeVec_s = this.timeStep_s*(1:1:this.nTimeSteps);
        end
        
        function acqBGButton_Callback(this,~,~)
            answer = inputdlg('Please enter the number background frames to average:','Specify background frames');
            nBGFrames = str2double(answer{1});
            this.configTrig('preview');
            this.vid.FramesPerTrigger = nBGFrames;
            
            h = msgbox('Please navigate to a blank region of the sample, then hit ''ok'' to start.');
            uiwait(h);
            
            wb = waitbar(0,'Acquiring background images...');
            start(this.vid);
            while(this.vid.FramesAcquired < nBGFrames)
                pause(.1);
                waitbar(this.vid.FramesAcquired/nBGFrames, wb,'Acquiring background images...');
            end
            delete(wb);
            % Get the data
            images = rot90(getdata(this.vid,nBGFrames),2);
            bgFrame = mean(squeeze(double(images)),3);
            
            % Update the bg image for the current preset
            this.bgMap(this.selectedPresetString) = bgFrame;
            
            this.previewData.CData = bgFrame;
        end
        
        function subtractBGCheckbox_Callback(this,~,~)
            this.doSubtractBG = get(this.subtractBGCheckbox, 'Value');
        end
        
        function reloadPresetsButton_Callback(this, ~, ~)
            [filename, pathname] = uigetfile('*.json');
            this.presetPath = fullfile(pathname, filename);
            this.loadPresets();
            this.presetsDropdown_Callback();
            this.updateGUI();
        end
        
        % Executes a timeseries acquisition with no other MD Params - only
        % one XYZ position, one channel
        function timeSeriesButton_Callback(this,~,~)
           this.stopPreviewButton_Callback();
           this.configTrig();
           this.timeSeriesImages = [];
           nFrames = str2double(get(this.nTimesText,'string'));
           delayTime = str2double(get(this.delayTimeText,'string'));
           this.vid.FramesPerTrigger = 1;
           this.vid.TriggerRepeat = nFrames;
           frames = uint16(zeros(size(this.previewData.CData,1), size(this.previewData.CData,2), nFrames));
                      
           chs = keys(this.presetMap);
           channelNumber = get(this.presetsDropdown,'Value');
           this.MDParams.channels =  {chs(channelNumber)};
           this.MDParams.presetMap = this.presetMap;
           this.MDParams.acquisitionOrder = 'T';
           this.MDParams.frameDims = [size(frames,1), size(frames,2)];
          
           % Create the raw data directory
           this.MDParams.filepath = ...
               [this.baseMDFilepath, '\UVM-', ...
               datestr(now,'yyyy-mm-dd-HH-MM-SS')];
           
           % Populate MDParams
           prefix = inputdlg('Please enter a filename prefix','Filename prefix');
            this.MDParams.filePrefix = prefix{1};
            
           % Get current position
           [~, xy] = this.oasis.readXy();
           z_mm = this.thorZ.getPos_mm(1);
           md.position = [xy(1), xy(2), z_mm*1000];
           this.MDParams.positions_um = [xy(1), xy(2), z_mm*1000];
           md.sliceNumber = 1;
           md.slice_um = 0;
           md.timeNumber = 1;
           md.time_s = 0;
           this.mdImage = MDImage(this.MDParams.frameDims,this.MDParams,this.presetMap);
           this.mdImage.setFilePath(this.MDParams.filepath,this.MDParams.filePrefix)
           % Initialize the metadata struct array. This array's slice
           % number and timestamp will be updated in the callback for
           % incoming frames.
%            md = this.presetMap(this.MDParams.channels{1});
%            md.channelNumber = channelNumber;
%            md.channel = chs(channelNumber);
%            md.positionNumber = 1;            

           
           start(this.vid);
            h = waitbar(0,'Setting up acquisition...');
           % This while loop runs until the acquisition is done. The
           % callback runs on demand in the background handling the
           % incoming frames
           count = 0;
           while(this.vid.FramesAcquired < nFrames)
               pause(max(0.01, delayTime));
               trigger(this.vid);
               waitbar(this.vid.FramesAcquired/nFrames,h,'Acquiring frames...');
               while this.vid.FramesAvailable < 1
                   pause(.001)
               end
               try
                   frame = getdata(this.vid, 1);
                   count = count +1;
                   %                        frame = double(rot90(squeeze(peekdata(this.vid,1)),2));
               catch
                   frame = zeros(this.MDParams.frameDims,'uint16');
               end
               
               if this.doSubtractBG && ~isempty(frame)
                   frame = frame - this.bgMap(this.selectedPresetString);
               end
               this.previewData.CData = rot90(squeeze(frame),2);
               md.timeNumber = count;
               this.mdImage.inputImages(frame, md, false, 'tiff');
           end
           delete(h);
    
%            save(fullfile(this.MDParams.filepath,[this.MDParams.filePrefix '_MDImage.mat']),'tempImage');
           this.configTrig();
        end
        
        % Callback function for the timeseries acquisition
        function timeSeriesFramesAcq(this,~,~)
            fa = this.vid.FramesAcquired;
            nFrames = this.vid.FramesAcquiredFcnCount;
            inds = (fa-nFrames+1):fa;
            [frames, acqTime] = getdata(this.vid,nFrames);
            for i=1:nFrames
                this.ts_metadata(inds(i)).time_s = acqTime(i);
                this.ts_metadata(inds(i)).timeNumber = inds(i);
            end
            this.previewData.CData = frames(:,:,end);
            this.mdImage.inputImages(frames, this.ts_metadata(inds), true, '');
        end
        
        % Set the vid object up for triggered acquisition
        function configTrig(this, mode)
            if nargin < 2
                mode = 'triggered';
            end
            
            stop(this.vid);
            flushdata(this.vid);
            
            switch mode
                case 'triggered'
                    triggerconfig(this.vid,'manual');
                    this.vid.FramesPerTrigger = this.framesToAccum;
                    this.vid.TriggerRepeat = inf;
                    this.vid.TriggerFrameDelay = 0;
                    stop(this.vid);
                case 'preview'
                    triggerconfig(this.vid,'immediate');
                    this.vid.FramesPerTrigger = inf;
                    this.vid.TriggerRepeat = 0;
            end
        end
        
        function accumulateFramesEdit_Callback(this,~,~)
           try
               this.framesToAccum =  str2double(get(this.accumulateFramesEdit,'String'));
           catch
           end
        end
        
        % Update the GUI with latest parameters
        function updateGUI(this)
            
            % Update camera status
            if isvalid(this.vid)
                set(this.camInitText,'String','Camera initialized');
                set(this.camInitText,'BackgroundColor',this.okColor);
            else
                set(this.camInitText,'String','Camera NOT initialized');            
                set(this.camInitText,'BackgroundColor',this.errorColor);
            end
            
            % Update the position list
            set(this.positionListTable,'Data',this.positionList);
            
            % Update the exposure time field
            set(this.exposureEdit, 'String', num2str(this.exposureTime_ms));
            
            % Update LEDChoice
            ind = find(strcmp(this.multiLED.connectedLEDs, this.activeLED));
            
            if ~isscalar(ind)
                ind = 1;
            end
            
            set(this.LEDChoice, 'Value', ind);
            
            % Update presets list strings
            set(this.presetsDropdown, 'String', keys(this.presetMap));
            set(this.afChanDropdown, 'String', keys(this.presetMap));
            set(this.presetListBoxMD, 'String', keys(this.presetMap));
            set(this.presetsDropdown, 'Value', this.selectedPresetInd);
            afChanInd = find(strcmp(keys(this.presetMap), this.afChannel));
            if isscalar(afChanInd)&&isfinite(afChanInd)
                set(this.afChanDropdown, 'Value', afChanInd);
            else
                set(this.afChanDropdown,'Value',1);
            end
            
            % Update frames to accumulate
             set(this.accumulateFramesEdit, 'String',num2str(this.framesToAccum));
            
            % Update power slider bar
            set(this.powerSlider, 'Value',this.percentLEDPower);
            
            % Update the exposure text edit field
            set(this.exposureEdit,'String',num2str(this.exposureTime_ms));
            
            % Update the binning dropdown
            switch this.binningValue
                case '1'
                    set(this.binningDropdown, 'Value',1);
                case '2'
                    set(this.binningDropdown, 'Value',2);
                case '4'
                    set(this.binningDropdown, 'Value',3);
            end
            
            % Refresh zStack fields
            set(this.zStackRangeText,'String', num2str(this.zStackRange_um));
            set(this.zStackStepsizeText, 'String', num2str(this.zStackStep_um));
            
            % Refresh time-lapse fields
            set(this.delayTimeText, 'String', num2str(this.timeStep_s));
            set(this.nTimesText,'String', num2str(this.nTimeSteps));
        end
        
        function quitButton_Callback(this,~,~)
            answer = yesNoDialog('Are you sure you want to quit?','Quit UV Scope','No',true);
            if answer
                this.delete();
            end
        end
        
        function delete(this)
            try
                delete(this.thorZ);
            catch  
            end
            
            try
                delete(this.vid);
            catch
            end
            
            try
                this.multiLED.setActiveLED('NONE',0);
                delete(this.labjack);
            catch
            end
            
            try
                quit(this.oasis);
            catch
            end
            
            try
                delete(this.album);
                delete(this.mainHandle);
            catch
            end

            this.mainHandle = -1;
        end
        
        function stopPreviewButton_Callback(this, ~, ~)
            this.isPreviewing = 0;
%             stop(this.vid);
            pause(.1);
            this.configTrig('triggered');
            set(this.previewButton, 'BackgroundColor',this.grayedOutColor);
        end
        
        function errorHandler(this, uvError)
            
            if isempty(this.errorLog)
                this.errorLog = uvError;
            else
                this.errorLog(end+1) = uvError;
            end
            
            if any(strcmp({this.errorLog.code},'Error'))
                    set(this.errorMessageBox, 'String', ['Error! ', this.errorLog]);
                    set(this.errorMessageBox, 'BackgroundColor',this.errorColor);
            elseif any(strcmp({this.errorLog.code},'Warning'))
                    set(this.errorMessageBox, 'String', ['Warning! ', this.errorLog]);
                    set(this.errorMessageBox, 'BackgroundColor',this.warningColor);
            else                    
                    set(this.errorMessageBox, 'String', 'No errors detected');
                    set(this.errorMessageBox, 'BackgroundColor',this.okColor);
            end
            
        end
        
    end
    
end
