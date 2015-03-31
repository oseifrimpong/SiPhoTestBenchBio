classdef Masterflex < InstrClass
    
    % Masterflex 7550-20 pump manual pdf:
    % http://www.masterflex.com/Assets/manual_pdfs/A-1299-0726.pdf
    % Victor Bass 2013
    
    %Minimum pump RPM is 2. (If you put in 1.95, it will round to 2).
    % @ 2  RPM we get ~70  uL/min
    % @ 10 RPM we get ~350 uL/min
    
    properties (Access = protected)
        PumpedVolume;  % in uL
        PumpPurged;  % does this only apply to syringe pump?
        PumpStartTime;  % to keep track of pumped volume
        Timeout = 2; % time-out time for reads
        PauseTime = 0.1; % brief pause so Matlab doesn't overrun serial port
        % pump rpm limits specified by manufacturer
        MIN_RPM = 1.6;
        MAX_RPM = 100;
    end
    
    methods
        %constructor
        function self = Masterflex()
            self.Name = 'Masterflex';
            self.Group = 'Pump';
            self.Model = '7550-20';
            self.MsgH = ' ';
            self.CalDate = date;
            self.Busy = 0;
            self.Connected = 0;  % 0=not connected, 1=connected
            self.Obj = ' ';  % serial port object
            % serial connection properties
            self.Param.COMPort = 1;
            self.Param.BaudRate = 4800;
            self.Param.StopBits = 1;
            self.Param.DataBits = 7;
            self.Param.Parity = 'odd';
            self.Param.Terminator = 'CR';
            % pump properties
            self.Param.FlowRate_uLpMin = 100;  % in ul/min
            self.Param.TubeDiameter_mm = 0.8;  % in mm
            self.Param.PurgeTime_sec = 5;
            self.Param.PurgeFlowRate_uLpMin = 5;
            self.Param.UpdatePeriod_sec = 0.5; % update reading timer: 0.5s
            self.Param.CWRotation = 0; % 1=CW, 0=CCW
            self.Param.RevolutionsToRun = 100; % diff operating mode, num of rev's to run then stop
            % derived class properties
            self.PumpedVolume = 0;
            self.PumpPurged = 0;
        end
    end
    
    methods (Static)
        function rpm = convert2rpm(flowRate, tubeDiameter)
            % this function converts velocity and tube diameter to rpm
%             flowRate = (flowRate - 1.836)/35.3; %correction factor w/ 0.8mm tubing
%             rtn = flowRate/(2*pi^2*(tubeD/2)^3);
            % shon 3/17/2014 - equ from OneNote based on measured flow rates w/ 0.8 mm diameter tubing
            if  tubeDiameter ~= 0.8
                error('Pump rpm calculation hard coded for 0.8 mm ID tubing.')
            else
                rpm = flowRate;
            end
        end
    end
    
    methods
        function self = connect(self)
            % check if already open
            if self.Connected== 1  %1: stage is connected
                err = MException('FluidicPump:Connection',...
                    'fluidic pump is already connected');
                throw(err);
            end
            % set serial port properties
            self.Obj = serial(['COM', num2str(self.Param.COMPort)]);
            set(self.Obj,'BaudRate',self.Param.BaudRate);
            set(self.Obj,'StopBits',self.Param.StopBits);
            set(self.Obj,'DataBits',self.Param.DataBits);
            set(self.Obj,'Parity',self.Param.Parity);
            set(self.Obj,'Terminator',self.Param.Terminator);
            
            try
                fopen(self.Obj);
            catch ME
                rethrow(ME);
            end
            if strcmp(self.Obj.Status, 'open')
                self.send_command(5);  %5=dec code for <ENQ>, which initializes connection to pump
                self.Connected= 1;
            end
        end
        
        function self = disconnect(self)
            % check if pump is connected
            if self.Connected == 0
                msg = 'Pump is not connected';
                disp(msg);
            end
            % try to close connection and delete serial port object
            try
                fclose(self.Obj);
                delete(self.Obj);
            catch ME
                disp(ME.message);
            end
            
            self.Connected = 0;
        end
        
        function self = send_command(self, command)
            % sends ASCII commands through serial port to control pump
            % <STX> starts commands, <CR> terminates them
            if self.Obj.BytesAvailable > 0  %empty buffer
                fscanf(self.Obj, '%s', self.Obj.BytesAvailable);
            end
            if strcmp(self.Obj.Status, 'open')
                fwrite(self.Obj, 02);  % sends ASCII dec code 02, means <STX>, required to start commands to pump
                fprintf(self.Obj, command);  % adds specified terminator <CR> to end of commands
            else
                err = MException('FluidicPump:Com',...
                    'fluidic pump status: connection closed');
                throw(err);
            end
            pause(0.1); % add some delay so we don't overrun the pumps buffer
        end
        
        % shon 3/18/2014
        function response = read_response(self)
            if self.Obj.BytesAvailable > 0  %empty buffer
                response = fscanf(self.Obj, '%s', self.Obj.BytesAvailable);
            end
            pause(0.1); % add some delay so we don't overrun the pumps buffer
        end
        
        function self = start(self)
            %send ASCII codes to start pump
            %P02 sends commands to pump 02, 02 is the default pump number
            %S+10 sets speed to 10rpm clockwise
            %G0 tells pump to pump continuously until halt command is given
            if self.Connected == 0
                % ensures pump is connected to serial port before starting
                msg = 'Pump not connected';
                disp(msg);
            else
                if self.Busy
                    % ensures pump has not started already
                    msg = strcat(self.Name,' already running. Stopping.');
                    disp(msg);
                    self.stop();
                end
                rpm = self.convert2rpm(self.Param.FlowRate_uLpMin, self.Param.TubeDiameter_mm);
                if rpm < self.MIN_RPM || rpm > self.MAX_RPM
                    msg = 'Specified rpm out of range. Aborting.';
                    disp(msg);
                end
                rpm = num2str(rpm);
                % shon 1/16/2013 +=clockwise, -=counterclockwise
                if self.Param.CWRotation
                    dir = '+'; % CW rotation
                else
                    dir = '-'; % CCW rotation
                end
                set_motor = strcat('P02S',dir,rpm);  %sets pump speed to calculated rpm, clockwise direction
                start_motor = 'P02G0';   %commands pump to pump until stop command issued
                self.send_command(set_motor);
                self.send_command(start_motor);
                self.PumpStartTime = tic;
                self.Busy = 1;  % shows pump has been started
            end
        end
        
        function self = stop(self)
            % send decimal ASCII codes to stops the pump
            % H sends halt command
            if self.Connected == 1
                if self.Busy == 1
                    stop_motor = 'P02H';
                    self.send_command(stop_motor);
                    elapsedTime = toc(self.PumpStartTime);    %gives time spent pumping in seconds
                    % give uL pumped
                    self.PumpedVolume = self.PumpedVolume + self.Param.FlowRate_uLpMin*elapsedTime/1000/60; % uL to mL, min to sec
                    self.Busy = 0;
                else
                    msg = strcat(self.Name, ' is not running');
                    disp(msg);
                end
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
        % shon 3/18/2014
        function self = zeroRevolutionsToGoCounter(self)
            % Z sends zero command
            if self.Connected == 1
                if self.Busy == 1
                    % stop the pump
                    self.stop();
                end
                zeroRevolutionsCounter = 'P02Z';
                self.send_command(zeroRevolutionsCounter);
                msg = strcat(self.Name, 'Zerod pumps revolution counter.');
                disp(msg);
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
        % shon 3/18/2014
        function self = zeroCumulativeRevolutions(self)
            % Z sends zero command
            if self.Connected == 1
                if self.Busy == 1
                    % stop the pump
                    self.stop();
                end
                zeroRevolutionsCounter = 'P02Z0';
                self.send_command(zeroRevolutionsCounter);
                msg = strcat(self.Name, 'Zerod pumps cumulative revolutions counter.');
                disp(msg);
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
        % shon 3/18/2014
        function self = setNumRevolutionsToRun(self)
            % V sets number of revolutions to run
            if self.Connected == 1
                if self.Busy == 1
                    % stop the pump
                    self.stop();
                end
                revolutions = num2str(self.Param.RevolutionsToRun);
                setRevolutionsToRun = strcat('P02V', revolutions);
                self.send_command(setRevolutionsToRun);
                msg = strcat(self.Name, 'Set number of revolutions to run to ',revolutions);
                disp(msg);
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
        % shon 3/18/2014
        function self = setMaxRevolutionsToRun(self)
            % V sets number of revolutions to run
            if self.Connected == 1
                if self.Busy == 1
                    % stop the pump
                    self.stop();
                end
                revolutions = num2str(99999.99);
                setRevolutionsToRun = strcat('P02V',revolutions);
                self.send_command(setRevolutionsToRun);
                msg = strcat(self.Name, 'Set number of revolutions to run to ',revolutions);
                disp(msg);
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
        % shon 3/18/2014
        function self = getNumberOfRevolutionsToGo(self)
            % E gets the number of revolutions to run
            if self.Connected == 1
                if self.Busy == 1
                    % stop the pump
                    self.stop();
                end
                getRevolutionsToGo = strcat('P02E',revolutions);
                self.send_command(getRevolutionsToGo);
                response = self.read_response();
                msg = strcat(self.Name, 'Revolutions to go = ', response);
                disp(msg);
            else
                msg = strcat(self.Name, ' is not connected');
                disp(msg);
            end
        end
        
%         % query pump state (pumping vs. stopped)
%         function resp = isPumping(self)
%             resp = self.Busy;
%         end
        
        
        function val = getPumpedVolume(self)
            if (self.Busy) % pump is running
                elapsedTime = toc(self.PumpStartTime);
                self.PumpedVolume = self.PumpedVolume + elapsedTime*self.Param.FlowRate_uLpMin/1000/60; % uL to mL, min to sec
                val = self.PumpedVolume;
                % restart pump time
                self.PumpStartTime = tic;
            else % pump is stopped
                val = self.PumpedVolume;
            end
        end
        
        function self = purge(self)
            if self.Connected == 1
                if self.Busy == 1
                    msg = 'Pump running. Wait until it stops to purge it';
                    disp(msg);
                else
                    self.Busy = 1;
                    % shon 1/16/2013 +=clockwise, -=counterclockwise
                    if self.Param.CWRotation
                        dir = '+'; % CW rotation
                    else
                        dir = '-'; % CCW rotation
                    end
% 3/18/2014 shon
                    purgeFlowRate = num2str(self.Param.PurgeFlowRate_uLpMin);
                    purge_lines = strcat('P02S',dir,purgeFlowRate,'G0');
%                    purge_lines = strcat('P02S',dir,'10G0');
%                    purge_lines = strcat('P02S',dir,self.Param.FlowRate_uLpMin);
                    stop_motor = 'P02H';
                    self.PumpStartTime = tic;
                    self.send_command(purge_lines);
                    pause(self.Param.PurgeTime_sec);
                    self.send_command(stop_motor);
                    elapsedTime = toc(self.PumpStartTime);
                    self.PumpedVolume = self.PumpedVolume + self.Param.FlowRate_uLpMin*elapsedTime/1000/60; % uL to mL, min to sec
                    self.Busy = 0;
                    self.PumpPurged = 1;
                end
            else
                msg = strcat(self.Name, ' not connected');
                disp(msg);
            end
        end
        
        function val = isPurged(self)
            val = self.PumpPurged;
        end
    end
    
    methods
        function self = check_status(self)
            self.send_command('P02I');  %I requests pump status
            pause(self.PauseTime);
            % get and display reponse from pump to status request
            response = fscanf(self.Obj);
            disp(response);
            %the response should be P02Ixxxxx
            %to interpret the response, see the user manual at:
            %http://www.masterflex.com/Assets/manual_pdfs/A-1299-0726.pdf
            %section 1.8 of appendix A: Pump Drive Communication
        end
        
        function self = reset(self)
            %This function resets the instrument and PumpedVolume tracking
            % steps:
            % 1. check to see if instr handle exists, if so, delete it
            % 2. re-create instrument handle and open port
            % 3. initialize instrument communications
            % 4. validate instrument communication
            % 5. set flags and reset PumpedVolume
            
            % 1
            if self.Connected == 1
                stop_motor = [02;80;48;50;72;13];
                %stop_motor = <STX> P 0 2 H <CR>
                self.send_command(stop_motor);   %makes sure the pump is stopped before trying to reset the connection
                fclose(self.Obj);
                delete(self.Obj);
                clear self.Obj;
                self.Connected = 0;
            end
            
            %2
            self.Obj = serial(['COM', num2str(self.Param.COMPort)]);
            set(self.Obj,'BaudRate',self.Param.BaudRate);
            set(self.Obj,'DataBits',self.Param.DataBits);
            set(self.Obj,'Parity',self.Param.Parity);
            set(self.Obj,'Terminator',self.Param.Terminator);
            try
                fopen(self.Obj);
            catch ME
                rethrow(ME);
            end
            if strcmp(self.Obj.Status, 'open')
                self.Connected= 1;
            end
            
            %3
            self.send_command(5);  % 5 = dec code for <ENQ>, which initializes connection to pump
            
            %4
            if self.Param.CWRotation
                dir = '+'; % CW rotation
            else
                dir = '-'; % CCW rotation
            end
            set_motor = strcat('P02S',dir,'10');
            self.send_command(set_motor);    %pump should acknowldege this command
            connection_check = fread(self.Obj);   %expected value is 6, dec code for <ACK>
            if connection_check ~= 6
                %close, delete, clear connection again
                fclose(self.Obj);
                delete(self.Obj);
                clear(self.Obj);
                %re-initialize and open connection
                self.Obj = serial(['COM', num2str(self.Param.COMPort)]);
                set(self.Obj,'BaudRate',self.Param.BaudRate);
                set(self.Obj,'DataBits',self.Param.DataBits);
                set(self.Obj,'Parity',self.Param.Parity);
                set(self.Obj,'Terminator',self.Param.Terminator);
                fopen(self.Obj);
                disp('Pump Reconnect attempted again')
            else
                disp('Pump connection validated')
            end
            
            %5
            self.PumpedVolume = 0;  % reset pumped volume
            self.PumpPurged = 0 ;  % reset if pump purged or not
        end % reset method
    end % 2nd set of methods
end
