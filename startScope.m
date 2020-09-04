% Startup script for the UV Scope
% Paul Lebel
% czbiohub

% Output directory for datasets. Network locations can be used, but local
% directories are usually faster to write to on the fly, allowing for
% faster image aquisition.
basePath = 'C:\Users\uvscope\Documents\Temp data';

% List of the LEDs that are connected to the microscope. The MultiLED
% object uses these to configure parameters like max current. 
LEDList = {'M405FP1','M285L4','M565F3','M365FP1'};

% Path to a .json file defining parameters related to the
% configuration of the microscope. This information is included in the
% metadata for image acquisitions. 
presetsPath = 'C:\Users\uvscope\Documents\GitHub\Matlab-UV-Microscopy\UVScope_zeiss100x_bin2_simplified.json';

% COM port used by the Thorlabs MCM3000 stage controller
thorCOM = 'COM8';

% Define camera type
cam = 'PCO';

% Initialize camera object using Matlab's Imaq toolbox. Unfortunately, even
% though it helps standardize some commands, there are still
% device-specific parameters to work with. 
switch cam
    case 'PCO'
            vid = videoinput('pcocameraadaptor_r2018a', 0, 'USB 2.0');
            src = getselectedsource(vid);
            src.B1BinningHorizontal = '01';
            src.B2BinningVertical = '01';
            triggerconfig(vid, 'manual');
            vid.TriggerRepeat = inf;
            vid.FramesPerTrigger = 1;
            vid.TriggerFrameDelay = 0;
    case 'WinVid'
        vid = videoinput('winvideo', 1, 'MJPG_1024x768');
        src = getselectedsource(vid);
        vid.FramesPerTrigger = 1;
end

% Initialize the microscope controller
myScope = UVScope(presetsPath, vid, src, thorCOM, LEDList);

% Sets the base directory location. All MD Acquisitions will create
% their own timestamped folders within this base directory.
myScope.setBaseMDPath(basePath);
