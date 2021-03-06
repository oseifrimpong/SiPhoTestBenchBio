classdef VelmexXSlide < InstrClass
    %Velmex X-Slide stage Summary of this class goes here
    %   Detailed explanation goes here
    % Shon 2013
    
    properties
        xPos; % stage x position
        zPos; % stage y position
        Calibrated; % stage calibrated
        TrayLoaded; % 0=no, 1=yes, tray loaded
        TrayEjected; % 0=no, 1=yes, tray ejected
        WellNumber; % current well number
        FrontPlateType; % moved to Param (shon)
        BackPlateType;
        PlateGap;
        CurrentWell;
        Driver;
%        PlateList;
    end
    
    methods(Static)
        function steps = distance_to_steps(distance, units)
            % steps in counts
            % for velmex xn10-0020-e01-7
            if strcmp(units,'inch')
                advancePerStep=0.00025;
                steps=distance/advancePerStep;
            elseif strcmp(units, 'mm')
                advancePerStep=0.00025*25.4;
                steps=distance/advancePerStep;
            end
        end % method distance_to_steps
    end
    
    methods
        %constructor
        function self = VelmexXSlide()
            self.Name = 'VelmexXSlide';
            self.Group = 'Fluidic Stage';
            self.Model = 'XN10-0020-E01-71(z axis)    XN10-0120-E01-71(y axis)    PK245-01AA(motor)';
            self.CalDate = date;
            self.Busy = 0;
            self.Connected = 0;  % 0=not connected, 1=connected
            %             self.Calibrated = 0;
            self.Obj = ' ';  % serial port object
            % serial connection properties
            self.Param.COMPort = 6;
            self.Param.BaudRate = 9600;
            % fluidic stage properties
            self.PlateGap = 7;  % gap (in mm) between front and back plates
            self.CurrentWell = 1;  % 0 = no position or well set % shon 12/27/2013 needed to change this to 1 so value is within range of possible wells
            self.TrayLoaded = 0;
            self.TrayEjected = 0;
            self.xPos = nan;
            self.zPos = nan;
            self.Driver = 'Vxmdriver';
%            self. = [3;6;12]; % (3 rows in a 6 well plate, 12 rows in 96 well plate)
            
            self.Param.Acceleration = 500; % is this cm/sec?
            self.Param.Velocity = 5; % is this cm/sec?
            self.Param.InitialPosition = 297; %mm, offset from end of stage (ejected position) to start position
            self.Param.DropDist = 42; %mm, offset for Al tube moutning bar
            self.Param.FrontPlate = 6; % 24 well plate % number of rows in the plate, from 1
            self.Param.BackPlate = 3; % 6 well plate % number of rows in the plate, from 1
        end
    end
    
    methods
        function self = connect(self)
            % check if connection is already open
            if self.Connected == 1  % 1 means stage is connected
                err = MException('FluidicStage:Connection',...
                    'fluidic stage is already connected');
                throw(err);
            else
                self.Connected = 1;
                if libisloaded(self.Driver)
                    unloadlibrary(self.Driver);
                end
                loadlibrary(self.Driver, 'Vxmdriver.h');
                COM = self.Param.COMPort;
                calllib(self.Driver, 'OpenPort', COM, self.Param.BaudRate);
                calllib(self.Driver, 'DriverSendToPort', 'F,C,setM1M1,setM2M1,setL1M0,setL2M0,R'); % set motor axis and type
                self.Connected = calllib(self.Driver, 'IsPortOpen');
            end
        end
        
        function self = disconnect(self)
            if self.Connected == 1
                self.Connected = 0;
                calllib(self.Driver, 'ClearPort');
                calllib(self.Driver, 'ClosePort');
            else
                self.Connected = 0;
            end
        end
        
        function self = reset_driver(self)
            if self.Connected == 1
                calllib(self.Driver, 'ResetDriverFunctions');
            else
                debug_msg(self.hGUI, 'Debug Mode: Driver Reset');
            end
        end
        
        function self = wait_for_command(self)
            calllib(self.Driver, 'WaitForChar', '^', 0);
        end
        
        function self = get_position(self)
            self.xPos = calllib(self.Driver, 'GetMotorPosition', 1);
            self.zPos = calllib(self.Driver, 'GetMotorPosition', 2);
        end
        
        function self = move_x(self, dist)
            if self.Connected == 1
                if dist == 0
                    return
                end
                steps = self.distance_to_steps(dist, 'mm');
                move_command = ['F,C,I1M', num2str(steps), ',R'];
                calllib(self.Driver, 'DriverSendToPort', move_command);
            else
                msg = strcat(self.Name, ' is not connected');
                error(msg);
            end
        end
        
        function self = move_z(self, dist)
            if self.Connected == 1
                if dist == 0
                    return
                end
                steps = self.distance_to_steps(dist, 'mm');
                move_command = ['F,C,I2M', num2str(steps), ',R'];
                calllib(self.Driver, 'DriverSendToPort', move_command);
            else
                msg = strcat(self.Name, ' is not connected');
                error(msg);
            end
        end
        
        function ejectTray(self)
            if self.Connected
                % next 2 lines copied from move_to_zero
                portCommand = 'F,C,I2M0,I1M0,IA1M-0,IA2M-0,R';
                calllib(self.Driver, 'DriverSendToPort', portCommand);
                
                % Set the properties
                self.TrayLoaded = 0;
                self.TrayEjected = 1;
            else
                msg = strcat(self.Name, ' not connected');
                error(msg);
            end
        end
        
        function loadTray(self)
            if self.Connected
                % next 4 lines copied from move_to_initial
                steps = self.distance_to_steps(self.Param.InitialPosition, 'mm');
                portCommand=['F,C,I1M-' num2str(steps) ',R'];
                calllib(self.Driver, 'DriverSendToPort', portCommand);
                self.CurrentWell=0;
                
                % Set the properties
                self.TrayLoaded = 1;
                self.TrayEjected = 0;
            else
                msg = strcat(self.Name, ' not connected');
                error(msg);
            end
        end
        
        %         function self = move_to_initial(self)
        %             steps = self.distance_to_steps(self.InitialPosition, 'mm');
        %             portCommand=['F,C,I1M-' num2str(steps) ',R'];
        %             calllib(self.Driver, 'DriverSendToPort', portCommand);
        %             self.CurrentWell=0;
        %         end
        
        function self = move_to_zero(self)
            portCommand = 'F,C,I2M0,I1M0,IA1M-0,IA2M-0,R';
            calllib(self.Driver, 'DriverSendToPort', portCommand);
        end
        
        function self = setWellNumber(self, well)
            self.CurrentWell = well;
        end
        
        function self = move_to_well(self, new_well)
            %plate_type is the number of rows in the plate...either 3 or 12
            
            %checks if new well is out of bounds
            if new_well > (self.Param.FrontPlate + self.Param.BackPlate)
                err = MException('FluidicStage:MoveToWell',...
                    'Velmex XSlide Stage: new_well greater than FrontPlateType + BackPlateType');
                throw(err);
            end
            
% shon deleted this 12/15/2013
            %checks if plate types are valid
%             if self.Param.FrontPlate ~= 12 && self.Param.FrontPlate ~= 3
%                 err = MException('FluidicStage:MoveToWell',...
%                     'Velmex XSlide Stage: FrontPlateType value is not 12 or 3');
%                 throw(err);
%             end
%             
%             if self.Param.BackPlate ~= 12 && self.Param.BackPlate ~= 3
%                 err = MException('FluidicStage:MoveToWell',...
%                     'Velmex XSlide Stage: BackPlateType value is not 12 or 3');
%                 throw(err);
%             end
            
            portCommand = 'F,C,';
            
            %Calibrate movements to plate configurations
            plate_offsets = [14.29,16.5,25]; % (shons note) edge of tray to center of first well
            plate_types = [12,6, 3]; % (shons note) # of wells the length of the tray (eg: 12 = 96 well plate (12 rows x 8 col))
            plate1_offset = sum((plate_types == self.Param.FrontPlate).*plate_offsets);
            plate2_offset = sum((plate_types == self.Param.BackPlate).*plate_offsets);
            plate_dists = [9.02,19.24,39.24]; % (shons note) distance of centers well2well
            plate1_dist = sum((plate_types == self.Param.FrontPlate).*plate_dists);
            plate2_dist = sum((plate_types == self.Param.BackPlate).*plate_dists);
            
            %Trying to move to current well...
            if self.CurrentWell ~= new_well
                
                % (shons note) this code moves to the first well after initial load
                % shon totally guessed at # steps for 6 well plate...
                if self.CurrentWell== 0
                    steps = 2594*(self.Param.FrontPlate == 12) + ...
                        3303*(self.Param.FrontPlate == 6) + ...
                        4014*(self.Param.FrontPlate == 3);
                    portCommand = ['F,C,I2M0,I1M' num2str(steps)];
                    self.CurrentWell= 1;
                end
                
                curIsPlate1 = (self.CurrentWell<= self.Param.FrontPlate);
                movToIsPlate1 = (new_well <= self.Param.FrontPlate);
                
                if curIsPlate1 == movToIsPlate1
                    move_dist = (new_well - self.CurrentWell) * ...
                        (curIsPlate1*plate1_dist + not(curIsPlate1)*plate2_dist);
                else
                    if movToIsPlate1
                        move_dist = -1*(self.CurrentWell-self.Param.FrontPlate - 1)*plate2_dist - ...
                            (plate1_offset + plate2_offset + self.PlateGap) - ...
                            (self.Param.FrontPlate - new_well)*plate1_dist;
                    else
                        move_dist = (self.Param.FrontPlate - self.CurrentWell)*plate1_dist + (plate1_offset + plate2_offset + self.PlateGap) + (new_well - self.Param.FrontPlate - 1)*plate2_dist;
                    end
                end

%                disp(move_dist)
                
                if move_dist >= 0
                    dirstr = '';
                else
                    dirstr = '-';
                end
                drop_steps = self.distance_to_steps(self.Param.DropDist, 'mm');
                portCommand = [portCommand, ',I2M', num2str(drop_steps)];
                steps=self.distance_to_steps(abs(move_dist), 'mm');
                portCommand=[portCommand ',I2M0']; % move in (-) direction
                if steps ~= 0
                    portCommand=[portCommand ',I1M' dirstr num2str(steps)];
                end
                portCommand=[portCommand ',I2M-' num2str(drop_steps) ',R'];
                str = calllib(self.Driver, 'DriverSendToPort', portCommand);
                %             PortWaitForChar('^', 0);     %Halt program until VXM sends back a "^" indicating that it has completed its program
                %             PortWaitForChar = calllib('VxmDriver', 'WaitForChar', CharToWaitFor, TimeOutTime)
                %            PortWaitForChar = ''; % initialize
                %            while ~strcmp(PortWaitForChar, '^')
                pause(0.1);
                PortWaitForChar = calllib(self.Driver, 'WaitForChar', '^', 0); %Halt program until VXM sends back a "^" indicating that it has completed its program
                self.CurrentWell= new_well;
            end
        end
    end
end

