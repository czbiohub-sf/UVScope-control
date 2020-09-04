classdef MDEngine < handle
    % The MDEngine class's role is to serve as a state machine to
    % orchestrate the acquisition of a multi-dimensional dataset from a
    % microscope. In the intended implementation, an instance of this class
    % would be a property of the microscope class. The microscope might
    % use a GUI or some other format to configure the acquisition, which is
    % summarized in the input parameter MDParams. This class receives the
    % MDParams and accordingly:
    % - Generates an MDImage object to store the data
    % - Generates .JSON metadata files to store acquisition parameters
    % - Displays a state to the microscope:
    % - 'Idle' : No acquisition is in progress
    % - 'FrameRequest':
    % - 'Waiting':
    
    % Paul Lebel
    % czbiohub
    % 2018/09/24
    
    
    properties(GetAccess = public, SetAccess = private)
        MDParams
        MDImage
        frameDims
        nChannels
        nSlices
        nTimes
        nPositions
        nImages % Total number of image frames in the MD acquisition
        requestedChannel % specific channel that is being requested from the scope
        requestedPosition_um
        requestedZStackDelta_um
        mdImage % MDImage object which we feed images to
        fInd % Linear index to the current slice being acquired
        acquisitionOrder
        universalFields
        state
        channels
        slInds
        chInds
        pInds
        tInds
        startTime_s
        filepath
        zStackBuffer
        focusOffset_um = 0;
    end
    
    properties(Access = public)
        trackFocusFlag = false
    end
    
    
    properties(Access = private)
        metadata
        presetMap
        stateList = {'Idle','Waiting','FrameRequest','Busy'};
        secondsPerDay = 86400
    end
    
    methods(Access = public)
        
        function this = MDEngine(MDParams)
            % Class constructor
            % Input arguments:
            % MDParams: struct containing the following fields:
            % - positions_um (nx3 element array of positions. Each row is a
            %   vector: [x_um,y_um,z_um]
            % - zStackVec_um (Vector of relative zStack positions. Ex. [-20:5:20])
            % - timeVec_s (vector of delay times)
            % - channels (Cell array of preset channel names which are used
            % in this acquisition - these each need to be keys to the presetMap
            % variable)
            % - frameDims (two-element vector of single frame dimensions)
            % - acquisitionOrder (A string describing the acquisition
            %   order.
            %   For example:
            %       'ZCXYT': Z-stack is performed first, then
            %       change presets(channels) and repeat, then move to a new
            %       position, repeat.
            
            %       'CZXYT': Do a zStack but at each z position first cycle
            %       through all channels before stepping z. Then go to a new XY
            %       position, then repeat that whole thing over time.
            
            %       'TCZXY': Do a time series, then repeat for each
            %       channel. Step Z, repeat. Move to a new XY position,
            %       repeat.
            
            %       'T': Just do a time series.
            
            %       Note: Any one dimension can be a singleton, ie. if you
            %       don't want a time series just set the number of times
            %       to 1.
            
            % presetMap (map object whose keys are the names of the
            % preset channels and whose values are structs defining
            % instrument parameters for acquisition
            
            
            if (size(MDParams.positions_um,2) ~=3)
                errordlg('Position array must have three columns');
                return;
            end
            
            if numel(MDParams.frameDims) ~= 2
                errordlg('MDParams.frameDims must have two elements');
                return;
            end
            
            
            % Unpack MDParams for convenience
            this.filepath = MDParams.filepath;
            this.presetMap = MDParams.presetMap;
            this.MDParams = MDParams;
            this.acquisitionOrder = MDParams.acquisitionOrder;
            this.frameDims = MDParams.frameDims;
            this.nPositions = max(1,size(MDParams.positions_um,1));
            this.nChannels = max(1,numel(MDParams.channels));
            this.nSlices = max(1,numel(MDParams.zStackVec_um));
            this.nTimes = max(1,numel(MDParams.timeVec_s));
            this.nImages = this.nPositions*this.nChannels*this.nSlices*this.nTimes;
            this.universalFields = fields(this.presetMap(MDParams.channels{1}));
            this.MDImage = MDImage(this.MDParams.frameDims,this.MDParams, this.presetMap);
            this.MDImage.setFilePath(this.MDParams.filepath, this.MDParams.filePrefix);
            this.channels = MDParams.channels;

            [slInds, chInds, pInds, tInds] = getSubscripts(this, 1:this.nImages);
            this.slInds = max(slInds,1);
            this.chInds = max(chInds,1);
            this.pInds = max(pInds,1);
            this.tInds = max(tInds,1);
            this.changeState('Idle');
        end
        
        function run(this)
            this.fInd = 1;
            this.requestedChannel = this.channels{this.chInds(this.fInd)};
            
            % Add the zStackVec_um value to the position vector
            this.requestedPosition_um = this.MDParams.positions_um(1,:) + ...
                [0,0,this.MDParams.zStackVec_um(1)];
            this.startTime_s = now()*this.secondsPerDay;
            this.changeState('FrameRequest');
        end
        
        function addNextImage(this, image)
            
            this.changeState('Busy');
            this.updateMetadata(this.fInd);
           
            % Update the MDImage object (this object stores images in
            % memory, disk, or both). 
            this.MDImage.inputImages(image, this.metadata, false, 'tiff');
            
            % Save MDImage
            try
                tempImage = this.MDImage; 
                save(fullfile(this.filepath, [this.MDParams.filePrefix, '_MDImage.mat']),'tempImage');
            catch ME
                error('Could not save MDImage');
            end
            
            % Linear frame index
            this.fInd = this.fInd+1;

            % Check if a new image is needed            
            if this.fInd <= this.nImages
                
                % Get the next channel
                this.requestedChannel = this.channels{this.chInds(this.fInd)};
                
                % Get the next position (z value is center of z-stack, if
                % applicable)
                this.requestedPosition_um = this.MDParams.positions_um(...
                    this.pInds(this.fInd),:);
                
                % Get the static z-stack offset
                this.requestedZStackDelta_um = this.MDParams.zStackVec_um(this.slInds(this.fInd));
                
                % If time is up, then request a frame
                if checkElapsedTime(this)
                    this.changeState('FrameRequest');
                else
                    this.changeState('Waiting');
                end
                
            else
                this.changeState('Idle');
            end
            
        end
        
        function trackFocus(this)
            
            % This method is called once a zStack is completed, if the
            % trackFocusFlag is set to true. The method computes the most
            % in-focus slice according to maximizing edge contrast by means 
            % of the Sobel operator. 
            
            % The best focus is computed on a class property called
            % zStackBuffer, which holds a buffer of frames containing the
            % most recent zStack.
            
            deltaZ = this.MDParams.zStackVec_um(2) - this.MDParams.zStackVec_um(1);
            
            stdVec = zeros(size(this.zStackBuffer,3));
            
            for i=1:size(this.zStackBuffer,3)
                frame = this.zStackBuffer(:,:,i);
                [~,~,gradX,gradY] = edge(frame, 'Sobel');
                stdVec(i) = sum(sum(gradX.^2 + gradY.^2))/(mean(double(frame(:))));
            end
            
            middleSlice = ceil(this.nSlices/2);
            
            % focusOffset_um tracks overall focal drift by cumulatively
            % adding focal offset errors over time
            this.focusOffset_um = this.focusOffset_um + ...
                deltaZ*(find(stdVec == max(stdVec)) - middleSlice);
        end
        
        function state = returnState(this)
            state = this.state;
        end
        
        function timeUp = checkElapsedTime(this)
            % Elapsed time (seconds) since last frame
            et_s = this.secondsPerDay*(now()) - this.startTime_s -...
                this.metadata(this.fInd-1).time_s;
            
            % Requested elapsed time
            etr_s = (this.MDParams.timeVec_s(this.tInds(this.fInd)) -...
                this.MDParams.timeVec_s(this.tInds(this.fInd-1)));
            
            timeUp = et_s >= etr_s;
        end
        
        function changeState(this, state)
            if ismember(state, this.stateList)
                this.state = state;
                disp(state);
            end
        end
        
        function [slInds, chInds, pInds, tInds] = getSubscripts(this, linearInds)
            % Returns the slice, channel, position, and time indices given
            % a linear index (ie. absolute frame number)
            
            nc = max(this.nChannels,1);
            nt = max(this.nTimes,1);
            ns = max(this.nSlices,1);
            np = max(this.nPositions,1);
            
            switch this.acquisitionOrder
                case 'ZCXYT'
                    [slInds,chInds,pInds,tInds] = ind2sub([ns,nc,np,nt], linearInds);
                case 'CZXYT'
                    [chInds,slInds,pInds,tInds] = ind2sub([nc,ns,np,nt], linearInds);
                case 'TCZXY'
                    [tInds,chInds,slInds,pInds] = ind2sub([nt,nc,ns,np], linearInds);
                case 'T'
                    [tInds,chInds,slInds,pInds] = ind2sub([nt,nc,np,ns], linearInds);
            end
            
        end
        
        function updateMetadata(this,inds)
            for i = inds
                md = this.presetMap(this.channels{this.chInds(i)});
                md.frameDims = this.MDParams.frameDims;
                md.channelNumber = this.chInds(i);
                md.channel = this.channels{this.chInds(i)};
                md.positionNumber = this.pInds(i);
                md.position = this.MDParams.positions_um(this.pInds(i),:);
                md.sliceNumber = this.slInds(i);
                md.slice_um = this.MDParams.zStackVec_um(this.slInds(i));
                md.timeNumber = this.tInds(i);
                md.time_s = (now()*this.secondsPerDay-this.startTime_s);
                if isempty(this.metadata)
                    this.metadata = md;
                else
                    this.metadata(i) = md;
                end
            end
        end
    end
end