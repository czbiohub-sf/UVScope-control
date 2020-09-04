% The MultiLED class is built to control the multiplexed illumination setup
% for the Deep UV microscope at biohub. This class is derived from the
% LJackUD class used to control a labjack device. Here, we use the LJ to
% provide three digital bits and one analog signal. The three digital bits
% control a small relay-based analog multiplexer set up such that a
% Thorlabs LEDD1B LED driver produces a current which the board receives as
% input. Two digital bits control which of the four LEDs receive the
% current, and the third digital bit acts as a global on/off. Finally, the
% analog output modulates the magnitude of the current produced by LEDD1B.
% In this way, we can multiplex four LEDs onto one LED driver.

% A key part of this class is that it contains the current limit data for
% each of the LEDs, which all have different Imax values.



% As connected 2018.01.23, Labjack U6 terminals:
% 'EIO0' controls 'power' or global on/off
% 'EIO1' controls R1
% 'EIO2' controls R2
% 'DAC0' controls analog modulation (0-5 volts)
% 'EI03' controls TTL enable for the exacte lamp

% Our custom relay box transforms as follows (R1, R2, Power)
% '000' powers NONE
% '001' powers output 1
% '101' powers output 2
% '011' powers output 3
% '111' powers output 4

% Therefore:
% 'Power' is channel 8
% 'R1' is channel 9
% 'R2' is channel 10

% Author: Paul Lebel
% czbiohub
% 2018

classdef MultiLED < handle
    
    %==========================================================================
    %
    %   READ ONLY PROPERTIES
    %
    %==========================================================================
    properties (GetAccess = public, SetAccess = protected)
        % Cell array of strings, containing the Thorlabs LED models which
        % are connected to the relay multiplexer's outputs
        connectedLEDs
        
        % Map of TTL-triggered device names to their respective channels
        TTLDevices
        activeTTL
        
        % Current limits (mA) of the connected LEDs. These are just
        % specific values pulled out of the (immutable) maxCurrentsMap
        connectedLEDLimits
        
        % Defines which LJ channels are being used to control the
        % multiplexer, and must be a cell array of strings listing the
        % channels in the following order:
        % "R1", "R2", "Power", and "Vcontrol"
        % where the first three must be DIO channels and the last is a DAC
        % channel
        connectedLJChannels
        
        % Maximum current setting of the LED driver. On Thorlabs LEDD1B
        % it's the value indicated on the trimpot at the rear of the
        % device. Default assumed setting is the max for that device.
        sourceCurrentLimit_mA = 1200;
        
        % String descriptor of which LED is currently active
        activeLED = 'NONE';
        
        % Stores the percent of the max current being driven
        activeLEDPercent = 0;
        
        % Stores the active LED's max current
        activeLEDMaxCurrent_mA = 0;
        
        % Stores the analog control voltage corresponding to the percent
        % power of the active LED
        activeLEDControlVoltage = 0;
        
        % Lists the status of R1, R2, and Power relays
        digitalBits = [0,0,0];
        
        % Value is updated from the superclass
        supportedDevices
        
        % Flag to indicated simulated device
        virtual
    end
    
    %==========================================================================
    %
    %   PRIVATE, IMMUTABLE PROPERTIES
    %
    %==========================================================================
    properties (GetAccess = private, SetAccess = immutable)
        
        % LJackUD class object controlling the LabJack
        labjack
        
        % This is the max modulation input voltage of the LED driver. For
        % Thorlabs LEDD1B it's 5V
        dacModRange = 5;
        
        % List of supported LEDs
        ledList
        
        % List of LED current limits. This is set in the constructor
        ledLimits
        
        % Mapping of ledList to ledLimits
        maxCurrentsMap
        
        % Map of the desired multiplexer port number to the digital values
        % required to set it.
        relayPortMapping
        
        %         % Labjack models supported
        %         supportedDevices
        
    end % properties (GetAccess = private, SetAccess = immutable)
    
    
    %==========================================================================
    %
    %   PUBLIC METHODS
    %
    %==========================================================================
    methods (Access = public)
        
        % Class constructor
        function this = MultiLED(labjack, connectedLEDs, connectedLJChannels,TTLDevices)
            
            % Inputs:
            % "LJType" is the LabJack device type, is passed to the
            % parent class, and must be a supported device
            
            % "connectedLEDs" must be a 4 element cell array containing strings.
            % Those strings must each exactly match one of the LED models
            % listed below. There is no rule against repetition of models.
            % If fewer than 4 LEDs are connected to the device, enter
            % 'NONE' for each corresponding port number. The order of the
            % connected LEDs corresponds exactly to port number.
            
            % "connectedLJChannels" is a cell array of strings containing
            % the names of the connected LabJack channels. These must
            % correspond, in order, to four outputs:
            % "R1" (DIO port), "R2" (DIO Port), "Power" (DIO Port),
            % "controlVoltage" (DAC Port)
                
                if nargin == 0
                    error('Not enough inputs');
                elseif nargin > 4
                    error('Too many inputs');
                end
                
                this.labjack = labjack;
                this.TTLDevices = TTLDevices;
                
                % Check if input is a supported device. For now, the MultiLED
                % class only supports U6 but others will be easy to add.
                this.supportedDevices = {'U6'};
                if ~ismember(this.labjack.LJType, this.supportedDevices)
                    tempStr = '';
                    for i=1:numel(this.supportedDevices)
                        tempStr = [tempStr, this.supportedDevices{i}, ', '];
                    end
                    error(['LJType must be one of: ', tempStr(1:(end-2))]);
                end
                
                % This is a mapping of each Thorlabs LED part number to its maximum
                % allowed current (mA)
                this.ledList = {
                    'M265L3', ... % Thorlabs free-space models
                    'M285L4',...
                    'M300L4',...
                    'M340L4',...
                    'M365L2',...
                    'M365LP1',...
                    'M375L4',...
                    'M385L2',...
                    'M385LP1',...
                    'M395L4',...
                    'M405L3',...
                    'M405LP1',...
                    'M420L3',...
                    'M430L4',...
                    'M450LP1',...
                    'M455L3',...
                    'M470L3',...
                    'M490L4',...
                    'M505L3',...
                    'M530L3',...
                    'M565L3',...
                    'M590L3',...
                    'M595L3',...
                    'M617L3',...
                    'M625L3',...
                    'M660L4',...
                    'M680L4',...
                    'M700L4',...
                    'M285F3',... % Fiber-coupled models
                    'M300F2',...
                    'M340F3',...
                    'M365F1',...
                    'M365FP1',...
                    'M375F2',...
                    'M385F1',...
                    'M385FP1',...
                    'M395F3',...
                    'M405F1',...
                    'M405FP1',...
                    'M420F2',...
                    'M455F1',...
                    'M470F3',...
                    'M490F3',...
                    'M505F1',...
                    'M530F2',...
                    'M565F3',...
                    'M590F2',...
                    'M595F2',...
                    'M617F2',...
                    'M625F2',...
                    'M660F1',...
                    'M680F3',...
                    'M700F3',...
                    'M740F2',...
                    'M780F2',...
                    'M810F2',...
                    'M850F2',...
                    'M880F2',...
                    'M940F1',...
                    'M970F3',...
                    'M1050F1',...
                    'MBB1F1',...
                    'MWWHF2',...
                    'MCWHF2', ...
                    'NONE'};
                
                % Maximum currents in mA. Order is preserved with 'keys'
                this.ledLimits = [350
                    500
                    350
                    700
                    700
                    1400
                    1400
                    700
                    1400
                    500
                    1000
                    1400
                    1000
                    500
                    2000
                    1000
                    1000
                    350
                    1000
                    1000
                    1000
                    1000
                    700
                    1000
                    1000
                    1200
                    600
                    500
                    500
                    350
                    700
                    700
                    1400
                    500
                    700
                    1400
                    500
                    500
                    1400
                    1000
                    1000
                    1000
                    350
                    1000
                    1000
                    700
                    1000
                    1000
                    1000
                    1000
                    1000
                    600
                    500
                    800
                    800
                    500
                    1000
                    1000
                    1000
                    1000
                    700
                    500
                    1000
                    1000
                    0];
                
                this.maxCurrentsMap = containers.Map(this.ledList, this.ledLimits);
                
                if nargin > 1
                    % Check connectedLEDs input
                    if ~isa(connectedLEDs, 'cell')
                        error('connectedLEDs must be a cell array of strings');
                    end
                    if numel(connectedLEDs) > 4
                        error('The maximum number of LEDs is 4');
                    end
                    
                    % Check connectedLEDs input values and set internal
                    % property
                    this.connectedLEDs{1} = 'NONE';
                    for i=1:4
                        if ~ismember(connectedLEDs{i}, this.ledList)
                            error('A connectedLEDs value does not match the list of accepted devices');
                        else
                            this.connectedLEDs{i+1} = connectedLEDs{i};
                        end
                    end
                    
                    this.setConnectedLEDCurrentLimits();
                    
                    % Create port mapping. Bit mapping:
                    % Bit 1 --> R1
                    % Bit 2 --> R2
                    % Bit 3 --> Power
                    % Analog value --> controlVoltage
                    this.relayPortMapping = containers.Map(0:4, {[0,0,0], [0,0,1],...
                        [1,0,1], [0,1,1], [1,1,1]});
                else
                    this.connectedLEDs = {};
                end
                
                % Set the connected LJ channels.
                if nargin > 2
                    % Check inputs
                    if numel(connectedLJChannels) ~= 4
                        error('Four connected channels are required');
                    end
                    
                    for i=1:3
                        if ~ismember(connectedLJChannels{i}, this.labjack.dioChannelList)
                            error([char(connectedLJChannels{i}) ' is not a supported dio channel']);
                        end
                    end
                    if ~ismember(connectedLJChannels{4}, this.labjack.dacChannelList)
                        error([char(connectedLJChannels{4}) ' is not a supported dac channel']);
                    end
                    
                    % Set the internal variable after passing the internal
                    % checks
                    this.connectedLJChannels = connectedLJChannels;
                else
                    this.connectedLJChannels = {};
                end
                
            end
        
        
        function setActiveLED(this, LED, percentPower)
            % Inputs:
            % "LED" is a string naming one of the connected LEDs
            % "percentPower" is a number between 0-100. The percent power
            % is always converted into the percent of that particular LED's
            % maximum current
            
            
            if this.labjack.isConnected
                
                % Check that 'LED' is one of the connected LEDs
                if (ismember(LED, this.connectedLEDs))|| strcmp(LED, 'NONE')
                    this.activeLED = LED;
                    % NEED PROPER ERROR HANDLING HERE!!
                    
                    this.activeLEDMaxCurrent_mA = this.maxCurrentsMap(this.activeLED);
                    
                    % PortNumber is from 0-4. 0 means nothing is on.
                    portNumber = (-1) + find( strcmp(this.activeLED,this.connectedLEDs),1);
                    if isempty(portNumber)||portNumber < 0 % Set to 0 if not found
                        portNumber = 0;
                    end
                    
                    % Ordered bits to set on the labjack ports, defining which
                    % LED to use
                    this.digitalBits = this.relayPortMapping(portNumber);
                    
                    % Ensure that the percentage power is between 0-100%
                    this.activeLEDPercent = max(min(percentPower,100), 0);
                    
                    % Set the analog control voltage, expressed as a fraction
                    % of the active LED's max power, which corresponds to a
                    % fraction of the current driver's range.
                    this.activeLEDControlVoltage = this.dacModRange*(this.activeLEDPercent/100)*(this.activeLEDMaxCurrent_mA/this.sourceCurrentLimit_mA);
                    
                    
                    % First set the analog voltage to zero while changing
                    % relays
                    this.labjack.setDACValues({this.connectedLJChannels{4}}, 0);
                    
                    % This should always go from 1-3
                    for i=1:3
                        this.labjack.setDIOValues({this.connectedLJChannels{i}}, this.digitalBits(i))
                    end
                    
                    % Set the control voltage setting the current
                    this.labjack.setDACValues({this.connectedLJChannels{4}}, this.activeLEDControlVoltage);
                    
                elseif ismember(LED, keys(this.TTLDevices))
                    this.activeTTL = LED;
                    
                    % Turn off the other devices
                    for i=1:3
                        this.labjack.setDIOValues({this.connectedLJChannels{i}}, 0)
                    end
                    
                    % Toggle the TTL device
                    this.labjack.setDIOValues({this.TTLDevices(LED)}, 1*(percentPower>0))
                    
                else
                    this.activeLED = 'NONE';
                    warning([LED, ' is not one of the connected LEDs. Active LED is set to ''NONE''']);
                end
                
            else
                warning('Labjack is not connected!')
            end
        end
        
    end
    
    
    %==========================================================================
    %
    %   PRIVATE METHODS
    %
    %==========================================================================
    methods (Access = protected)
        
        % Set the internal current limit values. This would be called
        % either by the constructor or by an internal method such as
        % setConnectedLEDs
        function setConnectedLEDCurrentLimits(this)
            
            % Clear any previous values
            this.connectedLEDLimits = zeros(4,1);
            
            % Set the current limits for the connected LEDs
            for i=1:numel(this.connectedLEDs)
                this.connectedLEDLimits(i) = this.maxCurrentsMap(this.connectedLEDs{i});
            end
            
        end
        
    end
    
end

