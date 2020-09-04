% Dummy class that hopefully doesn't throw errors when treated like a
% serial port object. The class is not intended to be complete, and can 
% be built as needed. 

% czbiohub
% Author: Paul Lebel
% Last updated 2019/02/14


classdef VirtualSerialPort < handle
 
    
    properties (GetAccess = public, SetAccess = protected)
        baudrate
        bytesize
        stopbits
        isOpen = false;
        responseBuffer
    end
   
    
    methods (Access = public)
        
        % Class constructor
        function this = VirtualSerialPort()
            this.baudrate = 9600;
            this.bytesize = 8;
            this.stopbits = 1;
        end
        
        function status = fopen(this)        
           this.isOpen = true;
           status = 1;
        end
        
        function status = flushinput(this)
            this.responseBuffer = [];
            status = 1;
        end
        
        function answer = fread(this, bytes, type)
            answer = zeros([bytes,1], type);
        end
        
        function fprintf(this,~)
            this.responseBuffer = 1;
        end
        
        function fwrite(this, ~)
            this.responseBuffer = msg;
        end
        
        function delete(this)
            
        end
        
        function fclose(this)
        end
        
    end
        
     
end
