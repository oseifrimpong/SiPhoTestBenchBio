classdef AssayCtlClass < handle
    %Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        AssayParams;
        currentState;
        currentIteration;
        currentRecipeLoopIteration;
        currentRecipeIndex;
        currentDeviceIndex;
        reagentInChannel;
        reagentRIInChannel;
        reagentChangeScan
        reagentTimeTotal;
        reagentTimeLeft;
        numberOfSweepsLeft;
        BioAssayNote;
    end
    
    properties (Access = protected)
        ticID
        testbenchObj
        generalFilePath
        dateTag
        testType
        testPanel
        deviceNames
        numOfDevices
        currentDevice
        targetDevice
        numDetectors
        selectedDetectors
        totalNumberOfSteps
        colors
        fineAlignCounter
        reagentTimeTic
        pauseTime; % amount of time assay was paused waiting for user intervention
        
        testIsActive; % flag to enable/disable cancel button on sweep waitbar
        stopReq
        pauseReq
        skipToNextStepReq
        
        % assay state control
        assayEnable;
        
        % list of available buttons for control window popup
        % used as handles, so no spaces in string
        ctlWinButtonList = {...
            'Resume',...
            'Stop',...
            'Stop Pump',...
            'Start Pump',...
            'Edit Recipe',...
            '+10',...
            'Skip To Next',...
            'Fine Align',...
            'Reselect Peaks'};
    end
    
    methods
        %% constructor
        function self = AssayCtlClass(testbenchObj)
            % load default values to properties
            self.testbenchObj = testbenchObj;
            self.testType = testbenchObj.AppSettings.infoParams.Task;
            self.testPanel = panel_index('test');
            self.reagentChangeScan = [];
            self.colors = {'r', 'g', 'm', 'c', 'k', 'y'};
            
            % assay state control
            self.reagentTimeLeft = -inf; % disable by default
            self.numberOfSweepsLeft = -inf; % disable by default
            self.assayEnable = false; % default
            
            self.currentIteration = 1;
            self.currentRecipeLoopIteration = 1;
            self.currentRecipeIndex = 1;
            self.currentDeviceIndex = 1;
            
            % for backwards compat
            if ~exist('self.testbenchObj.AppSettings.AssayParams.CorrelationThreshold', 'var')
                self.testbenchObj.AppSettings.AssayParams.CorrelationThreshold = 0.8;
            end
            self.BioAssayNote = '';
        end
        
        %% Status methods
        function isActive = queryTestStatus(self)
            isActive = self.testIsActive;
        end
        
        %% control popup window
        function ctlWinPopup(self)
            disp('in ctlWinPopup');
            if self.testIsActive % Procceed only when test is active
                self.assayEnable = false;
                % popup control window to get user input
                assayCtlWinPopup(self.testbenchObj, self.ctlWinButtonList);
            end
        end % control popup
        
        % control popup reply
        function self = ctlWinPopupReply(self, reply)
            %            val = char(reply);
            % parse based on case statement
            switch reply
                case 'Resume'
                    self.testbenchObj.msg('<<<<<<<<<< Resuming Assay >>>>>>>>>>');
                    
                case 'Stop'
%                     self.testbenchObj.msg('<<<<<<<<<< Stop Assay >>>>>>>>>>');
%                     self.stopTest();
                    self.stopReq = true;
                case 'Stop Pump'
                    msg = self.testbenchObj.instr.pump.stop();
                    self.testbenchObj.msg(msg);
                    
                case 'Start Pump'
                    msg = self.testbenchObj.instr.pump.start();
                    self.testbenchObj.msg(msg);
                   
                case 'Edit recipe'
                    %TODO:
                    warndlg('Shon needs to build this', 'Warning', 'modal')
                case '+10'
                    % check for which type is used (time vs. sweeps)
                    if self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                        self.numberOfSweepsLeft = self.numberOfSweepsLeft + 10;
                        self.testbenchObj.msg(sprintf('Number Of Sweeps Left: %d', self.numberOfSweepsLeft));
                    else
                        self.reagentTimeLeft = self.reagentTimeLeft + 10*60;
                        self.testbenchObj.msg(sprintf('Time Of Sweeps Left: %d', round(self.reagentTimeLeft/60)));
                    end
                    
                case 'Skip To Next'
                    % check for which type is used (time vs. sweeps)
                    if self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                        self.numberOfSweepsLeft = 0;
                    else
                        self.reagentTimeLeft = 0;
                    end
                    
                case 'Fine Align'
                    fine_align(self.testbenchObj, 'panel', self.testPanel);
                    
                case 'Reselect Peaks'
%                     self.testbenchObj = selectPeaks(self.testbenchObj, self.currentDevice.Name);
%                     self.ctlWinPopupReply('Resume');
                      warndlg('Shon needs to build this', 'Warning', 'modal')
                otherwise
                    error('Should not get here.');
            end
        end % control popup reply
        
        function startTest(self)
            self.ticID = tic;
            self.assayEnable = true; % default
            self.testIsActive = true;
            self.numDetectors = self.testbenchObj.instr.detector.getProp('NumOfDetectors');
            self.selectedDetectors = self.testbenchObj.instr.detector.getProp('SelectedDetectors');
            
            % Get quick note tag from user
            if strcmpi(self.testType, 'BioAssay')
                self.createBioAssayNote();
            end
            
            % Check for recipe, if none, alert user and quit
            if ~self.checkRecipe()
                return;
            end
            
            % Disable active FB for optical stage if enabled
            if self.testbenchObj.AppSettings.AssayParams.DisableStageActiveFB
                self.testbenchObj.instr.opticalStage.set_closed_loop(0);
                self.testbenchObj.msg('Optical stage active feedback disabled.');
            end
            
            % Check for TEC, if off, alert user w/ popup to cancel or continue
            
            % Get a list of all devices to test
            self.getDeviceList();
            
            % Determine reagent currently in channel
            self.checkReagentInChannel();
            
            % Estimate length (time) of assay
            
            % Zero laser and detectors if enabled
            
            % Initialize control state variables
            
            self.totalNumberOfSteps = self.numOfDevices * length(self.testbenchObj.recipe.reagent);
            self.stopReq = false;
            self.pauseReq = false;
            self.skipToNextStepReq = false;
        end
        
        function pauseTest(self)
            
        end
        
        function stopTest(self)
            % save current state
            self.saveAssayState();
            
            % turn off laser (double check)
            while (self.testbenchObj.instr.laser.laserIsOn)
                self.testbenchObj.instr.laser.off();
                self.testbenchObj.msg('Turning laser off');
            end
            
            % Stop pump
            while self.testbenchObj.instr.pump.isConnected && self.testbenchObj.instr.pump.Busy
                msg = self.testbenchObj.instr.pump.stop();
                self.testbenchObj.msg(msg);
            end
            
            % Turn off TEC
            while self.testbenchObj.instr.thermalControl.Connected && self.testbenchObj.instr.thermalControl.Busy
                self.testbenchObj.instr.thermalControl.stop();
                self.testbenchObj.msg('Turning TEC off');
            end
        end
        
        function finishTest(self)
            % Stop Test First
            self.stopTest();
            if ~self.stopReq
                % send email
                if self.testbenchObj.AppSettings.FinishTestSettings.SendEmail
                    %TODO: attach final plots to email
                    sendEmail(self.testbenchObj.AppSettings.infoParams.Email, 'Optical setup Finish', 'Get your ass back in the lab.')
                end
            
                % move data
                moveData(self.testbenchObj);
            end
        end
        
        %% save assay state
        function saveAssayState(self)
            
        end
        
        function loadAssayState(self)
            
        end
        
        function resetAssayState(self)
            self.currentIteration = 1;
            self.currentRecipeLoopIteration = 1;
            self.currentRecipeIndex = 1;
            self.currentDeviceIndex = 1;
        end
        
        %% orchestrate assay
        function orchestrateTest(self, mode)
            if strcmpi(mode, 'Start')
                self.resetAssayState();
            elseif strcmpi(mode, 'Continue')
                self.loadAssayState();
            else
                errordlg('Error in Start Mode', 'ERROR!');
                return;
            end
            
            % Loop through assay iterations
            while self.currentIteration <= self.testbenchObj.AppSettings.AssayParams.AssayIterations
                % Generate general datapath
                self.generalFilePath = createTempDataPath(self.testbenchObj);
                % create <dateTag> for device directories
                % format = c:\TestBench\TempData\<chipArch>\<dieNum>\<device>\<testType>\<dateTag>\*
                self.dateTag = datestr(now, 'yyyy.mm.dd@HH.MM'); % time stamp
                self.testbenchObj.lastTestTime = self.dateTag;
                msg = strcat('Test Loop Iteration #', num2str(self.currentIteration));
                self.testbenchObj.msg(msg);
                
                % Loop through all steps/reagents in the recipe file
                % Temporarily do this, need to change if "continue"
                self.currentRecipeLoopIteration = 1;
                while self.currentRecipeLoopIteration <= self.testbenchObj.AppSettings.AssayParams.RecipeIterations
                    self.checkUserIntervention();
                    if self.stopReq
                        return;
                    end
                    msg = strcat('Recipe Loop Iteration #', num2str(self.currentRecipeLoopIteration));
                    self.testbenchObj.msg(msg);
                    % Reset "reagentChangeScan"
                    self.reagentChangeScan = [];
                    % Temporarily do this, need to change if "continue"
                    self.currentRecipeIndex = 1;
                    while self.currentRecipeIndex <= length(self.testbenchObj.recipe.reagent)
                        self.checkUserIntervention();
                        if self.stopReq
                            return;
                        end
                        % Load New Reagent
                        self.loadNewReagent();
                        % Tune Thermal Control
                        self.tuneThermalControl();
                        % Loop through selected devices for this reagent or temp setting
                        % Temporarily do this, need to change if "continue"
                        self.notificationAtReagentChanges();
                        self.currentDeviceIndex = 1;
                        % clear pause time
                        self.pauseTime = 0;
                        while self.currentDeviceIndex <= self.numOfDevices
                            self.checkUserIntervention();
                            if self.stopReq
                                return;
                            end
                            self.moveToNextDevice();
                            if strcmpi(self.testType, 'BioAssay')
                                self.targetDevice.addBioAssayNote(self.BioAssayNote);
                            end
                            self.setUpTestTiming()
                            % load fineAlignCounter counter
                            self.fineAlignCounter = self.testbenchObj.AppSettings.AssayParams.ScansUntilNextFineAlign;
                            
                            % take data until time expires
                            while (self.reagentTimeLeft > 0) || (self.numberOfSweepsLeft > 0)
                                self.checkUserIntervention();
                                if self.stopReq
                                   return; 
                                end
                                % Decrement fine align counter
                                self.fineAlignCounter = self.fineAlignCounter - 1;
                                if self.fineAlignCounter == 0
                                    fast_fine_align(self.testbenchObj, 'panel', self.testPanel);  %jonasf: added this to avoid drift. maybe add as setting?
                                    % reload the fine align counter
                                    self.fineAlignCounter = self.testbenchObj.AppSettings.AssayParams.ScansUntilNextFineAlign;
                                end
                                % Perform Sweep and Save Data
                                [wvlData, pwrData] = sweep(self.testbenchObj);
                                self.saveScanResults(wvlData, pwrData);
                                
                                % air bubble detection
%                                 if ~self.testbenchObj.AppSettings.AssayParams.CorrelationThreshold
%                                     % invoke waveform processing in deviceClass
%                                     msg = self.targetDevice.scanToScanCorrelation(self.testbenchObj.AppSettings.AssayParams.CorrelationThreshold);
%                                     if ~isempty(msg)
%                                         % pause the assay, wait for user intervention
%                                         % capture current time
%                                         startPauseTime = tic;
%                                         % send an email
%                                         try
%                                             sendEmail(self.testbenchObj.AppSettings.infoParams.Email, 'AIR BUBBLE DETECTED', sprintf('%s', msg));
%                                         end
%                                         % create a uiwait popup
%                                         f = figure;
%                                         h = uicontrol('Position',[20 20 200 40],'String','Continue',...
%                                             'Callback','uiresume(gcbf)');
%                                         disp(msg);
%                                         % user 'Ok' continues the assay
%                                         uiwait(gcf);
%                                         disp('Resuming assay.');
%                                         close(f);
%                                         % must update the time remaining
%                                         self.pauseTime = self.pauseTime + ...
%                                             toc(startPauseTime);
%                                     end
%                                 end
%                                 
%                                 % check for air bubble (do correlation)
%                                 if ~self.checkScanToScanCorrelation(...
%                                         self.targetDevice,...
%                                         self.testbenchObj.AppSettings.AssayParams.CorrelationThreshold)
%                                     self.scanToScanCorrelationIsOK = false;
%                                 end
                                
                                % Perform Peak Tracking and Save
                                if self.targetDevice.hasPeakSelected
                                    self.targetDevice.trackPeaks();
                                    self.targetDevice.savePeaksTrackData();
                                end
                                
                                % Plot Results
                                self.plotScanResults();
                                
                                % Update Assay Table
                                self.updateAssayTable();
                                % Next thing?
                                
                            end % Scanning
                            self.currentDeviceIndex = self.currentDeviceIndex + 1;
                        end % device indexing
                        self.currentRecipeIndex = self.currentRecipeIndex + 1;
                    end % recipe indexing
                    self.currentRecipeLoopIteration = self.currentRecipeLoopIteration + 1;
                end % recipe looping
                self.currentIteration = self.currentIteration + 1;
            end % iteration looping
        end % orchestrate assay
        
    end
    
    %% Private Method
    methods (Access = private)
        
%         function checkScanToScanCorrelation(deviceObj, thresholdValue)
%             % return 0 if Ok, otherwise, return threshold value
%         end        
        
        function createBioAssayNote(self)
            illegalSymbol = {'\', '/', ':', '*', '?', '"', '<', '>', '|'};
            while isempty(self.BioAssayNote)
                note = inputdlg('Please input a quick note for the BioAssay', 'BioAssay Type', 1, {''});
                self.BioAssayNote = note{1};
                for n = 1:length(illegalSymbol)
                    if any(strfind(self.BioAssayNote, illegalSymbol{n}))
                        self.BioAssayNote = '';
                        break;
                    end
                end
            end
        end
        
        function validRecipe = checkRecipe(self)
            validRecipe = true;
            if ~isstruct(self.testbenchObj.recipe)
                warndlg('Please load a valid recipe file.', 'Invalid Recipe');
                self.testbenchObj.msg('Cannot start test. No recipe file loaded. Aborting.')
                % re-enable start button
                set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.startButton, 'Enable', 'On');
                % Disable pause button and Stop Button
                set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.pauseButton, 'Enable', 'Off');
                set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.stopButton, 'Enable', 'Off');
                validRecipe = false;
            end
        end
        
        function getDeviceList(self)
            self.deviceNames = self.testbenchObj.testedDevices;
            self.numOfDevices = length(self.deviceNames);
            for deviceIndex = 1:self.numOfDevices
                if self.testbenchObj.devices.(self.deviceNames{deviceIndex}).getScanNumber >= 1
                    self.testbenchObj.devices.(self.deviceNames{deviceIndex}).resetScanNumber();
                end
            end
        end
        
        function checkReagentInChannel(self)
            if self.testbenchObj.instr.fluidicStage.isConnected && self.testbenchObj.instr.pump.Busy
                recipeIndex = find(self.testbenchObj.recipe.well == self.testbenchObj.instr.fluidicStage.CurrentWell, 1);
                self.reagentInChannel = self.testbenchObj.recipe.reagent{recipeIndex};
                self.reagentRIInChannel = self.testbenchObj.recipe.ri(recipeIndex);
            else
                self.reagentInChannel = 'N/A';
                self.reagentRIInChannel = 'N/A';
            end
        end
        
        function loadNewReagent(self)
            self.reagentInChannel = self.testbenchObj.recipe.reagent{self.currentRecipeIndex};
            self.reagentRIInChannel = self.testbenchObj.recipe.ri(self.currentRecipeIndex);
            
            if self.testbenchObj.AppSettings.AssayParams.SequenceReagentsManually
                message = sprintf('Manually load reagent into channel.\nClick OK to continue');
                uiwait(msgbox(message));
            elseif self.testbenchObj.instr.pump.isConnected && self.testbenchObj.instr.fluidicStage.isConnected && (self.testbenchObj.recipe.well(self.currentRecipeIndex) ~= 0)
                % Automated reagent sequencing (requires connected stage and pump)
                % move to new well
                if self.testbenchObj.instr.fluidicStage.CurrentWell ~= self.testbenchObj.recipe.well(self.currentRecipeIndex)
                    % stop the pump if running
                    if self.testbenchObj.instr.pump.Busy
                        self.testbenchObj.msg(self.testbenchObj.instr.pump.stop());
                    end
                    
                    % soft stop and relax pressure to avoid air bubbles in line
                    if self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec > 0
                        msg = strcat('Relaxing tube pressure.',...
                            'Pausing ', num2str(self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec),' sec.');
                        self.testbenchObj.msg(msg);
                        pause(self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec); % arbitrary
                    end
                    
                    %% reverse pump to create reagent bubble at tube end
                    reverse_flow_rate = 100; 
                    
                    if self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange > 0
                        msg = strcat('Reversing pump to create bubble at tube end.');
                        self.testbenchObj.msg(msg);
                        % drop fluidic stage to expose tube end to air
%                        dropDist = self.testbench.instr.fluidicStage.getParam('DropDist');
%                        self.testbenchObj.instr.fluidicStage.move_z(dropDist);
                        % assume DropDist starts at '0' for Z stage. Move to end
                        self.testbenchObj.instr.fluidicStage.move_z(100);
                        
                        % reverse pump briefly to create bubble
                        % get and store current flow rate
                        flowRate = self.testbenchObj.instr.pump.getParam('FlowRate_uLpMin');
                        % set reverse flow rate to 1000 uL/min
                        self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', reverse_flow_rate);
                        % change pump direction
                        self.testbenchObj.instr.pump.changePumpDirection();
                        % start for 1 sec, then stop
                        msg = strcat('Pumping at 100 uL/min for ',...
                            num2str(self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange),' sec.');
                        self.testbenchObj.msg(msg);
                        self.testbenchObj.instr.pump.start();
                        pause(self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange);
                        self.testbenchObj.instr.pump.stop();
                        % reagent consumed = 100 uL/min / 60 sec/min * userSpecdRunTime (sec)
                        reagentConsumed = 100/60*self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange;
                        msg = strcat('Reagent consumed=',...
                            num2str(reagentConsumed),' uL');
                        self.testbenchObj.msg(msg);                        
                        % restore original flow rate
                        self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', flowRate);
                        % change pump direction back
                        self.testbenchObj.instr.pump.changePumpDirection();
                    end
                    
                    %% move to well for new reagent
                    self.testbenchObj.instr.fluidicStage.move_to_well(self.testbenchObj.recipe.well(self.currentRecipeIndex));
                    msg = strcat('Moving to well ',...
                        num2str(self.testbenchObj.recipe.well(self.currentRecipeIndex)));
                    self.testbenchObj.msg(msg);
                    
                    % restore the syringe position if ReversePumpTimeAtReagentChange feature is used
                    if self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange > 0
                        msg = strcat('Restoring syringe position.');
                        self.testbenchObj.msg(msg);
                        % get and store current flow rate
                        flowRate = self.testbenchObj.instr.pump.getParam('FlowRate_uLpMin');
                        % set reverse flow rate to 1000 uL/min
                        self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', reverse_flow_rate);
                        % start for 1 sec, then stop
                        self.testbenchObj.instr.pump.start();
                        pause(self.testbenchObj.AppSettings.AssayParams.ReversePumpTimeAtReagentChange);
                        self.testbenchObj.instr.pump.stop();
                        % restore original flow rate
                        self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', flowRate);
                        
                        % pause to allow flow to settle before scanning
                        if self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec > 0
                            msg = strcat('Pausing to allow flow to settle.',...
                                'Waiting ', num2str(self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec),' sec.');
                            self.testbenchObj.msg(msg);
                            pause(self.testbenchObj.AppSettings.AssayParams.RelaxPressureTime_sec); % arbitrary
                        end
                    end
                    
                end
                if self.testbenchObj.AppSettings.AssayParams.PrimeFluidicChannel
                    msg = strcat('Priming fluidic channel with ', self.reagentInChannel);
                    self.testbenchObj.msg(msg);
                    
                    % calculate reagent transit time in tube
                    inTubeVolume_uL = self.testbenchObj.AppSettings.AssayParams.TubeInLength_mm * 1000 *...
                        3.14 * (self.testbenchObj.AppSettings.AssayParams.TubeInID_um/2)^2 * 1e-9;
                    
                    % set new pumped volume target based on tube volume
                    pumpedVolume = self.testbenchObj.instr.pump.getPumpedVolume; % in uL
                    targetVolume = pumpedVolume + inTubeVolume_uL;
                    
                    % set priming flow rate (uL/min)
                    self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin',...
                        self.testbenchObj.AppSettings.AssayParams.PrimeFluidicChannelVelocity_uLpMin);
                    msg = strcat('Setting channel priming flow rate (uL/min) = ', ...
                        num2str(self.testbenchObj.AppSettings.AssayParams.PrimeFluidicChannelVelocity_uLpMin));
                    self.testbenchObj.msg(msg);
                    
                    % start pump and wait until volume is reached
                    msg = '...Waiting for reagent to reach sensor...';
                    self.testbenchObj.msg(msg);
                    self.testbenchObj.msg(self.testbenchObj.instr.pump.stop()); %jtk added 3/17/2014
                    
                    % 3/18/2014 shon - set pump purge flow rate (in rpm's until bug is fixed)
                    self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', self.testbenchObj.AppSettings.AssayParams.PrimeFluidicChannelVelocity_uLpMin);
                    self.testbenchObj.instr.pump.start();
                    
                    while pumpedVolume < targetVolume
                        pumpedVolume = self.testbenchObj.instr.pump.getPumpedVolume;
                        msg = strcat('...PumpedVol (uL)= ', ...
                            num2str(round(pumpedVolume)),...
                            '...Target= ',...
                            num2str(round(targetVolume)));
                        self.testbenchObj.msg(msg);
                        pause(5); % arbitrary
                    end
                end
                
                % Check for StopPumpDuringScan
                if self.testbenchObj.AppSettings.AssayParams.StopPumpDuringScan
                    msg = 'Stopping pump for data acquisition';
                    self.testbenchObj.msg(msg);
                    self.testbenchObj.msg(self.testbenchObj.instr.pump.stop());
                else % set pump flow rate back to recipe file value
                    if self.testbenchObj.recipe.velocity(self.currentRecipeIndex) == 0 % used to flush the channel but for no scans
                        msg = strcat('Flow rate (uL/min) = 0. Not starting pump.');
                        self.testbenchObj.msg(msg);
                        self.testbenchObj.msg(self.testbenchObj.instr.pump.stop());
                    else
                        self.testbenchObj.msg(self.testbenchObj.instr.pump.stop());
                        self.testbenchObj.instr.pump.setParam('FlowRate_uLpMin', self.testbenchObj.recipe.velocity(self.currentRecipeIndex))
                        % start pump
                        self.testbenchObj.instr.pump.start();
                        msg = strcat('Setting flow rate (uL/min) = ', ...
                            num2str(self.testbenchObj.recipe.velocity(self.currentRecipeIndex)));
                        self.testbenchObj.msg(msg);
                    end
                end
            else
                self.testbenchObj.msg('Pump or fluidic stage not connected.');
            end
        end
        
        function tuneThermalControl(self)
            if self.testbenchObj.instr.thermalControl.isConnected
                % Set temperature
                if self.testbenchObj.recipe.temp(self.currentRecipeIndex) ~= 0 % 0 = turn TEC off, otherwise, TEC on
                    self.testbenchObj.instr.thermalControl.setTargetTemp(self.testbenchObj.recipe.temp(self.currentRecipeIndex));
                    % turn the TEC on
                    self.testbenchObj.instr.thermalControl.start();
                    if self.testbenchObj.AppSettings.AssayParams.WaitForTempStabilization
                        % start timer for timeout
                        ticTempStart = tic;
                        % add 2 digits (for xx) to precision parameter since we read xx.yyy
                        precision = self.testbenchObj.AppSettings.AssayParams.TempComparisonPrecision + 2;
                        tolerance = self.testbenchObj.AppSettings.AssayParams.TempComparisonTolerance;
                        elapsedTempTime = toc(ticTempStart);
                        % read temp and apply precision
                        targetTemp = double(vpa(self.testbenchObj.recipe.temp(self.currentRecipeIndex), precision));
                        TECTemp = self.testbenchObj.instr.thermalControl.currentTemp;
                        currentTemp = double(vpa(TECTemp, precision));
                        % wait until temp is reached or timeout occurs
                        while (elapsedTempTime/60 < self.testbenchObj.AppSettings.AssayParams.WaitForTempTimeout_min) && ...
                                (abs(currentTemp - targetTemp) >= tolerance)
                            %% check for stop. If true, abort
                            self.checkUserIntervention();
                            if self.stopReq
                                return
                            end
                            pause(2); % this is arbitrary
                            % read temp and apply precision
                            TECTemp = self.testbenchObj.instr.thermalControl.currentTemp;
                            currentTemp = double(vpa(TECTemp, precision));
                            msg = strcat('Waiting for temperature to stabilize.',...
                                sprintf('\n\tCurrentTemp (C) = %s', num2str(currentTemp)),...
                                sprintf('\n\tTargetTemp (C) = %s', num2str(targetTemp)),...
                                sprintf('\n\tElapsedTime (min) = %s', num2str(round(elapsedTempTime/60))));
                            self.testbenchObj.msg(msg);
                            elapsedTempTime = toc(ticTempStart);
                        end
                        % error handling and user message
                        if (elapsedTempTime/60 >= self.testbenchObj.AppSettings.AssayParams.WaitForTempTimeout_min) || ...
                                (abs(currentTemp - targetTemp) >= tolerance)
                            % pop-up window for user
                            % shons note: need to add stop functionality to this
                            message = sprintf('Target temperature not reached.\nDo you want to continue?');
                            response = questdlg(...
                                message, ...
                                'ERROR', ...
                                'Yes', 'No', 'Yes');
                            if clstrcmp(response, 'No')
                                return;
                            end
                        else
                            msg = strcat(...
                                sprintf('Temperature reached.\n\tCurrentTemp = %s', num2str(currentTemp)),...
                                sprintf('\n\tTargetTemp = %s', num2str(targetTemp)),...
                                sprintf('\n\tElapsedTime = %s', num2str(round(elapsedTempTime/60))));
                            self.testbenchObj.msg(msg);
                        end
                    end
                else
                    % turn the TEC off (ie: temp in recipe file = 0)
                    self.testbenchObj.instr.thermalControl.stop();
                end
            else
                self.testbenchObj.msg('TEC not connected. Skipping thermal tuning.');
            end % thermal tuning and temp stabilization
        end
        
        function moveToNextDevice(self)
            self.currentDevice = self.testbenchObj.devices.(self.testbenchObj.chip.CurrentLocation);
            self.targetDevice = self.testbenchObj.devices.(self.deviceNames{self.currentDeviceIndex});
            moveToDevice(self.testbenchObj, self.currentDevice, self.targetDevice);
            % Check to see if temp data dir exists. If not, create
            self.targetDevice.checkDirectory(self.generalFilePath,...
                self.testbenchObj.AppSettings.infoParams.Task,...
                self.dateTag, self.testbenchObj.AppSettings.infoParams.School);
            
            % Fine Align device (either each new device or new reagent (for single device)
% shon 11 December 2014
%             if self.testbenchObj.instr.pump.isConnected && self.testbenchObj.recipe.velocity(self.currentRecipeIndex) == 0
%                 % used to flush the channel and assuming no scans
%                 % skip fine_align to save time
%                 self.testbenchObj.msg('Skipping fine_align.');
%             else
                fine_align(self.testbenchObj, 'panel', self.testPanel);
%             end
            self.updateTestCtlUIStatus();
        end
        
        function updateTestCtlUIStatus(self)
            % update status
            msg = strcat(num2str((self.currentRecipeIndex-1) * self.numOfDevices + self.currentDeviceIndex), ...
                '/', ...
                num2str(self.totalNumberOfSteps));
            set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.progressDisplay, 'String', msg);
            set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.currentDeviceDisplay, 'String', self.targetDevice.Name);
            self.testbenchObj.gui.panel(self.testPanel).assayUI.deviceTable{self.currentDeviceIndex, 2} = 'Testing';
            set(self.testbenchObj.gui.panel(self.testPanel).assayUI.resultTable, 'Data', self.testbenchObj.gui.panel(self.testPanel).assayUI.deviceTable);
        end
        
        function notificationAtReagentChanges(self)
            if self.currentRecipeIndex > 1 % Only notify user when the text enters the second and subsequent reagents
                % Get the scan number when reagent changes
                thisScan = self.targetDevice.getScanNumber;
                if isempty(self.reagentChangeScan) % for case of first time...
                    self.reagentChangeScan(1) = thisScan;
                elseif self.reagentChangeScan(end) ~= thisScan
                    self.reagentChangeScan(end + 1) = thisScan;
                end
                % Plot the peak tracking on a popup window when reagent changes
                if strcmpi(self.testType, 'BioAssay')
                    % Send an email when reagent changes
                    peaksCellN = self.targetDevice.getNormalizedTrackedPeakLocations();
                    tempF = figure;
                    tempA = [];
                    tempIndex = 0;
                    for ii = 1:self.numDetectors
                        if (self.selectedDetectors(ii))
                            tempIndex = tempIndex + 1;
                            tempA(tempIndex) = subplot(sum(self.selectedDetectors), 1, tempIndex);
                            hold(tempA(tempIndex), 'on')
                            for p = 1:length(peaksCellN{ii})
                                plot(tempA(tempIndex), 1:length(peaksCellN{ii}{p}), peaksCellN{ii}{p}, self.colors{p});
                            end
                            yLimit = get(tempA(tempIndex), 'ylim');
                            for rc = 1:length(self.reagentChangeScan)
                                plot(tempA(tempIndex), self.reagentChangeScan(rc)*ones(1, 10), linspace(yLimit(1), yLimit(2), 10), 'k--');
                                text(self.reagentChangeScan(rc) + 1, yLimit(2)*0.8 + yLimit(1)*0.2, self.testbenchObj.recipe.reagent{rc}, 'FontSize', 11, 'FontWeight', 'bold');
                            end
                            title(tempA(tempIndex), sprintf('Real Time Peak Tracking\nDevice: %s\nDetector: %d', self.targetDevice.Name, ii));
                            xlabel(tempA(tempIndex), 'Scan Number');
                            ylabel(tempA(tempIndex), 'Wavelength Shift [pm]');
                            hold(tempA(tempIndex), 'off')
                        end
                    end
                    if ~isempty(tempA) && self.testbenchObj.AppSettings.FinishTestSettings.SendEmail
                        file = strcat(self.testbenchObj.AppSettings.path.tempData, 'tempFig.pdf');
                        print(tempF, '-dpdf', file);
                        try
                            sendEmail(self.testbenchObj.AppSettings.infoParams.Email, 'Reagent Change', sprintf('%s @ %s', self.targetDevice.Name, self.reagentInChannel), file);
                        end
                        delete(file);
                    end
                    close(tempF);
                end
            end
        end
        
        function setUpTestTiming(self)
            % sweep (loop based on recipe time or number of iterations)
            if self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                self.reagentTimeLeft = -inf; % disable
                self.numberOfSweepsLeft = round(self.testbenchObj.recipe.time(self.currentRecipeIndex)); % put in # of sweeps
            else % use timer
                self.numberOfSweepsLeft = -inf; % disable
                self.reagentTimeTotal = self.testbenchObj.recipe.time(self.currentRecipeIndex)*60; % put in sec
                self.reagentTimeTic = tic;
                self.reagentTimeLeft = eps; % sec
            end
        end
        
        function saveScanResults(self, wvlData, pwrData)
            % save data to object and disk
            % params to save with each scan
            if self.testbenchObj.instr.pump.isConnected && (self.testbenchObj.recipe.well(self.currentRecipeIndex) ~= 0)
                flowRate = self.testbenchObj.instr.pump.getParam('FlowRate_uLpMin');
            else
                flowRate = 0;
            end
            currentTemp = self.testbenchObj.instr.thermalControl.currentTemp;
            otherInfo = struct(...
                'CurrentWell', self.testbenchObj.instr.fluidicStage.CurrentWell,...
                'ReagentName', self.reagentInChannel,...
                'ReagentRI', self.reagentRIInChannel,...
                'StageTemp', currentTemp,...
                'FlowRate', flowRate, ...
                'BioAssayQuickNote', self.BioAssayNote);
            params = scanParams(self.testbenchObj); % testbench equipment params to save with data
            params = catstruct(params, otherInfo);
            
            % save data
            self.targetDevice.saveData(wvlData, pwrData, params, self.testbenchObj.AppSettings.infoParams.School);
            % save plots
            if self.testbenchObj.AppSettings.AssayParams.SavePlots
                self.targetDevice.savePlot(wvlData, pwrData,self.testbenchObj.AppSettings.infoParams.School);
            end
        end
        
        function plotScanResults(self)
            % Plot sweep results
            plotIndex = 0;
            previousSweep = self.targetDevice.getProp('PreviousSweep');
            thisSweep = self.targetDevice.getProp('ThisSweep');
            for ii = 1:self.numDetectors
                if (self.selectedDetectors(ii))
                    plotIndex = plotIndex + 1;
                    plot(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), thisSweep(ii).wvl, thisSweep(ii).pwr, 'b');
                    if ~isempty(previousSweep)
                        hold(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), 'on')
                        plot(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), previousSweep(ii).wvl, previousSweep(ii).pwr, 'g--');
                        hold(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), 'off')
                    end
                    xlabel(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), 'Wavelength(nm)');
                    ylabel(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), 'Power(dBW)');
                    title(self.testbenchObj.gui.panel(self.testPanel).sweepScanPlots(plotIndex), ['Detector ', num2str(ii), ' real-time scan']);
                end
            end
            
            % If there is peak selected, plot peak window and tracking
            if self.targetDevice.hasPeakSelected
                % Start - Vince add this part to check the shift between first two scan
                %                 if targetDevice.getScanNumber == 1
                %                     figure;
                %                     plotIndex = 0;
                %                     peaksCell = targetDevice.getTrackedPeakLocations();
                %                     previousSweep = targetDevice.getProp('PreviousSweep');
                %                     numOfSelected = sum(selectedDetectors);
                %                     for ii = 1:numDetectors
                %                         if selectedDetectors(ii)
                %                             plotIndex = plotIndex + 1;
                %                             subplot(numOfSelected, 1, plotIndex);
                %                             hold on;
                %                             plot(wvlData(:, ii), pwrData(:, ii), 'b');
                %                             plot(previousSweep(ii).wvl, previousSweep(ii).pwr, 'g--');
                %                             for p = 1:length(peaksCell{ii})
                %                                 plot(peaksCell{ii}{p}(1), previousSweep(ii).pwr(previousSweep(ii).wvl == peaksCell{ii}{p}(1)), 'r+');
                %                             end
                %                             title(['Detector ', num2str(ii)]);
                %                             xlabel('Wavelength [nm]');
                %                             ylabel('Power [dB]');
                %                             hold off;
                %                         end
                %                     end
                %                 end
                % End - Vince add this part to check the shift between first two scan - End
                
                % After peak tracking
                peaksCellN = self.targetDevice.getNormalizedTrackedPeakLocations();
                peaksWindow = self.targetDevice.getPeakTrackWindows();
                plotIndex = 0;
                for ii = 1:self.numDetectors
                    if (self.selectedDetectors(ii))
                        plotIndex = plotIndex + 1;
                        for p = 1:length(peaksCellN{ii})
                            if ~isempty(previousSweep)
                                previousWvlWindow = previousSweep(ii).wvl(peaksWindow{ii}{p});
                                previousPwrWindow = previousSweep(ii).pwr(peaksWindow{ii}{p});
                            end
                            thisWvlWindow = thisSweep(ii).wvl(peaksWindow{ii}{p});
                            thisPwrWindow = thisSweep(ii).pwr(peaksWindow{ii}{p});
                            
                            % Plot the peak window
                            plot(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), thisWvlWindow, thisPwrWindow, 'b');
                            if ~isempty(previousSweep)
                                hold(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), 'on')
                                plot(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), previousWvlWindow, previousPwrWindow, 'g--');
                                hold(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), 'off')
                            end
                            xlim(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), [thisWvlWindow(1), thisWvlWindow(end)]);
                            title(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), strcat(['Detector ',num2str(ii),' peak window']));
                            xlabel(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), 'Wavelength [nm]');
                            ylabel(self.testbenchObj.gui.panel(self.testPanel).PeakWindowPlots(plotIndex), 'Power [dBW]')
                            
                            % Plot the peak tracking
                            plot(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 1:length(peaksCellN{ii}{p}), peaksCellN{ii}{p}, self.colors{p});
                            xlim(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), [1, max(length(peaksCellN{ii}{p}), 2)]);
                            title(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), strcat(['Detector ',num2str(ii),' peak tracking']));
                            xlabel(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'Scan Number');
                            ylabel(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'Wavelength shift [pm]');
                            hold(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'on')
                        end
                        yLimit = get(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'ylim');
                        for rc = 1:length(self.reagentChangeScan)
                            plot(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), self.reagentChangeScan(rc)*ones(1, 10), linspace(yLimit(1), yLimit(2), 10), 'k--');
                            text(self.reagentChangeScan(rc) + 1, yLimit(2)*0.8 + yLimit(1)*0.2, sprintf('#%d', rc), 'Parent', self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'FontSize', 8, 'FontWeight', 'bold');
                        end
                        hold(self.testbenchObj.gui.panel(self.testPanel).peakTrackPlots(plotIndex), 'off')
                    end
                end
            end
        end
        
        function updateAssayTable(self)
            % Update scan number
            currentScanNumber = self.targetDevice.getScanNumber();
            set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.scanNumberDisplay, 'String', num2str(currentScanNumber));
            % update elapsed time
            elapsedTimeSec = toc(self.ticID); % sec
            set(self.testbenchObj.gui.panel(self.testPanel).testControlUI.elapsedTimeDisplay, 'String', num2str(round(elapsedTimeSec/60)));
            
            remaining = self.getRemainingTime();
            
            % Update assay table: highlight current reagent and device
            assayUpdateTable(self.testbenchObj, self.currentRecipeIndex, self.currentDeviceIndex, remaining);
            % Update pumped volume
            set(self.testbenchObj.gui.panel(self.testPanel).assayUI.pumpedVolumeDisp, 'String', num2str(round(self.testbenchObj.instr.pump.getPumpedVolume)/1000)); % mL
        end
        
        function remaining = getRemainingTime(self)
            if self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                if self.skipToNextStepReq
                    self.numberOfSweepsLeft = 0;
                    % reset 'skip to next step' button
                    set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'UserData', 0); % skip to next step
                    set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'Enable', 'on');
                else
                    self.numberOfSweepsLeft = self.numberOfSweepsLeft - 1;
                end
                % update recipe table in assay panel for sweeps
                remaining = num2str(self.numberOfSweepsLeft);
            else % use timer
                self.reagentTimeLeft = self.reagentTimeTotal + self.pauseTime - ...
                    toc(self.reagentTimeTic); % sec
                if (self.reagentTimeLeft < 0) || (self.skipToNextStepReq)
                    self.reagentTimeLeft = 0;
                    % reset 'skip to next step' button
                    set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'UserData', 0); % skip to next step
                    set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'Enable', 'on');
                end
                % update recipe table in assay panel for time
                remaining = strcat(num2str(round(self.reagentTimeLeft/60)), 'min');
            end
        end
        
        function checkRecipePause(self)
            if self.testbenchObj.recipe.pauseRecipe(self.currentRecipeIndex)
                pauseStart = tic;
                % Stop the Pump
                if self.testbenchObj.instr.pump.Connected
                    msg = self.testbenchObj.instr.pump.stop();
                    self.testbenchObj.msg(msg);
                end
                self.testbenchObj.msg('<<<<<<<<<<  Test Pause.  >>>>>>>>>>');
                
                if self.testbenchObj.AppSettings.FinishTestSettings.SendEmail
                    sendEmail(self.testbenchObj.AppSettings.infoParams.Email, 'Optical setup paused', 'Get your ass back in the lab.')
                end
                msg = sprintf('Experiment:%s is paused\nNotification email is sent to user: %s\n\t%s\n\nPlease Click OK to continue.', test_type, self.testbenchObj.AppSettings.infoParams.Name, self.testbenchObj.AppSettings.infoParams.Email);
                uiwait(msgbox(msg, 'Test Paused'));
                
                self.testbenchObj.msg('<<<<<<<<<<  Test Resume.  >>>>>>>>>>');
                % start pump
                if self.testbenchObj.instr.pump.Connected
                    self.testbenchObj.instr.pump.start();
                    self.testbenchObj.msg('Re-starting pump');
                end
                
                pauseTime = toc(pauseStart);
                if ~self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                    self.reagentTimeTotal = self.reagentTimeTotal + pauseTime;
                end
            end
        end
        
        function checkUserIntervention(self)
%             if self.stopReq
%                 return
%             end
            % Check for 'pause' or 'stop' or 'skip' by user
            self.pauseReq = get(self.testbenchObj.gui.panel(self.testPanel).testControlUI.pauseButton, 'UserData'); % pause
            if ~self.stopReq
                self.stopReq = get(self.testbenchObj.gui.panel(self.testPanel).testControlUI.stopButton, 'UserData'); % stop
            end
            self.skipToNextStepReq = get(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'UserData'); % skip to next step

            if self.stopReq
                % Check for stop. If true, abort
                if self.testbenchObj.instr.pump.isConnected
                    self.testbenchObj.msg(self.testbenchObj.instr.pump.stop());
                end
                if self.testbenchObj.instr.thermalControl.Connected && self.testbenchObj.instr.thermalControl.Busy
                    self.testbenchObj.instr.thermalControl.stop();
                end
                self.stopTest();
                cancelTest(self.testbenchObj, self.generalFilePath, self.dateTag)
            elseif self.pauseReq
                % Check for pause. If true, pause the test
                % ****** Vince: Need to update assay timing after pause ******
                pauseTime = pauseTest(self.testbenchObj);
                if ~self.testbenchObj.AppSettings.AssayParams.TranslateRecipeTimeToSweeps
                    self.reagentTimeTotal = self.reagentTimeTotal + pauseTime;
                end
            elseif self.skipToNextStepReq
                % reset skipToNextStep button
                set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'UserData', false); % reset flag
                set(self.testbenchObj.gui.panel(self.testPanel).assayUI.skipToNextStepButton, 'Enable', 'on'); % re-enable button
            end
        end
    end
end
