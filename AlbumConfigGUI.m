classdef AlbumConfigGUI < handle
    % Very simple GUI class to receive user input on the configuration of a
    % manually acquired image album.
    % Paul Lebel
    % czbiohub
    
    properties (Access = public)
        mainHandle
        presetMap
        nChannels
        nChannelsPopup
        channelPopups = {'channel1Popup',...
            'channel2Popup', 'channel3Popup',...
            'channel4Popup', 'channel5Popup'};
        OKButton
        selectedChannels
        settingsConfirmed = false;
    end
    
    properties (Access = private)
        nTotalChannels = 5; 
    end
    
    
    methods (Access = public)
        
        % Constructor
        function this = AlbumConfigGUI(presetMap)
            this.presetMap = presetMap;
            this.mainHandle = open('AlbumConfigGUI.fig');
            
            % Assign figure handles
            this.nChannelsPopup = this.mainHandle.findobj('tag','nChannelsPopup');
            this.OKButton = this.mainHandle.findobj('tag','OKButton');
            for i=1:this.nTotalChannels
                % Grab all the figure handles
                this.channelPopups{i} = this.mainHandle.findobj('tag',this.channelPopups{i});
                % Set the strings
                set(this.channelPopups{i}, 'String', this.presetMap.keys);
            end
            
            % Set options for number of channels
            numString = cell(this.nTotalChannels,1);
            for i=1:this.nTotalChannels
                numString{i} = num2str(i);
            end
            
            set(this.nChannelsPopup, 'String', numString);
            set(this.nChannelsPopup, 'Value',1);
            this.nChannels = 1;
            
            this.enablePopups();
            
            % Set callbacks
            set(this.OKButton,'Callback',@this.settingsOK_Callback);
            set(this.nChannelsPopup,'Callback',@this.nChannelsPopup_Callback);
            
        end
        
        % Grays out popups depending on how many channels are selected
        function enablePopups(this)
            for i=1:this.nTotalChannels
                if i <= this.nChannels
                    set(this.channelPopups{i},'Visible','On');
                else
                    set(this.channelPopups{i},'Visible','Off');
                end
            end  
        end
        
        % OKButton was pushed
        function settingsOK_Callback(this, ~, ~)
            this.settingsConfirmed = true; 
        end
        
        % Read in the nChannels parameter
        function nChannelsPopup_Callback(this, ~, ~)
            tempVal = get(this.nChannelsPopup,'Value');
            tempStrings = get(this.nChannelsPopup,'String');
            this.nChannels = str2double(tempStrings{tempVal});
            this.enablePopups();
        end
        
        function selectedChannels = getAlbumSettings(this)
            
            % Wait for the OKButton to be pushed then read all the settings
            while((this.settingsConfirmed == false) && ishandle(this.mainHandle))
                pause(.01);
            end
            
            if ~ishandle(this.mainHandle)
                selectedChannels = {};
                return;
            end
            
            selectedChannels = cell(this.nChannels,1);
            for i=1:this.nChannels
                tempVal = get(this.channelPopups{i}, 'Value');
                tempStrings = get(this.channelPopups{i},'String');
                selectedChannels{i} = tempStrings{tempVal};
            end

        end
        
        function delete(this)
            delete(this.mainHandle);
        end
 
        
    end
    
end

