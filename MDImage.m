classdef MDImage < handle
    
    % The MDImage class serves to store and interact with Multi-Dimensional
    % image data. The intented usage is for a microscope OS to create an
    % MDImage object and feed it images as they come in. The images can be
    % saved to disk in binary format as they come in (this is much faster
    % than saving as .TIFF) to maintain speed and compatibility with large
    % datasets. The MDImage object is initialized with a parameter set which
    % describes the acquisition parameters as well as the metadata for each
    % of the images. This object stores the image metadata internally and
    % can also write it to a .JSON file, and does so when exporting to
    % TIFF.
    
    % MDImage always works in the 'uint16' format for raw data, and double
    % for processing data.
    
    % MDImage can optionally load images from the raw file into memory for
    % performing image processing and/or visualization. Regardless of the
    % actual acquisition order used to acquire them, the images are
    % imported and stored as a multi-dimensional array within Matlab with
    % the following dimensions:
    
    % [rows, cols, slices, channels, positions, times]
    
    % Additionally, MDImage has a built-in MD image viewer with slider
    % bars to navigate the multi-dimensional image space. It also has the
    % ability to flip between flat field and deconvoluted corrected
    % versions of the dataset, as well as overlay 3D dispersed PSFs from
    % the same microscope, to simulate single emitters distributed
    % throughout the image volume.
    
    % MDImage performs many image processing operations, including:
    % - Deconvolution
    % - Stack alignment over time (drift correction)
    % - Stack alignment over z (focus stack alignment)
    % - Transport of Intensity using the full, non-uniform illumination model
    % - Digital re-focussing
    % - Affine transformation
    % - Flat field correction
    % - Principal component analysis of z-stacks
    
    %  Paul Lebel
    %  czbiohub
    %%
    %==========================================================================
    %
    %   READ ONLY PROPERTIES
    %
    %==========================================================================
    properties (SetAccess = private, GetAccess = public)
        MDParams
        metadataFullpath
        images
        correctedImages
        pcaMats
        bgImageMap
        correctionList = {};
        simImages
        acquisitionOrder
        fileOrder
        presetMap
        flatField
        focusValid
        deconv
        frameDims
        frameSizeBytes
        totalImageBytes
        channels
        nPositions
        nSlices
        nTimes
        nChannels
        nImages
        isOldManualAlbum = false;
        
        % Loaded image indices into the full XYZCT space
        slInds
        chInds
        tInds
        pInds
        
        nImagesWritten
        nImagesUnwritten
        filepath
        filepathCorrected
        filePrefix
        filePrefixCorrected
        metadata
        
        % Maps the metadata field names from the user's instrument to the
        % universal fields in FlatFieldPoly and ImageDeconv
        fieldsToCheck
        allowedFileOrders = {'linear','indexed'};
        
        % Fit order for flat field correction
        ffPolyOrder = 2;
        
        imagesLoaded = false
        
        psfCoords
        z_step_um
        
        scaleUpperBound = .999;
        scaleLowerBound = .001;
    end
    
    properties (Constant, Access = protected)
        % List of fields that need to be saved
        fieldsToSave = {'frameDims','MDParams','presetMap', ...
            'isOldManualAlbum','fileOrder','filepath','filePrefix',...
            'filepathCorrected','filePrefixCorrected','flatField','deconv', ...
            'pcaMats'};
        
        % The required fields in the MDParams struct
        MDParamFields = {'positions_um', 'zStackVec_um', 'timeVec_s', ...
            'channels', 'frameDims', 'acquisitionOrder'};
    end
    
    properties(Access = private)
        
        % Display GUI stuff
        mainHandle
        uitoolbar1
        zoomInButton
        zoomOutButton
        albumAxes
        albumPreviewData
        timeSlider
        channelSlider
        sliceSlider
        positionSlider
        currentTime
        currentChannel
        currentSlice
        currentPosition
        timeText
        channelText
        sliceText
        dispCorrList
        mipDisplayButton
        currentTimeText
        currentChText
        currentSliceText
        currentPositionText
        markerOverlay
        markerOverlayButton
        text8
    end
    
    %==========================================================================
    %
    %   PUBLIC METHODS
    %
    %==========================================================================
    methods(Access = public)
        
        % Class constructor
        % Input arguments:
        
        % MDParams: struct containing information about the dataset. It
        % must contain the following fields:
        %   - positions_um (nx3 element array of positions. Each row is a
        %   - vector: [x_um,y_um,z_um]
        %   - zStackVec_um (Vector of relative zStack positions. Ex. [-20:5:20])
        %   - timeVec_s (vector of delay times)
        %   - channels (Cell array of preset channel names which are used
        %       in this acquisition - these each need to be keys to the presetMap
        %       variable)
        %   - frameDims (two-element vector of single frame dimensions)
        %   - acquisitionOrder (A string describing the acquisition
        %       order.
        
        % [optional] presetMap: map object whose keys are the names of the
        % preset channels and whose values are structs defining
        % instrument parameters for acquisition
        
        % [optional] fileOrder
        
        % [optional] isOldManualAlbum
        
        
        % Assumptions:
        % - All slices of the same channel (but different z-positions and
        % time points) are acquired with the same acquisition parameters.
        % Specifically, the flat field and deconvolution classes track a
        % subset of metadata parameters which is always checked before
        % performing image corrections.
        
        function this = MDImage(frameDims, MDParams, presetMap, fileOrder, isOldManualAlbum)
            
            if nargin < 1
                error('"frameDims" is a required argument');
            elseif numel(frameDims) ~= 2
                error('"frameDims" must have two elements.');
            else
                this.frameDims = frameDims;
                % We only work with 16-bit data (double is used for
                % calculations, but not stored in class properties)
                this.frameSizeBytes = prod(frameDims)*2;
            end
            
            if (nargin > 1) && ~isempty(MDParams)
                this.setMDParams(MDParams);
            end
            
            if (nargin > 2)&& ~isempty(presetMap)
                this.setPresetMap(presetMap);
            end
            
            % If a file order is not specified explicitly, default to
            % indexed
            if (nargin > 3) && ~isempty(fileOrder)
                if ismember(fileOrder, this.allowedFileOrders)
                    this.fileOrder = fileOrder;
                else
                    warning('provided file order is not allowed.');
                    this.fileOrder = 'indexed';
                end
            else
                this.fileOrder = 'indexed';
            end
            
            if (nargin > 4) && ~isempty(isOldManualAlbum)
                this.isOldManualAlbum = isOldManualAlbum;
            end
            
            this.bgImageMap = containers.Map();
            this.nImagesWritten = 0;
            this.nImagesUnwritten = this.nImages;
            this.mainHandle = -1;
            
        end
        
        % Method: setkMDParams
        % Helper method to check the input MDParams and unpack them
        function setMDParams(this, MDParams)
            
            % Check that the input MDParams has all the required fields
            hasThemAll = true;
            for i = this.MDParamFields
                if ~ismember(i{1},fields(MDParams))
                    hasThemAll = false;
                end
            end
            
            if ~hasThemAll
                error('"MDParams" does not have all the required fields.');
            else
                this.MDParams = MDParams;
            end
            
            % Unpack MDParams for convenience
            this.channels = MDParams.channels;
            this.acquisitionOrder = this.MDParams.acquisitionOrder;
            this.nPositions = size(this.MDParams.positions_um,1);
            this.nChannels = numel(this.MDParams.channels);
            this.nSlices = numel(this.MDParams.zStackVec_um);
            this.nTimes = numel(this.MDParams.timeVec_s);
            this.nImages = this.nPositions*this.nChannels*this.nSlices*this.nTimes;
        end
        
        function setBGImage(this, channel, bgImage)
            answer = true;
            if isKey(this.bgImageMap, channel)
                if ~isempty(this.bgImageMap(channel))
                    answer = yesNoDialog(['BG Image for ' channel ' already exists.',...
                        'Would you like to overwrite it?'],'Existing BG Image','No',true);
                end
            end
            
            if any(ismember(this.channels,channel))
                
                if answer
                    this.bgImageMap(channel) = bgImage;
                end
            else
                error([channel ' does not exist.']);
            end
        end
        
        % Method: setkMDParams
        % Helper method to check the input MDParams and unpack them
        function setPresetMap(this, presetMap)
            
            if ~isa(presetMap,'containers.Map')
                error('"presetMap" must be a map object.');
            end
            
            if isempty(presetMap)
                error('"presetMap" cannot be empty.');
            end
            
            mapKeys = keys(presetMap);
            hasThemAll = true;
            
            % 
            for i = this.channels
                while isa(i,'cell')
                    i = i{1};
                end
                if ~ismember(i,mapKeys)
                    hasThemAll = false;
                end
            end
            
            if hasThemAll
                this.presetMap = presetMap;
            else
                error('"presetMap" must have entries for all the channels in the dataset.');
            end
            
        end
        
        % Method: createFlatfieldCorrection initializes the FlatfieldPoly object
        % fieldsToCheck: fields used by FlatFieldPoly and ImageDeconv
        % to specify whether instrument settings are compatible for the
        % given image correction dataset.
        function createFlatfieldCorrection(this, fieldsToCheck)
            
            if isempty(this.presetMap)
                error('"presetMap" must be defined to create flatField object.');
            end
            
            % If flatField object already exists, make sure user wants to
            % overwrite it
            if ~isempty(this.flatField)
                answer = yesNoDialog('Are you sure you want to re-initialize the deconvolution object?', 'Reset deconv', 'No',true);
                if ~answer
                    return;
                end
            end
            
            if nargin > 1
                % Create the flatfield object specifying fieldsToCheck
                this.flatField = FlatFieldPoly(this.frameDims,this.ffPolyOrder, fieldsToCheck);
            else
                % All FlatFieldPoly to use default fields
                this.flatField = FlatFieldPoly(this.frameDims,this.ffPolyOrder);
            end
            
            
            % Add channels to the FF object
            for i=1:this.nChannels
                thisChannel = this.MDParams.channels{i};
                
                % Add the channel with metadata to the flat field object
                this.flatField.addChannels({thisChannel}, {this.presetMap(thisChannel)});
            end
        end
        
        % Method: createDeconvCorrection initializes the ImageDeconv object
        % fieldsToCheck: fields used by FlatFieldPoly and ImageDeconv
        % to specify whether instrument settings are compatible for the
        % given image correction dataset.
        function createDeconvCorrection(this, fieldsToCheck)
            
            if isempty(this.presetMap)
                error('"presetMap" must be defined to create deconv object.');
            end
            
            if ~isempty(this.deconv)
                answer = yesNoDialog('Are you sure you want to re-initialize the deconvolution object?', 'Reset deconv', 'No',true);
                if ~answer
                    return;
                end
            end
            
            if nargin > 1
                % Create the deconvolution object with custom fieldsToCheck
                this.deconv = ImageDeconv(this.frameDims,fieldsToCheck);
            else
                % Create the deconvolution object with standard
                % fieldsToCheck
                this.deconv = ImageDeconv(this.frameDims);
            end
            % Add channels to the ID object
            for i=1:this.nChannels
                thisChannel = this.MDParams.channels{i};
                
                % Add the deconvolution channels
                this.deconv.addChannels({thisChannel}, {this.presetMap(thisChannel)});
            end
            
        end
        
        % Method: setFileOrder
        % This method sets the internal fileOrder property, which is a flag
        % to indicate whether the files on disk are enumerated in linear
        % order or in indexed order. Overall it would be better to stick
        % with one indexing method, but early versions wrote linear file
        % order to disk and backwards compatibility is desired.
        function setFileOrder(this, fileOrder)
            answer = yesNoDialog('Are you sure you want to change the file order?','File order','No',true);
            if answer
                if ismember(fileOrder, this.allowedFileOrders)
                    this.fileOrder = fileOrder;
                else
                    error(['Incorrect fileOrder argument!']);
                end
            end
        end
        
        % Method: setFilePath
        % This method sets the filepath property, determining the directory
        % that contains the images, either .tiff or raw.
        function setFilePath(this, filepath,filePrefix)
            this.filepath = filepath;
            this.filePrefix = filePrefix;
            this.metadataFullpath = fullfile(this.filepath, [this.filePrefix, '_metadata.json']);
        end
        
        % Method: inputImages
        % This method allows the sequential input of images into the class,
        % for example, from a microscope that is sending one or more
        % images at a time.
        
        % Inputs
        % images: 3D array of uint16 containing the image data to input. The size of
        % each frame must be consistent with the frameSize property.
        
        % metadata: Metadata for the entire acquisition up to this point in
        % time. NOTE: I should change this so that metadata is specific to
        % the image batch being passed in each call. That way, a metadata
        % file would be written for each image (or for the entire dataset,
        % if desired), and that would be more general.
        
        % keepInMemory: Boolean flag to keep the image data in memory or
        % not.
        
        % saveFormat: a string which is either 'tiff','raw', or 'none'
        function inputImages(this, images, metadata, keepInMemory, saveFormat)
            
            if nargin < 5
                saveFormat = 'none';
            end
            
            if nargin < 4
                keepInMemory = true;
            end
            
            this.imagesLoaded = true;
            this.metadata = metadata;
            
            % Check inputs
            if ~isa(images,'uint16')
                error('images must be uint16!');
            end
            
            if (size(images,1) ~= this.frameDims(1))||...
                    (size(images,2)~=this.frameDims(2))
                error('Input image frame is the wrong size!');
            end
            
            if strcmp(saveFormat,'none')
                if size(images,3) > this.nImagesUnwritten
                    error('Too many images in this stack! There are more images here than what remain to be written.');
                end
            end
            
            % Get the multi-D indices into the image stack positions
            subInds = this.getSubscriptInds(this.nImagesWritten + (1:size(images,3)));
            
            % Attempt to write the data
            %             try
            if ~exist(this.filepath,'dir')
                mkdir(this.filepath);
            end
            
            % Write metadata file
            if numel(this.metadata) == 1
                fid2 = fopen(this.metadataFullpath,'w');
                fprintf(fid2,'[');
                fprintf(fid2,[jsonencode(this.metadata(end)),',']);
                fclose(fid2);
            elseif numel(this.metadata) == this.nImages
                fid2 = fopen(fullfile(this.filepath,[this.filePrefix '_metadata.json']),'a');
                fprintf(fid2,[jsonencode(this.metadata(end)),']']);
                fclose(fid2);
            else
                fid2 = fopen(fullfile(this.filepath,[this.filePrefix '_metadata.json']),'a');
                fprintf(fid2,[jsonencode(this.metadata(end)),',']);
                fclose(fid2);
            end
            
            switch saveFormat
                case 'tiff'
                    for i=1:size(images,3)
                        fn = this.getFilename(subInds(i,1), subInds(i,2), subInds(i,3), subInds(i,4));
                        imwrite(images(:,:,i), fn);
                    end
                    
                case 'raw'
                    fid = fopen([this.filepath, '\' this.filePrefix '.dat'],'a');
                    fwrite(fid, images(:), 'uint16');
                    fclose(fid);
            end
            
            if keepInMemory
                for i=1:size(images,3)
                    this.images(:,:,subInds(i,1), subInds(i,2), subInds(i,3), subInds(i,4)) = images;
                    this.currentSlice = subInds(i,1);
                    this.currentChannel = subInds(i,2);
                    this.currentPosition = subInds(i,3);
                    this.currentTime = subInds(i,4);
                end
            end
            
            this.nImagesWritten = this.nImagesWritten + size(images,3);
            this.nImagesUnwritten = this.nImages - this.nImagesWritten;
        end
        
        % Method importMetadata: Reads a metadata file (.json format), for
        % example as written by this class. The metadata fields are read
        % and interpreted, populating internal class properties. This
        % method is used when re-creating an MDImage object from existing raw
        % .tiff images and a metadata file. The user therefore does not
        % need to instantiate the constructor with MDParams, presetMap, or
        % file order.
        function importMetadata(this, fullFilename)
            askUser = false;
            if nargin < 2
                fullFilename = fullfile(this.filepath, [this.filePrefix '_metadata.json']);
            end
            
            try
                fid = fopen(fullFilename,'r');
                textvec = fread(fid, '*char');
                fclose(fid);
            catch
                warning('Metadata file was not read. Defaulting to user.');
                askUser = true;
                this.metadata = struct();
            end
            
            if ~askUser
                try
                    if iscolumn(textvec)
                        textvec = textvec';
                    end
                    
                    % Repair possibly incomplete file
                    if textvec(end) ~= ']'
                        textvec(end) = ']';
                    end
                    
                    this.metadata = jsondecode(textvec);
                catch
                    warning('Metadata format was incorrect. Defaulting to user.');
                    this.metadata = struct();
                end
            end
            
            % Decode the acquisition order
            if isa(this.metadata,'cell')
                this.metadata = [this.metadata{:}];
            end
            
            if isfield(this.metadata,'channel')
                this.channels = unique({this.metadata.channel},'stable');
                this.nChannels = numel(this.channels);
            else
                expression = inputdlg('There is no "channel" metadata field. In order of acquisition, please enter the channel names in cell array format');
                eval(['this.channels = ', expression{1}]);
                this.nChannels = numel(this.channels);
            end
            
            this.chInds = 1:this.nChannels;
            
            if isfield(this.metadata,'channelNumber')
                channelNumbers = [this.metadata.channelNumber];
            else
                expression = inputdlg('There is no "channelNumber" metadatafield. Please enter an expression that evaluates to a vector of channel numbers.');
                expression = expression{1};
                eval(['channelNumbers = ', expression,';']);
            end
            
            % Find the repeating period
            temp = find(channelNumbers ~= channelNumbers(1),1);
            if numel(temp) > 0
                chRepeatPeriod = temp;
            else
                chRepeatPeriod = inf;
            end
            
            if isfield(this.metadata,'sliceNumber')
                sliceNumbers = [this.metadata.sliceNumber];
                this.nSlices = numel(unique(sliceNumbers));
            else
                expression = inputdlg('There is no "sliceNumber" metadatafield. Please enter an expression that evaluates to a vector of channel numbers.');
                expression = expression{1};
                eval(['sliceNumbers = ', expression,';']);
                this.nSlices = numel(unique(sliceNumbers));
            end
            
            this.slInds = 1:this.nSlices;
            
            % Find the repeating period
            temp = find(sliceNumbers ~= sliceNumbers(1),1);
            if numel(temp) > 0
                slRepeatPeriod = temp;
            else
                slRepeatPeriod = inf;
            end
            
            if isfield(this.metadata,'timeNumber')
                timeNumbers = [this.metadata.timeNumber];
                this.nTimes = numel(unique(timeNumbers));
            else
                expression = inputdlg('There is no "timeNumber" metadatafield. Please enter an expression that evaluates to a vector of channel numbers.');
                expression = expression{1};
                eval(['timeNumbers = ', expression,';']);
                this.nTimes = numel(unique(timeNumbers));
            end
            
            this.tInds = 1:this.nTimes;
            
            % Find the repeating period
            temp = find(timeNumbers ~= timeNumbers(1),1);
            if numel(temp) > 0
                tRepeatPeriod = temp;
            else
                tRepeatPeriod = inf;
            end
            
            if isfield(this.metadata,'positionNumber')
                positionNumbers = [this.metadata.positionNumber];
                this.nPositions = numel(unique(positionNumbers));
            else
                expression = inputdlg('There is no "positionNumber" metadatafield. Please enter an expression that evaluates to a vector of channel numbers.');
                expression = expression{1};
                eval(['positionNumbers = ', expression,';']);
                this.nPositions = numel(unique(positionNumbers));
            end
            
            this.pInds = 1:this.nPositions;
            
            % Find the repeating period
            temp = find(positionNumbers ~= positionNumbers(1),1);
            if numel(temp) > 0
                pRepeatPeriod = temp;
            else
                pRepeatPeriod = inf;
            end
            
            this.nImages = this.nPositions*this.nChannels*this.nSlices*this.nTimes;
            
            repPeriods = [slRepeatPeriod, chRepeatPeriod, pRepeatPeriod, tRepeatPeriod];
            
            % If the repeating period is infite, this is a singlton
            % dimension.
            %             repPeriods(~isfinite(repPeriods)) = 1;
            
            [repPeriodsSorted, IX] = sort(repPeriods);
            
            % Deal with singleton dimensions by setting each to
            % their default order (ZCXYT).
            dimNames = {'Z','C','XY','T'};
            this.acquisitionOrder = [dimNames{IX}];
            
            delta = this.nImages - numel(this.metadata);
            
            % Then the data acquisition did not run to completion
            if abs(delta)>0
                warning('Calculated number of images does not match number of metadata entries.', ...
                    newline, ...
                    'Truncating dataset to match metadata entries that are present.');
                finiteInds = find(isfinite(repPeriodsSorted));
                msb = dimNames{IX(finiteInds(end))};
                
                switch msb
                    case 'T'
                        this.nTimes = this.nTimes - ceil(delta/(this.nChannels*this.nSlices*this.nPositions));
                    case 'XY'
                        this.nPositions = this.nPositions - ceil(delta/(this.nChannels*this.nSlices*this.nTimes));
                    case 'C'
                        this.nChannels = this.nChannels - ceil(delta/(this.nPositions*this.nSlices*this.nTimes));
                    case 'Z'
                        this.nSlices = this.nSlices - ceil(delta/(this.nPositions*this.nChannels*this.nTimes));
                end
                
                this.nImages = this.nTimes*this.nPositions*this.nChannels*this.nSlices;
                
            end
            
            % Pack MDParams
            this.MDParams.channels = this.channels;
            this.MDParams.acquisitionOrder = this.acquisitionOrder;
            this.MDParams.positions_um = unique([this.metadata(:).position]','rows');
            this.MDParams.zStackVec_um = unique([this.metadata(:).slice_um]);
            this.MDParams.timeVec_s = unique([this.metadata(:).timeNumber]);
            this.nImages = this.nPositions*this.nChannels*this.nSlices*this.nTimes;
            this.MDParams.frameDims = this.frameDims;
            
        end
        
        function scaleDynamicRange(this, whichData, nBits)
            % Scales image data to 16-bit range
            % whichData is either 'raw' or 'corrected'
            
            if nargin < 3
                nBits = 16;
            end
            
            if nargin < 2
                whichData = 'raw';
            end
            
            switch whichData
                case 'raw'
                    ma = double(max(this.images(:)));
                    mi = double(min(this.images(:)));
                    this.images = int16((2^nBits-1)*(double(this.images) - mi)/(ma-mi));
                case 'corrected'
                    ma = double(max(this.correctedImages(:)));
                    mi = double(min(this.correctedImages(:)));
                    this.correctedImages = uint16((2^nBits-1)*(double(this.correctedImages) - mi)/(ma-mi));
            end
        end
            
        
        function fullFilenames = exportCorrectedImages(this, filepath, filePrefix, assert, writeValidFocusOnly)
            
            if nargin < 5
                writeValidFocusOnly = false;
            end
            
            if nargin < 4
                assert = false;
            end
                        
            this.filepathCorrected = filepath;
            this.filePrefixCorrected = filePrefix;
            if ~exist(filepath,'dir')
                try
                    mkdir(filepath);
                catch
                    error('Specified filepath did not exist and could not be created.');
                end
            end
            dims = zeros(6,1);
            for i=1:6
                dims(i) = size(this.correctedImages,i);
            end
            
            answer = false;
            
            if ~assert
                % Check if the user wants to proceed
                answer = yesNoDialog(['There are ' num2str(prod(dims(3:end))), ...
                    ' images of size ', num2str(dims(1)), ' x ', num2str(dims(2)), ...
                    '. Proceed with export?'], 'Corrected images export', 'No', true);
            end
            
            if assert||answer
                
                %                 if writeValidFocusOnly
                %                     % This option checks to see whether there was a valid
                %                     % focus found for each position and time point. The
                %                     % criteria is that all color channels and time points
                %                     % must have valid focii, or that position will not be
                %                     % exported. Exported file names will then not include
                %                     % those positions with invalid focus, and the outputted
                %                     % file names will have indices shifted such that the
                %                     % outputted positions are indexed continuously.
                %
                %                     stopInd = find(~this.focusValid,1);
                %                     if ~isempty(stopInd)
                %                         [~, jMax, iMax] = ind2sub(size(this.focusValid), stopInd);
                %                     else
                %                         jMax = dims(5);
                %                         iMax = dims(6);
                %                     end
                %
                %                 else
                
                iVec = 1:dims(6);
                jVec = 1:dims(5);
                kVec = 1:dims(4);
                lVec = 1:dims(3);
                %                 end
                
                fullFilenames = {};
                
                posCount = 0;
                for j = jVec
                    % Optionally check if this position has valid focus
                    % for all colors/time points
                    if all(this.focusValid(:,j,:),'all') || (~writeValidFocusOnly)
                        posCount = posCount + 1;
                        
                        for i = iVec
                            for k = kVec
                                for l = lVec
                                    fullFilenames{l,k,posCount,i} = fullfile(filepath, [filePrefix, ...
                                        '_sl',num2str(l), '_ch',num2str(k), ...
                                        '_p',num2str(j), '_t',num2str(i),'.tif']);
                                    
                                    imwrite(uint16(squeeze(this.correctedImages(:,:,l,k,j,i))), fullFilenames{l,k,posCount,i});
                                end
                            end
                        end
                    end
                end
            end
            
        end
        
        function unloadMetadata(this)
            answer = yesNoDialog('Are you sure you want to unload metadata?','Unload images','No');
            
            if answer
                this.metadata = struct();
            end
            
        end
        
        % Method getFilename returns a full filename for an indexed image.
        % If the internal property 'fileOrder' is set to 'linear', the
        % filename will contain a linear index. If it's set to 'indexed'
        % (default) then it will contain separate slice, channel, position,
        % and time indices.
        function fn = getFilename(this, slIndTemp, chIndTemp, pIndTemp, tIndTemp)
            
            sizeVec = [numel(slIndTemp), numel(chIndTemp), numel(pIndTemp), numel(tIndTemp)];
            if any(sizeVec>1)
                error('getFilename does not support vectors yet.');
            end
            
            if this.isOldManualAlbum
                fn = fullfile(this.filepath,[this.filePrefix '-ch-',...
                    num2str(chIndTemp-1,'%02i') '-' num2str(pIndTemp-1, '%05i'), '.tiff']);
            else
                
                switch this.fileOrder
                    case 'linear'
                        try
                            linInd = this.getLinearInds(slIndTemp,chIndTemp,pIndTemp,tIndTemp);
                        catch
                            linInd =  1;
                            warning('Could not assign linear index');
                        end
                        fn = fullfile(this.filepath, [this.filePrefix,...
                            num2str(linInd-1,'%i'), '.tiff']);
                        
                    case 'indexed'
                        
                        fn = fullfile(this.filepath,[this.filePrefix, '_'...
                            'sl', num2str(slIndTemp), '_', 'ch', num2str(chIndTemp), ...
                            '_','p', num2str(pIndTemp), '_', 't', num2str(tIndTemp), ...
                            '.tiff']);
                end
                
            end
            
        end
        
        % Method: getSubscriptInds converts a linear index to a subscripted
        % index, given the size/dimensionality of the multi-D dataset.
        function subInds = getSubscriptInds(this,linInd)
            % Uses the current nPositions, nSlices, nTimes, and nChannels as
            % the total image array size to return subscripted indices into
            % the loaded image stack, given the linear index provided.
            
            [slIndsTemp, chIndsTemp, pIndsTemp, tIndsTemp] = ind2sub([this.nSlices, this.nChannels, this.nPositions, ...
                this.nTimes], linInd);
            subInds = [slIndsTemp', chIndsTemp', pIndsTemp', tIndsTemp'];
        end
        
        % Method: getLinearInds converts subscripted indices into a linear
        % index, given the size/dimensionality of the multi-D dataset.
        function linInds = getLinearInds(this,slices,channels,positions,times)
            % Returns the linear indices into the non-image-pixel
            % dimensions (ie. all but the first two dims) of the MDImage,
            % in order to generate offsets for the binary file.
            
            % Only doing this for shorthand
            nc = numel(this.MDParams.channels);
            nt = numel(this.MDParams.timeVec_s);
            ns = numel(this.MDParams.zStackVec_um);
            np = size(this.MDParams.positions_um,1);
            
            switch this.acquisitionOrder
                case 'ZCXYT'
                    linInds = sub2ind([ns,nc,np,nt],slices,channels,positions,times);
                case 'CZXYT'
                    linInds = sub2ind([nc,ns,np,nt],channels,slices,positions,times);
                case 'TCZXY'
                    linInds = sub2ind([nt,nc,ns,np],times,channels,slices,positions);
                case 'TZCXY'
                    linInds = sub2ind([nt,ns,nc,np],times,slices,channels,positions);
                case 'ZXYCT'
                    linInds = sub2ind([ns,np,nc,nt],slices, positions, channels, times);
                case 'ZXYTC'
                    linInds = sub2ind([ns,np,nt,nc],slices, positions, times, channels);
                case 'T'
                    linInds = sub2ind([nt 1],times);
                otherwise
                    linInds = 0;
                    warning('Acquisition order is not defined');
            end
            
        end
        
        function allocateImages(this,slices,channels,positions,times,assert)
            
            if nargin < 6
                assert = false;
            end
            
            % Save a copy of existing loaded indices in case the user
            % cancels
            tempSlices = this.slInds;
            tempChannels = this.chInds;
            tempPositions = this.pInds;
            tempTimes = this.tInds;
            
            % Check input indices, set to default if not provided
            this.checkIndices(slices, channels, positions, times);
            
            % Ask user if memory amount is ok
            if ~assert
                % Pre-allocate the image array. This could be very large
                this.totalImageBytes = this.frameSizeBytes*...
                    numel(this.slInds)*numel(this.chInds)*numel(this.pInds)*...
                    numel(this.tInds);
                mem = memory;
                answer = yesNoDialog(['Total image size is ', num2str(this.totalImageBytes/(1E6)), ...
                    ' MB. Max possible array in Matlab is: ' ...
                    num2str(mem.MaxPossibleArrayBytes/(1E6)), ' MB. ', ...
                    'Continue?'], 'Image size warning','No');
            else
                answer = true;
            end
            
            % User asserts memory usage is ok
            if answer
                this.images = zeros(this.frameDims(1), this.frameDims(2), ...
                    numel(slices), numel(channels), numel(positions), numel(times),'uint16');
            else % User says 'No'. Restore the original indices
                this.checkIndices(tempSlices, tempChannels, tempPositions, tempTimes);
            end
        end
        
        % Method: loadImages loads the specified images into memory. If no
        % indices are specified, then the entire dataset is loaded by
        % default. The optional output argument assigns a multi-dimensional
        % array containing the requested images.
        function varargout = loadImages(this, fileType, slices, channels, positions, times, assert)
            
            if nargin < 7 || isempty(assert)
                assert = false;
            end
            if nargin < 6 || isempty(times)
                times = 1:this.nTimes;
            end
            if nargin < 5 || isempty(positions)
                positions = 1:this.nPositions;
            end
            if nargin < 4 || isempty(channels)
                channels = 1:this.nChannels;
            end
            if nargin < 3 || isempty(slices)
                slices = 1:this.nSlices;
            end
            if nargin < 2 || isempty(fileType)
                fileType = 'tiff';
            end
            
            % Save a copy of existing loaded indices in case the user
            % cancels
            tempSlices = this.slInds;
            tempChannels = this.chInds;
            tempPositions = this.pInds;
            tempTimes = this.tInds;
            
            % Check input indices, set to default if not provided
            this.checkIndices(slices, channels, positions, times);
            
            % Pre-allocate the image array. This could be very large
            this.totalImageBytes = this.frameSizeBytes*...
                numel(this.slInds)*numel(this.chInds)*numel(this.pInds)*...
                numel(this.tInds);
            
            mem = memory;
            mem = mem.MaxPossibleArrayBytes;
            
            if ~assert
                answer = yesNoDialog(['Total image size is ', num2str(this.totalImageBytes/(1E6)), ...
                    ' MB. Available memory is: ' ...
                    num2str(mem/(1E6)), ' MB. ', ...
                    'Continue loading?'], 'Image size warning','No');
            else
                answer = true;
            end
            
            if answer || assert
                this.images = uint16(zeros(this.frameDims(1), this.frameDims(2), ...
                    numel(slices), numel(channels), numel(positions), numel(times)));
                
                switch fileType
                    case 'raw'
                        % Read images from the raw file
                        fid = fopen(this.filepath,'r');
                        h = waitbar(0,'Loading images...');
                        for i=this.tInds
                            for j=this.pInds
                                for k=this.chInds
                                    for l=this.slInds
                                        linInd = this.getLinearInds(l,k,j,i);
                                        waitbar(linInd/this.nImages, h);
                                        offset = this.frameSizeBytes*linInd;
                                        fseek(fid, offset, 'bof');
                                        tempVec = fread(fid, this.frameSizeBytes, 'uint16');
                                        this.images(:,:,l,k,j,i) = reshape(tempVec, [this.frameDims(1), this.frameDims(2)]);
                                    end
                                end
                            end
                        end
                    case 'tiff'
                        h = waitbar(0, 'Loading images...');
                        for i=this.tInds
                            for j=this.pInds
                                for k=this.chInds
                                    for l=this.slInds
                                        linInd = this.getLinearInds(l,k,j,i);
                                        waitbar(linInd/this.nImages, h);
                                        fn = this.getFilename(l,k,j,i);
                                        try
                                            tempImage = imread(fn);
                                        catch
                                            tempImage = ones(this.frameDims,'uint16');
%                                             warning('File not found');
                                        end
                                        this.images(:,:,l,k,j,i) = reshape(tempImage, [this.frameDims(1), this.frameDims(2)]);
                                    end
                                end
                            end
                        end
                        delete(h);
                    otherwise
                        error('Invalid file type argument');
                end
                this.imagesLoaded = true;
                
            else % User says 'No'. Restore the original indices
                this.checkIndices(tempSlices, tempChannels, tempPositions, tempTimes);
            end
            
            if nargout
                varargout{1} = this.images;
            end
            
        end
        
        % Method: unloadImages clears all the loaded images from memory
        function unloadImages(this,assert)
            if nargin < 2
                assert = false;
                answer = false;
            else
                answer = true;
            end
            
            if ~assert
                answer = yesNoDialog('Are you sure you want to unload images?','Unload images','No');
            end
            if answer
                this.images = [];
                this.correctedImages = [];
                this.slInds = [];
                this.chInds = [];
                this.tInds = [];
                this.pInds = [];
            end
            this.imagesLoaded = false;
        end
        
        % Method: refocusImages produces a new stack of images, each of
        % which is the best focused image from a z-stack. Therefore the
        % size of the returned stack is collapsed along the slice axis.
        function varargout = refocusImages(this,method,radius,returnMethod, parfocalCorrection)
            % Inputs: 
            % "method": is one of the following strings: 'gradient', 'stdev',
            % or 'stdev_inv'. It selects which focus metric is used
            % 
            % "radius": is the number of slices on each side of the best
            % focus that are either returned or averaged together and
            % returned. 
            
            % "returnMethod": is a string, either 'average' or 'all'. It
            % determines whether the average of the best focus slices is
            % returned or all of them. 
            
            % "parfocalCorrection": is a struct that contains an index for
            % the master channel (use this channel for focus), and relative
            % focus offsets for the rest of the channels. Must contain
            % fields: "offsets", "master".
            
            % Outputs:
            % varargout{1}: The refocused slice(s).
            % varargout{2}: The indices of the slices into the raw dataset.
            % This will be an array of dimensions either [1, nChannels,
            % nPositions, nTimes] if the 'average' method is chosen, or
            % [2*radius + 1, nChannels, nPOsitions, nTimes] if 'all' is
            % chosen. 
            
            thisCorrection = 'Refocus';
            scale = 1;
            
            %% Check inputs
            if nargin < 5 || isempty(parfocalCorrection)
                parfocalCorrection.offsets = zeros(this.nChannels);
                useMaster = false;
            elseif this.nChannels > 1
                useMaster = true;
            else
                useMaster = false;
            end
            
            if nargin < 4 || isempty(returnMethod)
                returnMethod = 'average';
            end
            
            if nargin < 3 || isempty(radius)
                radius = 1;
            end
            
            if nargin < 2 || isempty(method)
                method = 'gradient';
            else
                if ~ismember(method, {'gradient','stdev','stdev_inv','gradient_inv'})
                    error('method is not recognized');
                end
            end
            
            % Initialize dims vec this way to ensure there are six elements
            dims = zeros(6,1);
            for i=1:6
                dims(i) = size(this.images,i);
            end
            
            % Check if image stack exists
            imageStackExists = dims(3) > 1;
            if ~imageStackExists
                warning('Cannot refocus without z-stack data.');
                return;
            end
                        
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            else % Corrected stack already exists. Check if it still has z-stack data
                dims = size(this.correctedImages);
                imageStackExists = dims(3) > 1;
                if ~imageStackExists
                    warning('Cannot refocus without z-stack data.');
                    return;
                end
            end
            
            this.displayImages();
            
            % Create figure window for the focus metric plot
            fig = figure;
            ax = gca;
            
            % Initialize maxInds and focus valid arrays
            bfInds = ones(numel(this.chInds), numel(this.pInds), numel(this.tInds));
            this.focusValid = ones(numel(this.chInds), numel(this.pInds), numel(this.tInds));
            
            % Short circuit and do only the master channel, if appropriate
            if useMaster
                chVec = parfocalCorrection.master;
            else
                chVec = this.chInds;
            end
            
            for i=this.tInds
                for j=this.pInds
                    for k = chVec
                        metricVec = zeros(1,this.nSlices);
                        normVec = metricVec;
                        
                        for m=1:dims(3)
                            thisFrame = imresize(squeeze(double(this.correctedImages(:,:,m,k,j,i))),scale);
                            normVec(m) = mean(thisFrame(:));
                            
                            switch method
                                case 'gradient'
                                    [gradImgX,gradImgY] = gradient(thisFrame);
                                    metricVec(m) = sum(sum( sqrt(gradImgX.^2 + gradImgY.^2)));
                                case 'gradient_inv'
                                    [gradImgX,gradImgY] = gradient(thisFrame);
                                    metricVec(m) = -sum(sum( sqrt(gradImgX.^2 + gradImgY.^2)));
                                case 'stdev'
                                    metricVec(m) = std(thisFrame(:));
                                case 'stdev_inv'
                                    metricVec(m) = -std(thisFrame(:));
                            end
                        end
                        
                        % Normalize the focus metric vector to the average
                        % frame intensity, then scale the entire thing to
                        % have a unity maximum
                        metricVec = metricVec./abs(normVec);
                        metricVec = metricVec/abs(max(metricVec));
%                         metricVec = this.subPoly(metricVec,1);
                        cla;
                        plot(ax,metricVec); hold all;
                        
                        % Check that a maximum value can indeed be found.
                        % Else, set it to 1.
                        tempInd = find(metricVec == max(metricVec),1);
                        if ~isempty(tempInd)
                            bfInds(k,j,i) = tempInd;
                        else
                            bfInds(k,j,i) = 1;
                        end
                        
                        % Show visualization
                        this.currentSlice = bfInds(k,j,i);
                        this.currentChannel = k;
                        this.currentPosition = j;
                        this.currentTime = i;
                        this.updateGUI();
                        
                        % Plot focus metric
                        plot(ax, bfInds(k,j,i), metricVec(bfInds(k,j,i)),'rX');
                        drawnow();
                        
                        if useMaster
                            % Then loop over all the channel indices,
                            % applying the parfocal offset to each
                            
                            for m = this.chInds
                                % Check if best focus index is valid for all
                                % channels. If the best focus is at the edge, then it is
                                % not known if the best focus was found so it's declared bad.
                                zVec = bfInds(k,j,i) + parfocalCorrection.offsets(m) + (-radius:radius);
                                if any(zVec < 1)
                                    zVec = 1 + zVec - min(zVec);
                                    this.focusValid(m,j,i) = false;
                                    warning('Focus not valid!');
                                end
                                if any(zVec > dims(3))
                                    zVec = zVec - (max(zVec) - dims(3));
                                    this.focusValid(m,j,i) = false;
                                    warning('Focus not valid!');
                                end
                                                                
                                switch returnMethod
                                    case 'average'
                                        this.correctedImages(:,:,1,m,j,i) = mean(this.correctedImages(:,:,zVec,m,j,i),3);
                                    case 'all'
                                        this.correctedImages(:,:,1:numel(zVec),m,j,i) = this.correctedImages(:,:,zVec,m,j,i);
                                end
                            end
                        else
                            % Just do the index assignment straight up
                            zVec = bfInds(k,j,i) + (-radius:radius);
                            if any(zVec < 1)
                                zVec = 1 + zVec - min(zVec);
                                this.focusValid(k,j,i) = false;
                                warning('Focus not valid!');
                            end
                            if any(zVec > dims(3))
                                zVec = zVec - (max(zVec) - dims(3));
                                this.focusValid(k,j,i) = false;
                                warning('Focus not valid!');
                            end
                            
                            switch returnMethod
                                case 'average'
                                    this.correctedImages(:,:,1,k,j,i) = mean(this.correctedImages(:,:,zVec,k,j,i),3);
                                case 'all'
                                    this.correctedImages(:,:,1:numel(zVec),k,j,i) = this.correctedImages(:,:,zVec,k,j,i);
                            end
                        end
                    end
                end
            end
                     
            delete(fig);
            
            % Remove the extra slices
            switch returnMethod
                case 'average'
                    this.correctedImages(:,:,2:end,:,:,:) = [];
                case 'all'
                    this.correctedImages = this.correctedImages(:,:,1:numel(zVec),:,:,:);
            end
            
            if nargout > 0
                varargout{1} = this.correctedImages;
            end
            if nargout > 1
                varargout{2} = bfInds;
            end
            
            % Append this correction to the list
            this.correctionList{end+1} = thisCorrection;
            
        end
        
        function dataCorr = subPoly(~,ydata,order)
            
            xdata = [1:numel(ydata)]';
            if ~iscolumn(ydata)
                ydata = ydata';
            end
            
            [p,~,~] = polyfit(xdata,ydata(:),order);
            
            
            dataCorr = ydata - polyval(p,(xdata-mu(1))./mu(2));
            
        end
        
        function varargout = pcaImage(this, useExistingCoeffs)
            
            if nargin < 2
                useExistingCoeffs = false;
            end
            
            dims = size(this.images);
            imageStackExists = dims(3) > 1;
            if ~imageStackExists
                warning('Cannot refocus without z-stack data.');
                return;
            end
            
            thisCorrection = 'pca';
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            else % Corrected stack already exists. Check if it still has z-stack data
                dims = size(this.correctedImages);
                imageStackExists = dims(3) > 1;
                if ~imageStackExists
                    warning('Cannot perform pca without z-stack data.');
                    return;
                end
            end
            
            for i=1:6
                dims(i) = size(this.correctedImages,i);
            end
            % To eliminate broadcast variable in parfor
            dim1 = dims(1);
            dim2 = dims(2);
            dim3 = dims(3);
            
            nFits = prod(dims(4:6));
            pcaStack = double(reshape(this.correctedImages,[dims(1),dims(2),dims(3),nFits]));
            if useExistingCoeffs
                pcaMat = reshape(this.pcaMats, [dims(3),dims(3), nFits]);
                parfor m = 1:nFits
                    dataVecs = double(reshape(permute(pcaStack(:,:,:,m),[3,1,2]),[dim3,dim1*dim2]))';
                    pcaStack(:,:,:,m) = reshape(dataVecs*pcaMat(:,:,m),[dim1,dim2,dim3]);
                end
            else
                pcaMat = zeros(dims(3),dims(3), nFits);
                parfor m = 1:nFits
                    dataVecs = double(reshape(permute(pcaStack(:,:,:,m),[3,1,2]),[dim3,dim1*dim2]))';
                    pcaMat(:,:,m) = pca(dataVecs);
                    pcaStack(:,:,:,m) = reshape(dataVecs*pcaMat(:,:,m),[dim1,dim2,dim3]);
                end
                this.pcaMats = reshape(pcaMat,[dims(3),dims(3),dims(4:6)]);
            end
            pcaStack = uint16((2^16)*(pcaStack - min(pcaStack(:)))./(max(pcaStack(:))-min(pcaStack(:))));
            this.correctedImages = reshape(pcaStack,dims);
            
            if nargout
                varargout{1} = this.correctedImages;
            end
            
            % Append this correction to the list
            this.correctionList{end+1} = thisCorrection;
            
        end
        
        % Method: transportOfIntensity solves the transport of intensity
        % equation (TIE) using the slices axis
        function varargout = transportOfIntensity(this, varargin)
            
            % varargin{1} = outputFilepath
            % varargin{2} = useBGImage
            % varargin{3} = useBestNFocus
            
            thisCorrection = 'TIE';
            
            if isempty(varargin)
                outputFilepath = '';
                useBGImage = false;
            else
                outputFilepath = varargin{1};
                if numel(varargin) > 1
                    useBGImage = varargin{2};
                end
                if numel(varargin) > 2
                    useFocusRadius = varargin{3};
                else
                    useFocusRadius = 0;
                end
            end
            
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    if ~this.imagesLoaded
                        disp('No images loaded. Loading images...');
                        this.loadImages();
                    end
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            else % Corrected stack already exists. Check if it still has z-stack data
                dims = size(this.correctedImages);
                imageStackExists = dims(3) > 1;
                if ~imageStackExists
                    warning('Cannot perform TIE without z-stack data. Try unloading corrected images to use raw images as starting point.s');
                    return;
                end
                % Check if this correction has already been done
                if ismember(thisCorrection, this.correctionList)
                    answer = yesNoDialog( ...
                        [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                        'Repeat Correction',...
                        'No', true);
                    if ~answer
                        return;
                    end
                end
            end
            
            if useFocusRadius
                this.refocusImages('gradient',useFocusRadius,'all');
            end
            
            for i=1:6
                dims(i) = size(this.correctedImages,i);
            end
            nFits = prod(dims(4:6));
            inputStack = reshape(this.correctedImages,[dims(1),dims(2),dims(3),nFits]);
            outputStack = [];
            
            bgImages = ones(dims(1),dims(2),'double');
            if useBGImage
                for i=1:dims(4)
                    bgImages(:,:,i) = double(this.bgImageMap(this.channels{i}));
                end
            end
            
            MDims = dims(3:6);
            
            parfor l = 1:nFits
                [~, chIndsTemp, ~, ~] = ind2sub(MDims, l);
                outputStack(:,:,:,l) = TIESolver(inputStack(:,:,:,l), 1, 4 ,...
                    outputFilepath, 'TIE', bgImages(:,:,chIndsTemp));
                disp(l);
            end
            outputStack = uint16(floor(65535*(outputStack-min(outputStack(:)))/(max(outputStack(:))-min(outputStack(:)))));
            this.correctedImages = reshape(outputStack, ...
                [dims(1),dims(2),size(outputStack,3),...
                dims(4:6)]);
            
            clear inputStack outputStack;
            
            if nargout
                varargout{1} = this.correctedImages;
            end
            
            % Append this correction to the list
            this.correctionList{end+1} = thisCorrection;
            
        end
        
        function [focusedImages , maxInd] = refocusNoStrings(this,stackIn)
            
            dims = zeros(6,1);
            for i=1:6
                if nargin > 1
                    dims(i) = size(stackIn,i);
                else
                    dims(i) = size(this.correctedImages,i);
                end
            end
            
            focusedImages = zeros(dims(1),dims(2),1,dims(4),dims(5),dims(6));
            maxInd = ones(dims(4), dims(5), dims(6));
            
            for i=1:dims(6)
                for j=1:dims(5)
                    for k=1:dims(4)
                        metricVec = zeros(dims(3),1);
                        normVec = metricVec;
                        for m=1:dims(3)
                            if nargin > 1
                                [~,~,gradImgX,gradImgY] = edge(squeeze(stackIn(:,:,m,k,j,i)));
                                metricVec(m) = sum(sum(gradImgX.^2 + gradImgY.^2));
                                normVec(m) = sum(sum(squeeze(stackIn(:,:,m,k,j,i))));
                            else
                                [~,~,gradImgX,gradImgY] = edge(squeeze(this.correctedImages(:,:,m,k,j,i)));
                                metricVec(m) = sum(sum(gradImgX.^2 + gradImgY.^2));
                                normVec(m) = sum(sum(squeeze(this.correctedImages(:,:,m,k,j,i))));
                            end
                            
                            
                        end
                        metricVec = metricVec./normVec;
                        maxInd(k,j,i) = find(metricVec == max(metricVec),1);
                        if nargin > 1
                            focusedImages(:,:,1,k,j,i) = stackIn(:,:,maxInd(k,j,i),k,j,i);
                        else
                            focusedImages(:,:,1,k,j,i) = this.correctedImages(:,:,maxInd(k,j,k),k,j,i);
                        end
                    end
                end
            end
        end
        
        % Method: alignImages produces a a new stack of images, each of
        % which is aligned via 2D cross-correlation along the time axis.
        % By default the first frame in the time series is used as the
        % template in the alignment.
        
        % By default, the method will not align data with multiple
        % z-slices. This is partly due to lengthy computation, but partly
        % due to the fact that out-of-focus images have little contrast
        % with which to align. There may cases where the entire stack
        % needs to be aligned, however. In this case, set the
        % forceStackAlignment flag to 'true'.
        
        % The 'useBestFocus' flag only applies if 'forceStackAlignment' is
        % true. 'useBestFocus' indicates that the stack alignment offsets
        % are calculated using the best focus data and applied to the rest
        % of the stack. If false, then the full alignment is performed on
        % every slice of the dataset separately.
        function alignImages(this, forceStackAlignment, useBestFocus)
            
            if nargin < 2
                forceStackAlignment = false;
            end
            if nargin < 3
                useBestFocus = true;
            end
            
            thisCorrection = 'Alignment';
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            end
            
            dims = size(this.correctedImages);
            stackExists = dims(3) > 1;
            
            if stackExists
                if forceStackAlignment
                    if useBestFocus
                        %                         focusedStack = this.refocusNoStrings();
                        % Need to write this
                    else
                        % Need to write this
                    end
                else
                    warning('Attempted to refocus an image stack. If this is desired, run this method with "forceStackAlignment" set to true.');
                    return;
                end
            else
                % Loop through the positions and channels and perform alignment
                for j=this.pInds
                    for k=this.chInds
                        thisStack = squeeze(this.correctedImages(:,:,1,k,j,:));
                        template = cropMovie(squeeze(this.correctedImages(:,:,1,k,j,1)));
                        %                         this.alignedImages = zeros([size(template,1), size(template,2),1,this.nPositions, this.nTimes]);
                        [~,~,thisStack] = imageCrossCorr(template,thisStack);
                        this.correctedImages(:,:,1,k,j,:) = reshape(thisStack,...
                            [dims(1),dims(2),1,1,1,this.nTimes]);
                    end
                end
            end
            this.correctionList{end+1} = thisCorrection;
        end
        
        function alignZStack(this,autoCrop)
            thisCorrection = 'ZStackAlignment';
            
            if nargin < 2
                autoCrop = false;
            end
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            end
            
            dims = size(this.correctedImages);
            stackExists = dims(3) > 1;
            
            if ~stackExists
                warning('No image stack present.');
                return;
            else
                % Loop through the positions and channels and perform alignment
                for l = this.tInds
                    for j=this.pInds
                        for k=this.chInds
                            thisStack = squeeze(this.correctedImages(:,:,:,k,j,l));
                            if autoCrop
                                template = squeeze(this.correctedImages(round(.3*dims(1)):round(.7*dims(1)), ...
                                    round(.3*dims(2)):round(.7*dims(2)),:,k,j,l));
                            else
                                template = cropMovie(squeeze(this.correctedImages(:,:,:,k,j,l)));
                            end
                            template = this.refocusNoStrings(template);
                            [~,~,thisStack] = imageCrossCorr(template,thisStack);
                            this.correctedImages(:,:,:,k,j,l) = reshape(thisStack,...
                                [dims(1),dims(2),dims(3),1,1,1]);
                        end
                    end
                end
            end
            this.correctionList{end+1} = thisCorrection;
        end
        
        function unloadCorrectedImages(this,assert)
            if nargin < 2
                assert = false;
            end
            
            answer = false;
            if ~assert
                answer = yesNoDialog( ...
                    'Are you sure you want to unload the correctedImages?',...
                    'Warning',...
                    'No', true);
            end
            if answer||assert
                this.correctedImages = [];
                this.correctionList = {};
            end
        end
        
        function setFlatFieldImage(this, channelName, refImagePath, useGrid)
            
            % Inputs:
            % - channelName is a string indicating the channel name.
            % - refImage is the reference image for the flat field
            % correction. If the image is a field of beads, set useGrid to
            % false. If it is a field of dye, set it to true
            % - useGrid is a flag indicating which method to use. If true,
            % it bins the image down to a coarser grid and then performs
            % the 2D poly fit. Otherwise, it performs peak-finding and
            % fitting on the beads.
            
            refImage = imread(refImagePath);
            
            this.flatField.computePolynomial(channelName, refImage, true, useGrid);
        end
        
        function setPSFPath(this, channelName, psfPath, psfDims, psfSpacing_um)
            
            this.deconv.setPSFPath(psfPath, channelName, this.presetMap(channelName), psfDims, psfSpacing_um)
        end
        
        function correctFlatField(this)
            
            % Performs flatfield correction on the images and stores them
            % in the correctedImages property.
            
            % If the images are not loaded then they
            % are loaded automatically.
            
            thisCorrection = 'FlatField';
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            %Populate explicitly to ensure dims has 5 elements (singleton
            %dimensions would otherwise result in a smaller dims vec)
            dims(1) = size(this.images,1);
            dims(2) = size(this.images,2);
            dims(3) = size(this.images,3);
            dims(4) = size(this.images,4);
            dims(5) = size(this.images,5);
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages == 0)
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            end
            
            % Flat field correction
            if ffFlag
                chCount = 0;
                for i=dims(4)
                    disp(['Performing flat field corrections for ' this.channels{this.chInds(i)}]);
                    chCount = chCount + 1;
                    tempStack = this.flatField.correctImage(this.correctedImages(:,:,:,i,:), this.channels{this.chInds(i)}, this.presetMap(this.channels{this.chInds(i)}));
                    this.correctedImages(:,:,:,chCount,:) = reshape(tempStack,...
                        [dims(1),dims(2),dims(3), 1, dims(5)]);
                end
            end
            this.correctionList{end+1} = thisCorrection;
        end
        
        function tform = registerChannels(this, fixedChannelInd, tform)
            % Registers all the images to one channel by performing an
            % affine transformation to rotate, scale, and translate all the
            % images from all the channels to register with the selected
            % fixed channel specified by 'fixedChannelInd'.
            
            % Inputs:
            % fixedChannelInd: numerical index to the channel number that
            % remains fixed.
            
            % tform: Optionally pass in an existing transformation
  
            
            thisCorrection = 'channelRegistration';
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed. Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages) == 0
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            end
            
            if nargin < 3
                % User did not supply the tforms, so discover them
                % Create the optimizer
                [optimizer, metric] = imregconfig('multimodal');
                
                optimizer.InitialRadius = 0.002;
                % Generate an affine transformation than can transform each of
                % the other channels back to the fixed one. We use the central
                % z-slice of the stack for this estimate.
                dims = zeros(6,1);
                for i=1:6
                    dims(i) = size(this.correctedImages,i);
                end
                
                for i=this.chInds
                    tform{i} = imregtform(this.correctedImages(:,:,round(mean(dims(3))), i,1,1), ...
                        this.correctedImages(:,:,round(mean(dims(3))), fixedChannelInd,1,1),'affine',optimizer,metric);
                end
            end
            
            % Loop through the positions and channels and perform affine
            % transform registration
            for i = 1:dims(3)
                for j = 1:dims(4)
                    for k = 1:dims(5)
                        for l = 1:dims(6)
                            this.correctedImages(:,:,i,j,k,l) = imwarp(this.correctedImages(:,:,i,j,k,l),tform{j},'OutputView',imref2d(this.frameDims));
                        end
                    end
                end
            end

            this.correctionList{end+1} = thisCorrection;
        end
        
        function performDeconvolution(this)
            
            % Performs deconvolution on the images and stores them
            % in the correctedImages property.
            
            % If the images are not loaded then they
            % are loaded automatically.
            
            thisCorrection = 'Deconvolution';
            
            % Check if this correction has already been done
            if ismember(thisCorrection, this.correctionList)
                answer = yesNoDialog( ...
                    [thisCorrection ' has already been performed.  Are you sure you want to repeat it?'],...
                    'Repeat Correction',...
                    'No', true);
                if ~answer
                    return;
                end
            end
            
            if ~this.imagesLoaded
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            %Populate explicitly to ensure dims has 5 elements (singleton
            %dimensions would otherwise result in a smaller dims vec)
            dims(1) = size(this.images,1);
            dims(2) = size(this.images,2);
            dims(3) = size(this.images,3);
            dims(4) = size(this.images,4);
            dims(5) = size(this.images,5);
            
            % Allocate the correctedImages array if it has not been
            % created already.
            if numel(this.correctedImages == 0)
                try
                    this.correctedImages = this.images;
                catch
                    warning('Could not initialize the correctedImages array.');
                    return;
                end
            end
            
            % edgeTaperFlag is an optional input to deconvolution, applying
            % a smoothing filter to the edges of the image volume to avoid
            % ringing artifacts in the deconv.
            
            % Default edgeTaperFlag is true
            edgeTaperFlag = true;
            
            % Deconvolution
            chCount = 0;
            for i=1:dims(4)
                chCount = chCount + 1;
                % The basic unit for input into the deconvolution is a
                % z-stack, ie. channels and time points need to be run
                % separately.
                tCount = 0;
                for j = 1:dims(5)
                    tCount = tCount + 1;
                    disp(['Performing deconvolution for ' this.channels{this.chInds(i)}, ', time point ' num2str(tCount)]);
                    tempStack = squeeze(this.correctedImages(:,:,:,chCount,tCount));
                    
                    % Correct the image stack
                    tempStack = this.deconv.correctImage(tempStack, this.channels{this.chInds(i)}, this.z_step_um, this.presetMap(this.channels{this.chInds(i)}), edgeTaperFlag);
                    this.correctedImages(:,:,:,chCount,tCount) = reshape(tempStack,...
                        [dims(1),dims(2),dims(3), 1, 1]);
                end
            end
            this.correctionList{end+1} = thisCorrection;
        end
        
        function makePSFOverlay(this, nSpots, intensity)
            
            if strcmp(this.mmStack.imagesLoaded,'None')
                disp('No images loaded. Loading images...');
                this.loadImages();
            end
            
            %Populate explicitly to ensure dims has 5 elements (singleton
            %dimensions would otherwise result in a smaller dims vec)
            dims(1) = size(this.mmStack.images,1);
            dims(2) = size(this.mmStack.images,2);
            dims(3) = size(this.mmStack.images,3);
            dims(4) = size(this.mmStack.images,4);
            dims(5) = size(this.mmStack.images,5);
            
            % Initialize the imgOut array
            this.simImages = double(zeros(dims));
            this.psfCoords = cell(dims(4), dims(5));
            
            chCount = 0;
            for i=1:dims(4)
                chCount = chCount + 1;
                tCount = 0;
                
                for j = 1:dims(5)
                    tCount = tCount + 1;
                    disp(['Performing psf overlay for ' this.channels{this.chInds(i)}, ', time point ' num2str(tCount)]);
                    
                    tempStack = squeeze(this.mmStack.images(:,:,:,chCount,tCount));
                    
                    % Correct the image stack
                    [tempStack, this.psfCoords{chCount, tCount}]= this.deconv.makePSFOverlay(tempStack, this.channels{this.chInds(i)}, this.z_step_um, this.presetMap(this.channels{this.chInds(i)}), nSpots, intensity);
                    this.simImages(:,:,:,chCount,tCount) = reshape(tempStack,...
                        [dims(1),dims(2),dims(3), 1, 1]);
                end
            end
            
            
        end
        
        function displayImages(this)
            % Idea is to create an Imagej like GUI to
            % browse the image data or a subset of it.
            if ishandle(this.mainHandle)
                delete(this.mainHandle)
            end
            % Upgrade this to virtual stack in the future?
            if ~this.imagesLoaded
                this.loadImages();
            end
            
            this.mainHandle = open('MDImage.fig');
            children = this.mainHandle.Children;
            
            % Load all the graphics handles
            for i=1:numel(children)
                this.(children(i).Tag) = this.mainHandle.findobj('tag',children(i).Tag);
            end
            
            this.albumPreviewData = imagesc(this.albumAxes, zeros(this.frameDims));
            colormap(this.albumAxes, 'gray');
            set(this.albumAxes, 'XTick',[]);
            set(this.albumAxes, 'YTick',[]);
            set(this.albumAxes, 'XTickLabel',[]);
            set(this.albumAxes, 'YTickLabel',[]);
            axis(this.albumAxes, 'image');
            
            % Set current slices/times/channels to 1
            this.currentTime = 1;
            this.currentChannel = 1;
            this.currentSlice = 1;
            this.currentPosition = 1;
            
            % Set album callbacks
            set(this.timeSlider, 'Callback',@this.timeSlider_Callback);
            set(this.channelSlider, 'Callback',@this.channelSlider_Callback);
            set(this.sliceSlider, 'Callback',@this.sliceSlider_Callback);
            set(this.positionSlider, 'Callback',@this.positionSlider_Callback);
            set(this.dispCorrList, 'Callback', @this.dispCorrList_Callback);
            set(this.zoomInButton, 'OnCallback',@this.zoomIn_OnCallback);
            set(this.zoomInButton, 'OffCallback',@this.zoomIn_OffCallback);
            set(this.zoomOutButton, 'OnCallback',@this.zoomOut_OnCallback);
            set(this.zoomOutButton, 'OffCallback',@this.zoomOut_OffCallback);
            set(this.mipDisplayButton, 'Callback',@this.mipDisplayButton_Callback);
            set(this.markerOverlayButton, 'Callback',@this.markerOverlayButton_Callback);
            
            labelList = {'Raw'};
            if ~isempty(this.correctedImages)
                labelList{end+1} = 'Corrected';
            end
            if ~isempty(this.simImages)
                labelList{end+1} = 'Simulated';
            end
            
            set(this.dispCorrList, 'String', labelList);
            
            this.updateGUI();
            
        end
        
        function timeSlider_Callback(this,~,~)
            this.currentTime = max(1,round(get(this.timeSlider,'Value')));
            this.updateGUI();
        end
        
        function channelSlider_Callback(this,~,~)
            this.currentChannel = max(1,round(get(this.channelSlider,'Value')));
            this.updateGUI();
        end
        
        function sliceSlider_Callback(this,~,~)
            this.currentSlice = max(1,round(get(this.sliceSlider,'Value')));
            this.updateGUI();
        end
        
        function positionSlider_Callback(this,~,~)
            this.currentPosition = max(1,round(get(this.positionSlider,'Value')));
            this.updateGUI();
        end
        
        function dispCorrList_Callback(this,~,~)
            this.updateGUI();
        end
        
        function zoomIn_OnCallback(this,~,~)
            zoom(this.albumAxes, 'on');
        end
        
        function zoomIn_OffCallback(this,~,~)
            zoom(this.albumAxes, 'off');
        end
        
        function zoomOut_OnCallback(this,~,~)
            zoom(this.albumAxes, 'out');
        end
        
        function zoomOut_OffCallback(this,~,~)
            zoom(this.albumAxes, 'off');
        end
        
        function mipDisplayButton_Callback(this,~,~)
            this.updateGUI();
        end
        
        function markerOverlayButton_Callback(this,~,~)
            this.updateGUI();
        end
        
        % Verify that the given indices are valid for this object. If so,
        % return them back and
        function [slices, channels, positions, times] = checkIndices(this, slices, channels, positions, times)
            if (nargin > 1) && ~(isempty(slices))
                if  sum((slices > 0)&(slices <= numel(this.MDParams.zStackVec_um))) == numel(slices)
                    if all(round(slices) == slices)
                        this.slInds = slices;
                    else
                        this.slInds = 1:this.nSlices;
                        slices = this.slInds;
                    end
                else
                    this.slInds = 1:this.nSlices;
                    slices = this.slInds;
                end
            else
                this.slInds = 1:this.nSlices;
                slices = this.slInds;
            end
            
            if (nargin > 2) && ~(isempty(channels))
                if  sum((channels > 0)&(channels <=  numel(this.MDParams.channels))) == numel(channels)
                    if all(round(channels) == channels)
                        this.chInds = channels;
                    else
                        this.chInds = 1:this.nChannels;
                        channels = this.chInds;
                    end
                    
                else
                    this.chInds = 1:this.nChannels;
                    channels = this.chInds;
                end
                
            else
                this.chInds = 1:this.nChannels;
                channels = this.chInds;
            end
            
            if (nargin > 3) && ~(isempty(positions))
                if  sum((positions > 0)&(positions <=  numel(this.MDParams.positions_um))) == numel(positions)
                    if all(round(positions) == positions)
                        this.pInds = positions;
                    else
                        error('Positions indices must be integers!');
                    end
                    
                else
                    error('Positions index argument is outside the allowed range');
                end
                
            else
                this.pInds = 1:this.nPositions;
                positions = this.pInds;
            end
            
            if (nargin > 4) && ~(isempty(times))
                if  sum((times > 0)&(times <=  numel(this.MDParams.timeVec_s))) == numel(times)
                    if all(round(times) == times)
                        this.tInds = times;
                    else
                        error('times indices must be integers!');
                    end
                else
                    error('time index argument is outside the allowed range');
                end
                
            else
                this.tInds = 1:this.nTimes;
                times = this.tInds;
            end
            
            this.nSlices = numel(this.slInds);
            this.nChannels = numel(this.chInds);
            this.nPositions = numel(this.pInds);
            this.nTimes = numel(this.tInds);
            this.nImages = this.nSlices*this.nChannels*this.nPositions*this.nTimes;
            
        end
        
        function writeToAvi(this,dimension, correctedFlag, pathToSave, frameRate)
            
            this.displayImages();
            
            if nargin < 3 || isempty(correctedFlag)
                correctedFlag = false;
            end
            
            if nargin < 4 || isempty(pathToSave)
                pathToSave = this.filepath;
            end
            if nargin < 5 || isempty(frameRate)
                frameRate = 30;
            end
            
            if correctedFlag
                dispStrings = get(this.dispCorrList,'String');
                ind = strfind(dispStrings,'Corrected');
                for i=1:numel(ind)
                    if ind{i}
                        ind2 = i;
                    end
                end
                if exist('ind2','var')
                    set(this.dispCorrList,'Value',ind2);
                else
                    error('Corrected Images not present');
                end
            end
            
            v = VideoWriter(fullfile(pathToSave, [this.filePrefix, '_vidExport.avi']),'Uncompressed AVI');
            v.FrameRate = frameRate;
            open(v);
            
            for i = 1:size(this.images,dimension)
                switch dimension
                    case 3
                        this.currentSlice = i;
                    case 4
                        this.currentChannel = i;
                    case 5
                        this.currentPosition = i;
                    case 6
                        this.currentTime = i;
                end
                this.updateGUI;
                frame = getframe(this.albumAxes);
                writeVideo(v,frame);
            end
            
            close(v);
            
        end
        
        % Refresh all the GUI fields
        function updateGUI(this)
            if strcmp(get(this.mainHandle, 'visible'),'on')
                
                value = get(this.dispCorrList,'Value');
                dispStrings = get(this.dispCorrList,'String');
                displayChoice = dispStrings{value};
                
                switch displayChoice
                    case 'Raw'
                        maxSlices = this.nSlices;
                        maxChannels = this.nChannels;
                        maxPositions = this.nPositions;                        
                        maxTimes = this.nTimes;
                    case 'Corrected'
                        maxSlices = size(this.correctedImages, 3);
                        maxChannels = size(this.correctedImages, 4);
                        maxPositions = size(this.correctedImages, 5);
                        maxTimes = size(this.correctedImages, 6);
                end
                
                % Update time slider
                if maxTimes == 1
                    set(this.timeSlider,'Max',1);
                    set(this.timeSlider, 'Value', 1);
                    set(this.timeSlider,'Min',1);
                    set(this.timeSlider,'SliderStep',[0,0]);
                else
                    set(this.timeSlider,'Max',maxTimes);
                    set(this.timeSlider, 'Value', this.currentTime);
                    set(this.timeSlider,'Min',1);
                    set(this.timeSlider,'SliderStep',[1/maxTimes, 1]);
                    set(this.currentTimeText, 'String', [ num2str(this.currentTime) '/' num2str(maxTimes)]);
                end
                
                % Update channel slider
                if maxChannels ==1
                    set(this.channelSlider,'Max',1);
                    set(this.channelSlider, 'Value', 1);
                    set(this.channelSlider,'Min',1);
                    set(this.channelSlider,'SliderStep',[0,0]);
                else
                    set(this.channelSlider,'Max', maxChannels);
                    set(this.channelSlider, 'Value', this.currentChannel);
                    set(this.channelSlider,'Min',1);
                    set(this.channelSlider,'SliderStep',[1/maxChannels, 1]);
                    set(this.currentChText, 'String', [ num2str(this.currentChannel) '/' num2str(maxChannels)]);
                end
                
                % Update slice slider
                if maxSlices == 1
                    set(this.sliceSlider,'Max',1);
                    set(this.sliceSlider, 'Value', 1);
                    set(this.sliceSlider,'Min',1);
                    set(this.sliceSlider,'SliderStep',[0,0]);
                else
                    set(this.sliceSlider,'Max',maxSlices);
                    set(this.sliceSlider, 'Value', this.currentSlice);
                    set(this.sliceSlider,'Min',1);
                    set(this.sliceSlider,'SliderStep',[1/maxSlices, 1]);
                    set(this.currentSliceText, 'String', [ num2str(this.currentSlice) '/' num2str(maxSlices)]);
                    
                end
                
                % Update position slider
                if maxPositions == 1
                    set(this.positionSlider,'Max',1);
                    set(this.positionSlider, 'Value', 1);
                    set(this.positionSlider,'Min',1);
                    set(this.positionSlider,'SliderStep',[0,0]);
                else
                    set(this.positionSlider,'Max',maxPositions);
                    set(this.positionSlider, 'Value', this.currentPosition);
                    set(this.positionSlider,'Min',1);
                    set(this.positionSlider,'SliderStep',[1/maxPositions, 1]);
                    set(this.currentPositionText, 'String', [ num2str(this.currentPosition) '/' num2str(maxPositions)]);
                    
                end
                
                
                switch displayChoice
                    case 'Raw' % Display raw data
                        if get(this.mipDisplayButton, 'Value')
                            delete(this.markerOverlay);
                            this.albumPreviewData.CData = max(squeeze(this.images(:,:,:, this.currentChannel, this.currentPosition, this.currentTime)),[],3);
                            this.reScaleAxes();
                            delete(this.markerOverlay);
                        else
                            this.albumPreviewData.CData = squeeze(this.images(:,:,this.currentSlice, this.currentChannel, this.currentPosition, this.currentTime));
                        end
                        this.reScaleAxes();
                        
                    case 'Corrected' % Display corrected data
                        this.currentSlice = min(size(this.correctedImages,3),this.currentSlice);
                        this.currentChannel = min(size(this.correctedImages,4),this.currentChannel);
                        this.currentPosition = min(size(this.correctedImages,5),this.currentPosition);
                        this.currentTime = min(size(this.correctedImages,6),this.currentTime);
                        
                        if get(this.mipDisplayButton, 'Value')
                            delete(this.markerOverlay);
                            this.albumPreviewData.CData = max(squeeze(this.correctedImages(:,:,:, this.currentChannel, this.currentPosition, this.currentTime)),[],3);
                        else
                            delete(this.markerOverlay);
                            this.albumPreviewData.CData = squeeze(this.correctedImages(:,:,this.currentSlice, this.currentChannel,this.currentPosition, this.currentTime));
                        end
                        
                        this.reScaleAxes();
                        
                    case 'Simulated' % Display overlay of corrected data with raw
                        if get(this.mipDisplayButton, 'Value')
                            delete(this.markerOverlay);
                            this.albumPreviewData.CData = max(squeeze(this.simImages(:,:,:, this.currentChannel, this.currentPosition, this.currentTime)),[],3);
                            
                            if get(this.markerOverlayButton, 'Value')
                                hold on;
                                this.markerOverlay = plot(this.psfCoords{this.currentChannel, this.currentTime}(:,2), this.psfCoords{this.currentChannel, this.currentTime}(:,1), 'ro');
                                hold off;
                            end
                            
                            
                        else
                            delete(this.markerOverlay);
                            this.albumPreviewData.CData = squeeze(this.simImages(:,:,this.currentSlice, this.currentChannel, this.currentTime));
                            this.reScaleAxes();
                            if get(this.markerOverlayButton, 'Value')
                                hold on;
                                this.markerOverlay = plot(this.psfCoords{this.currentChannel, this.currentTime}(:,2), this.psfCoords{this.currentChannel, this.currentTime}(:,1), 'ro');
                                hold off;
                            end
                        end
                end
            end
        end
        
        function reScaleAxes(this)
            [a,xout] = imhist(this.albumPreviewData.CData,100);
            cs = cumsum(a);
            cs = cs/max(cs(:));
            i1 = find(cs > this.scaleLowerBound,1);
            i2 = find(cs > this.scaleUpperBound,1);
            v1 = xout(i1);
            v2 = xout(i2);
            
            % Ensure the display always has a valid range
            if ~(v2 > v1)
                v2 = v1+1;
            end
            
            this.albumAxes.CLim = [v1,v2];
        end
        
        %*************************************************************
        % Helper method for saving this correction to disk
        function S = saveobj(this)
            for fld = this.fieldsToSave
                S.(fld{1}) = this.(fld{1});
            end
        end
        
    end
    
    methods (Static)
        %*************************************************************
        % Helper method for loading this correction from disk
        function obj = loadobj(S)
            obj = MDImage(S.frameDims, S.MDParams, S.presetMap, S.fileOrder, S.isOldManualAlbum);
            obj.setFilePath(S.filepath, S.filePrefix);
            %             obj.create
        end
    end
    
end


