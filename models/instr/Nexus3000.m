classdef Nexus3000 < InstrClass
    %NEXUS3000 Summary of this class goes here
    %   Detailed explanation goes here
    
    %     properties
    %         Name = 'Nexus 3000';
    %     end
    
    properties (Access = protected)
        PumpedVolume; % uL
        PumpPurged; % no=0, yes=1, for syringe pump
        PumpStartTime; % tic to keep track of pumped volume
        Timeout = 0.1;
        PauseTime = 0.3;  % prevents overloading of serial port
        BaudRate;
        StopBits;
        DataBits;
        Terminator;
        elapsedTime;
        
        wakeUpTimerObj;
    end
    
    methods
        % constructor
        function self = Nexus3000()
            self.Name = 'Nexus 3000';
            self.Group = 'Pump';
            self.Model = 'Nexus3000';
            self.Serial = '2172160';
            self.MsgH = ' ';
            self.CalDate = date;
            self.Busy = 0;
            self.Connected = 0;  % 0=not connected, 1=connected
            self.Obj = ' ';  % serial port object
            % serial connection properties
            self.Param.COMPort = 24;
            self.BaudRate = 9600;
            self.StopBits = 1;
            self.DataBits = 8;
            self.Terminator = 'CR/LF';
            self.Param.Parity = 'none';
            % pump properties
            
            self.Param.FlowRate_uLpMin = 10;  % in ul/min ****10 DEFAULT****
            self.Param.SyringeDiameter = 14.5;  % in mm for BC 10 mL plastic syringe
            self.Param.UpdatePeriod = 1; % update reading timer (sec)
            %Postive volume values for positive pressure (expunge)
            %Negative volume values for negative pressure (intake)
            self.Param.PumpVolume = -10*1000;  % in uL (10 mL plastic syringe)
            self.PumpedVolume = 0;
            self.PumpPurged = 0;
            self.Param.PurgeFlowRate = 10000; % in ul/min
            self.PumpStartTime = 0; % tic variable. Needs to be initialized incase stop called before start. shon 4/19/2014
            
            % create timer to ensure pump does not go to sleep (sleep mode = 60 minutes)
            % shon 4/19/2014
            % set to 50 minutes = 3000 sec
            self.Param.wakeUpPeriod = 3000;
            self.wakeUpTimerObj = timer(...
                'Name', 'Pump Wake-Up Timer',...
                'StartDelay', self.Param.wakeUpPeriod, ...
                'Period', self.Param.wakeUpPeriod,...
                'ExecutionMode', 'fixedSpacing',...
                'BusyMode', 'drop', ...
                'TimerFcn', {@self.autoWakeUpPump});
        end
    end
    
    methods
        function connect(self)
            self.Obj = serial(['COM', num2str(self.Param.COMPort)], ...
                'BaudRate', self.BaudRate, 'Parity', self.Param.Parity, ...
                'StopBits', self.StopBits, 'DataBits', self.DataBits, ...
                'Terminator',self.Terminator);
            fopen(self.Obj);
            set(self.Obj,'Timeout',self.Timeout);
            resp = query(self.Obj,['set diameter ', num2str(self.Param.SyringeDiameter)]);
            pause(self.PauseTime)
            resp = query(self.Obj,['set volume ', num2str(self.Param.PumpVolume)]);
            pause(self.PauseTime)
            resp = query(self.Obj,['set rate ', num2str(self.Param.FlowRate_uLpMin)]);
            pause(self.PauseTime)
            
            start(self.wakeUpTimerObj);
            
            self.Connected = 1;
        end
        
        function self = disconnect(self)
            if self.Connected ~= 0
                fclose(self.Obj);
                delete(self.Obj);
                
                stop(self.wakeUpTimerObj);
                delete(self.wakeUpTimerObj);
                
                self.Connected = 0;
            end
        end
        
        function msg = start(self)
            if self.Connected == 1
                if self.Busy == 1
                    % need to stop pump to update params (shon 12/26/2013) otherwise, they don't update correctly
                    self.stop();
                end
                pause(0.5); % wtf. chemyx sucks. learn how to buffer commands
                resp = query(self.Obj,['set volume ' num2str(self.Param.PumpVolume)]);
                pause(self.PauseTime)
                resp = query(self.Obj,['set rate ', num2str(self.Param.FlowRate_uLpMin)]);
                pause(self.PauseTime)
                resp = query(self.Obj,'start');
                pause(self.PauseTime)
                self.PumpStartTime = tic; % for calculating pumped volume
                self.Busy = 1;
                msg = 'Pump Start';
            else
                msg = 'Pump not connected';
                error(msg);
            end
        end
        
        function self = changePumpDirection(self)
            self.Param.PumpVolume = -self.Param.PumpVolume;
            if self.Busy == 1
                % update pump params (shon 12/26/2013)
                self.start();
            end
            % this line of code does nothing. chemyx blows
            resp = query(self.Obj,['set volume ' num2str(self.Param.PumpVolume)]);
            pause(self.PauseTime)
        end
        
        function query_parameters(self)
            resp = query(self.Obj,'view parameter');
        end
        
        function msg = stop(self)
            if self.Connected
                if self.Busy
                    pause(self.PauseTime);
                    resp = query(self.Obj,'stop'); % what comes back from the pump?
                    pause(self.PauseTime);
                    self.elapsedTime = toc(self.PumpStartTime); % gives seconds spent pumping
                    self.PumpedVolume = self.PumpedVolume + self.Param.FlowRate_uLpMin*self.elapsedTime/60; % give uL pumped
                    self.Busy = 0;
                    msg = sprintf('Pump Stop:\n\tElapsed Time: %.1fs \n\tFlow Rate: %.1fuL/min \n\tPumped Volume: %.1fuL', self.elapsedTime, self.Param.FlowRate_uLpMin, self.PumpedVolume);
                else
                    msg = strcat(self.Name, ' is not running');
                end
            else
                msg = strcat(self.Name, ' is not connected');
                error(msg);
            end
        end
        
        %         % query pump state (pumping vs. stopped)
        %         function resp = isPumping(self)
        %             resp = self.Busy;
        %         end
        
        function sendParams(self)
            % shon 12/26/2013 this code does nothing except update the properties. chemyx blows
            resp = query(self.Obj,['set diameter ', num2str(self.Param.SyringeDiameter)]);
            pause(self.PauseTime)
            %            msg = strcat('-- SyringeDiamter=', num2str(self.Param.SyringeDiameter)); disp(msg);
            resp = query(self.Obj,['set volume ', num2str(self.Param.PumpVolume)]);
            pause(self.PauseTime)
            %            msg = strcat('-- SyringeVolume=', num2str(self.Param.PumpVolume)); disp(msg);
            resp = query(self.Obj,['set rate ', num2str(self.Param.FlowRate_uLpMin)]);
            pause(self.PauseTime)
            %            msg = strcat('-- Velocity=', num2str(self.Param.FlowRate_uLpMin)); disp(msg);
        end
        
        function reset(self)
            resp = query(self.Obj,'reset');
        end
        
        % function to clear the pump's lines
        function purge(self)
            if self.Connected
                % if pump is running, stop it
                if self.Busy == 1
                    % need to stop pump to update params (shon 12/26/2013) otherwise, they don't update correctly
                    self.stop();
                end
                pause(0.5); % wtf. chemyx sucks. learn how to buffer commands
                
                % minus for pump volume = change direction
                resp = query(self.Obj,['set volume ' num2str(-self.Param.PumpVolume)]);
                pause(self.PauseTime)
                resp = query(self.Obj,['set rate ', num2str(self.Param.PurgeFlowRate)]);
                pause(self.PauseTime)
                resp = query(self.Obj,'start');
                self.PumpedVolume = 0;
                self.PumpPurged = 1;
                self.Busy = 0;
            else
                msg = strcat(self.Name, ' not connected');
                error(msg);
            end
        end
        
        % function to get pumped volume
        function val = getPumpedVolume(self)
            if self.Busy % pump is running
                self.elapsedTime = toc(self.PumpStartTime); % gives seconds spent pumping
                self.PumpedVolume = self.PumpedVolume + self.Param.FlowRate_uLpMin*self.elapsedTime/60; % give uL pumped
                val = self.PumpedVolume;
                % reset pump time
                self.PumpStartTime = tic;
            else
                val = self.PumpedVolume;
            end
        end
        
        function autoWakeUpPump(self, ~, ~)
            if self.Busy
                self.start();
            else
                self.stop();
            end
        end
    end
end

