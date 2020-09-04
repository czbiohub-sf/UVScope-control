
classdef AlbumGUI < handle
    % This is a GUI class that collects snapped images in a album according
    % to a certain number of preset channel configurations. The album
    % images are displayed in a figure axes with a slider bar for the user
    % to scroll back and forth to view the images
    
    % In the first version, we'll have only one channel order - as in,
    % channels are always acquired sequentially before changing fields of
    % view. After the album acquisition is complete, the data can be saved
    % in a flat .tiff format with a single .JSON metadata file.
    
    % Input arguments
    % settings: a struct containing the following fields:
    %       - nChannels (integer)
    %       - selectedChannels (cell array of strings)
    
    
    properties(Access = public)
        
        parent
        
        % Channel info
        nChannels
        channels
        acqParams
        
        % GUI handles
        parentHandle
        clearAlbumButton
        saveAlbumButton
        albumSliceSlider
        albumSavedIndicator
        snapAlbum
        albumAxes
        currentAlbumSliceText
        nAlbumSlicesText
        channelText
        nextChannelText
        retakeImageButton
        
        albumPreviewData
        albumData
        albumSavedFlag
        nAlbumSlices
        currentAlbumSlice
        albumNull
        metadata
%         metadataFields % These are the fields that are added on top of the existing fields in the preset map
        presetMap
        
        vid
        src
        vidRes
        
        % Weird artifacts from GUIDE. There's objects called Untitled_1
        % and text2 in the .fig file that I can't seem to get rid of or
        % find. 
        Untitled_1
        text2
        
    end
    
    methods(Access = public)
        
        function this = AlbumGUI(parent,channels)
            this.parent = parent;
            this.presetMap = parent.presetMap;
            this.channels = channels;
            this.nChannels = numel(this.channels);
            this.nAlbumSlices = 0;
            this.currentAlbumSlice = 0;
            this.albumNull = true;
%             this.metadataFields = {'name','binning','LED','FieldOfView','Camera'};
            
            if nargin > 1
                this.vid = parent.vid;
                this.src = getselectedsource(parent.vid);
                roi = this.vid.ROIPosition;
                this.vidRes = [roi(4), roi(3)];
            else
                this.vidRes = [100 100];
            end
            
            % Populate figure handles
            this.parentHandle = open('AlbumGUI.fig');
            children = this.parentHandle.Children;
            set(this.parentHandle,'CloseRequestFcn',@this.delete);
            for i=1:numel(children)
                this.(children(i).Tag) = this.parentHandle.findobj('tag',children(i).Tag);
            end
            
            this.albumPreviewData = imagesc(this.albumAxes, zeros(this.vidRes));
            colormap(this.albumAxes, 'gray');
            set(this.albumAxes, 'XTick',[]);
            set(this.albumAxes, 'YTick',[]);
            set(this.albumAxes, 'XTickLabel',[]);
            set(this.albumAxes, 'YTickLabel',[]);
            axis(this.albumAxes, 'image');
    
            % Set album callbacks
            set(this.clearAlbumButton, 'Callback',@this.clearAlbumButton_Callback);
            set(this.saveAlbumButton, 'Callback',@this.saveAlbumButton_Callback);
            set(this.albumSliceSlider, 'Callback',@this.albumSliceSlider_Callback);
            set(this.snapAlbum, 'Callback',@this.snapAlbum_Callback);
            set(this.retakeImageButton, 'Callback', @this.retakeImageButton_Callback);
                    
            % Update GUI
            this.updateGUI();
        end
        
        function delete(this,~,~)
           delete(this.parentHandle);
           this.parentHandle = -1;
           this.parent.clearAlbum();
        end
        
        function ch = getChannel(this,ind)
            % Returns channel string of given image slice index
            % Returns current channel if no index is given
            if nargin<2
                ind = this.currentAlbumSlice;
            end
            
            ch = this.channels{ mod(ind-1,this.nChannels) +1};
        end
        
        function fov = getFOV(this,ind)
            % Returns FOV number of given image slice index
            % Returns current FOV number if no index is given
            if nargin<2
                ind = this.currentAlbumSlice;
            end
            
            fov = 1+floor((ind-1)/this.nChannels);
        end
        
        function retakeImageButton_Callback(this, ~,~)
            this.albumData = this.albumData(:,:,1:(end-1));
            this.nAlbumSlices = size(this.albumData,3);
            this.currentAlbumSlice = this.nAlbumSlices;
            this.snapAlbum_Callback();
        end
        
        function snapAlbum_Callback(this, ~,~)
            if ~isempty(this.vid)
                % Go to the preset channel for the next frame
                this.parent.changePreset(this.getChannel(this.currentAlbumSlice+1));
                frame = this.parent.snapImage();
            else
                frame = ones(this.vidRes);
            end           
            
            % Update album and preview data buffers, update GUI
            this.albumPreviewData.CData = frame;
            drawnow();
            this.albumData(:,:,this.nAlbumSlices+1) = frame;
            this.nAlbumSlices = size(this.albumData,3);
            this.currentAlbumSlice = this.nAlbumSlices;
            this.parent.changePreset(this.getChannel(this.currentAlbumSlice+1));

            this.albumNull = false;
            
            % Add a metadata entry for this frame
            tempStruct = this.presetMap(this.getChannel());
            tempStruct.ExposureTimeMs = this.src.E2ExposureTime;
            tempStruct.FieldOfView = this.getFOV();
            this.updateMetadata();
            this.albumSavedFlag = false;
            
            this.updateGUI();
        end
        
        function updateMetadata(this)
            for i=1:this.nAlbumSlices
                md = this.presetMap(this.getChannel(i));
                md.channelNumber = mod(i-1,this.nChannels);
                md.sliceNumber = 1; % For consistency with the MDA metadata
                md.channel = this.getChannel(i);
                md.positionNumber = this.getFOV(i); 
                tempStruct(i) = md;
            end
            this.metadata = tempStruct;
        end
        
        function updateGUI(this)
            % Slice texts       
            set(this.nAlbumSlicesText,'String',['/' num2str(this.nAlbumSlices)]);
            set(this.currentAlbumSliceText,'String',num2str(this.nAlbumSlices));
            
            % Channel texts
            set(this.channelText,'String',this.getChannel());
            set(this.nextChannelText, 'String',['Next channel: ' this.getChannel(this.nAlbumSlices+1)]);
            
            % If album saved
            if this.albumSavedFlag
                set(this.albumSavedIndicator,'BackgroundColor',[0.5 1 0.5]);
                set(this.albumSavedIndicator,'String','Album saved');
            else
                set(this.albumSavedIndicator,'BackgroundColor',[1 .5 0.5]);
                set(this.albumSavedIndicator,'String','Album Not saved');
            end
            
            if this.albumNull
                set(this.albumSliceSlider, 'Min', 0);
                set(this.albumSliceSlider, 'Value', 0);
                set(this.albumSliceSlider, 'Max', 0);
                set(this.albumSliceSlider,'SliderStep',[1, 1]);   
                this.albumPreviewData.CData = zeros(this.vidRes);
            else
                set(this.albumSliceSlider,'Max',this.nAlbumSlices);
                set(this.albumSliceSlider, 'Value', this.currentAlbumSlice);
                set(this.albumSliceSlider,'Min',1);
                set(this.albumSliceSlider,'SliderStep',[1/this.nAlbumSlices, 1]);   
                this.albumPreviewData.CData = this.albumData(:,:,this.currentAlbumSlice);
            end
            
            if this.nAlbumSlices > 1
                set(this.albumSliceSlider, 'Visible', 'On');
            else
                set(this.albumSliceSlider, 'Visible','Off');
            end
            
        end
        
        function clearAlbumButton_Callback(this, ~, ~)
            this.albumData = zeros(this.vidRes);
            this.albumNull = true;
            this.currentAlbumSlice = 1;
            this.nAlbumSlices = 0;
            this.albumSavedFlag = false;
            this.updateGUI();
        end
        
        function saveAlbumButton_Callback(this, ~, ~)
            pathname = uigetdir();
            if pathname ~= 0
                prefix = inputdlg('Please enter a filename prefix','Filename prefix');
                prefix = prefix{1};
                j = 1;
                
                % Write metadata file
                fid = fopen([pathname, '\' prefix '-metadata.json'],'w');
                fprintf(fid,jsonencode(this.metadata),'w');
                fclose(fid);
                
                while j < this.nAlbumSlices
                    for k=1:this.nChannels
                        filename = [prefix '-ch-' num2str(k-1,'%02i') '-' num2str(floor((j-1)/this.nChannels), '%05i') '.tif'];
                        fullfileName = [pathname, '\' filename];
                        imwrite(uint16(this.albumData(:,:,j)),fullfileName);
                        j = j+1;
                    end
                end
                this.albumSavedFlag = true;
                this.updateGUI();
            end
        end
        
        function albumSliceSlider_Callback(this, ~, ~)
            this.currentAlbumSlice = max(1,round(get(this.albumSliceSlider,'Value')));
            this.updateGUI();
        end
        
        
    end
    
end