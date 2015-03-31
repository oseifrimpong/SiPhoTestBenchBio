% targetDevice should be the name (string) of a device object
function obj = selectPeaks(obj, targetDevice)
% select peaks popup that will graph the wavelength Vs. power output of
% each detector unit on a separate axes and allow the user to pick peaks on
% each graph to track by saving them to the device object specified
% Victor Bass 2013
% Modified by Vince Wu - Nov 2013

% targetDevice is the name of the device
% Reset device scan datas
obj.devices.(targetDevice).resetScanNumber();

% Get the number of detectors
numDetectors = obj.instr.detector.getProp('NumOfDetectors');
obj.devices.(targetDevice).isPeak = zeros(1, numDetectors);

obj.devices.(targetDevice).PeakLocations = cell(1, numDetectors);
obj.devices.(targetDevice).PeakLocationsN = cell(1, numDetectors);
obj.devices.(targetDevice).PeakTrackWindows = cell(1, numDetectors);

instructions{1} = 'Press the Start button to begin peak tracking';
instructions{2} = 'Left click near a peak to select for tracking.';
instructions{3} = 'Right click when finished';
instructions{4} = 'Click ''Done'' to save peaks';

obj.gui.selectPeaksPopup.mainWindow = figure(...
    'Unit', 'normalized', ...
    'Position', [0, 0, 0.68, 0.85],...
    'Menu', 'None',...
    'Name', sprintf('PEAK TRACKER: %s', targetDevice),...
    'WindowStyle', 'normal',...  % normal , modal, docked.
    'Visible', 'off',...
    'NumberTitle', 'off',...
    'CloseRequestFcn', {@closeWindow});

% main panel
obj.gui.selectPeaksPopup.mainPanel = uipanel(...
    'parent', obj.gui.selectPeaksPopup.mainWindow,...
    'BackgroundColor',[0.9 0.9 0.9],...
    'Visible','on',...
    'Units', 'normalized', ...
    'Position', [.005, .005, .990, .990]);

% title string
obj.gui.selectPeaksPopup.stringTitle = uicontrol(...
    'Parent', obj.gui.selectPeaksPopup.mainPanel,...
    'Style', 'text',...
    'HorizontalAlignment','center',...
    'BackgroundColor',[0.9 0.9 0.9 ],...
    'Units', 'normalized',...
    'String','Peaks Selection and Tracking',...
    'FontSize', 13, ...
    'FontWeight','bold',...
    'Position', [.3, .95, .4, .035]);

% instructions string
obj.gui.selectPeaksPopup.instructionString = uicontrol(...
    'parent', obj.gui.selectPeaksPopup.mainPanel,...
    'Style', 'text',...
    'BackgroundColor',[0.9 0.9 0.9 ],...
    'Units', 'normalized', ...
    'Position', [.30, .91, .4, .035],...
    'String', 'INSTRUCTIONS:', ...
    'FontWeight','bold',...
    'FontSize', 12);

% dynamic instructions box
obj.gui.selectPeaksPopup.instructions = uicontrol(...
    'parent', obj.gui.selectPeaksPopup.mainPanel,...
    'Style', 'text',...
    'BackgroundColor',[0.9 0.9 0.9 ],...
    'Units', 'normalized',...
    'Position', [.30, .87, .4, .035],...
    'String', instructions{1}, ...
    'FontWeight', 'bold', ...
    'FontSize', 11, ...
    'ForegroundColor', [0, 0, 1]);

% save and close button
obj.gui.selectPeaksPopup.save_and_close_button = uicontrol(...
    'parent', obj.gui.selectPeaksPopup.mainPanel,...
    'Style', 'pushbutton',...
    'units', 'normalized',...
    'String', 'SAVE & CLOSE',...
    'FontWeight', 'bold', ...
    'Enable', 'on',...
    'Position', [0.73, 0.87, 0.12, 0.05],...
    'Callback', {@save_and_close_cb, obj, targetDevice, numDetectors});

%% Generate Axes
plotPanel_w = 0.62;
plotPanel_h = 0.85;
% axes panel
obj.gui.selectPeaksPopup.plotPanel = uipanel(...
    'parent', obj.gui.selectPeaksPopup.mainPanel,...
    'Title', 'Sweep Data', ...
    'FontWeight', 'bold', ...
    'FontSize', 11, ...
    'BackgroundColor', [0.9, 0.9, 0.9],...
    'Visible', 'on',...
    'Units', 'normalized',...
    'Position', [0.01, 0.01, plotPanel_w, plotPanel_h]);

for i = 1:numDetectors
    % draw axes
    obj.gui.selectPeaksPopup.sweepScanSubplot(i)= subplot(numDetectors, 1, i);
    set(obj.gui.selectPeaksPopup.sweepScanSubplot(i), ...
        'Parent', obj.gui.selectPeaksPopup.plotPanel, ...
        'Units', 'normalized');
    axePosition = get(obj.gui.selectPeaksPopup.sweepScanSubplot(i), 'Position');
    axePosition(1) = 0.08;
    axePosition(2) = 1.01 - axePosition(4)*1.5*i;
    set(obj.gui.selectPeaksPopup.sweepScanSubplot(i), ...
        'Position', axePosition)
    xlabel('Wavelength [nm]');
    ylabel('Power [dBm]');
    title(strcat(['Detector ', num2str(i)]));
   
    % checkbox for resonant peak vs. null
    obj.gui.selectPeaksPopup.maximaCheckBox(i) = uicontrol(...
        'Parent', obj.gui.selectPeaksPopup.plotPanel,...
        'Style', 'checkbox',...
        'units', 'normalized',...
        'position', [.87, axePosition(2) + axePosition(4)*0.81, .12, axePosition(4)*0.17],...
        'string', 'Choose Maxima',...
        'Enable', 'on',...
        'callback', {@peak_button_cb, obj, targetDevice, i});
    
    % start button for peak selection
    obj.gui.selectPeaksPopup.startButton(i) = uicontrol(...
        'Parent', obj.gui.selectPeaksPopup.plotPanel,...
        'Style', 'pushbutton',...
        'units', 'normalized',...
        'position', [.87, axePosition(2) + axePosition(4)*0.66, .12, axePosition(4)*0.17],...
        'string', 'Start',...
        'Enable', 'on',...
        'callback', {@start_button_cb, obj,instructions, i});
    
    % done button for peak selection
    obj.gui.selectPeaksPopup.doneButton(i) = uicontrol(...
        'Parent', obj.gui.selectPeaksPopup.plotPanel,...
        'Style', 'pushbutton',...
        'units', 'normalized',...
        'position', [.87, axePosition(2) + axePosition(4)*0.48, .12, axePosition(4)*0.17],...
        'string', 'Done',...
        'userData', false, ...
        'Enable', 'off', ...
        'callback', {@done_button_cb, obj,instructions, targetDevice, i});
    
%     % select peak tracking window button 
%     obj.gui.selectPeaksPopup.peakTrackWindowButton(i) = uicontrol(...
%         'Parent', obj.gui.selectPeaksPopup.plotPanel,...
%         'Style', 'pushbutton',...
%         'units', 'normalized',...
%         'position', [.87, axePosition(2) + axePosition(4)*0.48, .12, axePosition(4)*0.17],...
%         'string', 'Window',...
%         'userData', false, ...
%         'Enable', 'off', ...
%         'callback', {@selectPeakTrackWindow_cb, obj, targetDevice, i});
    
    % Table to show selected wvls
    PeakLocations = {};
    obj.gui.selectPeaksPopup.peaksTable(i) = uitable(...
        'Parent', obj.gui.selectPeaksPopup.plotPanel,...
        'ColumnName', {'Wvl', 'LeftInd', 'RightInd'},...
        'ColumnFormat',{'char', 'char', 'char'},...
        'ColumnEditable', false,...
        'Units','normalized',...
        'Position', [0.87, axePosition(2)-0.02, 0.12, axePosition(4)*0.6],...
        'Data', PeakLocations,...
        'FontSize', 9,...
        'ColumnWidth', {50},...
        'CellEditCallback',{@cell_edit_cb, i},...
        'CellSelectionCallback', {@cell_sel_cb, i},...
        'Enable', 'on');
end

%% Create Data Storage Directory
% if (~obj.devices.(targetDevice).hasDirectory)
%     filePath = createTempDataPath(obj);
%     dateTag = datestr(now,'yyyy.mm.dd@HH.MM'); % time stamp
%     obj.devices.(targetDevice).checkDirectory(filePath, obj.AppSettings.infoParams.Task, dateTag);
% end

%% INSTR UI PANELS
% UI parameters (position)
ui_x = plotPanel_w + 0.015;
ui_y = 0.01;
ui_width = 0.99 - ui_x;
ui_height = 0;
ui_position = [ui_x, ui_y, ui_width, ui_height];

% Optical Stage UI
if (obj.instr.opticalStage.Connected)
    ui_position(4) = 0.26;
    obj = optical_stage_ui(...
        obj, ...
        'selectPeaks', ...
        obj.gui.selectPeaksPopup.mainPanel, ...
        ui_position);
end

% Laser UI
if (obj.instr.laser.Connected)
    ui_position(2) = ui_position(2) + ui_position(4);
    ui_position(4) = 0.26;
    obj = laser_ui(...
        obj, ...
        'selectPeaks', ...
        obj.gui.selectPeaksPopup.mainPanel, ...
        ui_position, ...
        obj.gui.selectPeaksPopup.sweepScanSubplot);
end

% Detector UI
if (obj.instr.detector.Connected)
    ui_position(2) = ui_position(2) + ui_position(4);
    ui_position(4) = 0.85 - ui_position(2);
    obj = detector_ui(...
        obj, ...
        'selectPeaks', ...
        obj.gui.selectPeaksPopup.mainPanel, ...
        ui_position);
end

% ************************ For test mode only ************************
test_type = obj.AppSettings.infoParams.Task;
if strcmpi(test_type, 'VirtualTestMode')
%     obj.AppSettings.path.testModeData = ...
%         [obj.AppSettings.path.testModeData, strrep(obj.AppSettings.infoParams.ChipArchitecture, '_', '\'), '\', obj.devices.(targetDevice).Name, '\'];
    obj.AppSettings.path.testModeData = uigetdir(obj.AppSettings.path.testModeData, ...
        'Choose the test data directory');
    obj.AppSettings.path.testModeData = [obj.AppSettings.path.testModeData, '\'];
    scan1DataName = [obj.AppSettings.path.testModeData, 'Scan1.mat'];
    scan1 = load(scan1DataName);
    scan1 = scan1.scanResults;
    for d = 1:numDetectors
        scan1Wvl = scan1(d).Data(:, 1);
        scan1Pwr = scan1(d).Data(:, 2);
        plot(obj.gui.selectPeaksPopup.sweepScanSubplot(d), scan1Wvl(1:end-1), scan1Pwr(1:end-1));
        xlabel('Wavelength [nm]');
        ylabel('Power [dBm]');
        title(strcat(['Detector ', num2str(d)]));
    end
end
% ************************ For test mode only ************************

movegui(obj.gui.selectPeaksPopup.mainWindow, 'center');
set(obj.gui.selectPeaksPopup.mainWindow, 'Visible', 'on');

end % ends SelectPeaks Popup

%% SELECT PEAKS FROM PLOT
function peak_selection(obj, instructions, index) % --- Vince 2013
PeakInfo = {};

isMaxima = get(obj.gui.selectPeaksPopup.maximaCheckBox(index), 'Value');
defaultWindowSize = [2, 2]; %nm

% Delete the previous (if any) peak selection
delete(findobj(obj.gui.selectPeaksPopup.sweepScanSubplot(index), 'Marker', '+'));
set(obj.gui.selectPeaksPopup.peaksTable(index), 'Data', {});

%this is not good: can't reset peak locations.
dataObj = get(obj.gui.selectPeaksPopup.sweepScanSubplot(index), 'Children');
wvlVals = get(dataObj(end), 'XData'); % Use 'end' to temporary fix the bug
pwrVals = get(dataObj(end), 'YData'); % Use 'end' to temporary fix the bug
% WinPoints = 5/(wvlVals(2)-wvlVals(1)); % window/step = num of elements: for a 2nm window;
xrange = max(wvlVals) - min(wvlVals);
tol = xrange/100;
n = 0;
hold(obj.gui.selectPeaksPopup.sweepScanSubplot(index), 'on');
finish = false;
PeakInfo = cell(10,2); % preallocate for speed, assume less than 10 peaks selected
while (~finish)
    [xsel, ysel, button] = ginput(1);
    % get x,y coord of mouse cursor
    % button is an integer indicating which mouse buttons you pressed
    % (1 for left, 2 for middle, 3 for right)
    if (button == 1) %user - left-click
        boundary = ...
            xsel <= max(wvlVals) && xsel >= min(wvlVals) && ...
            ysel <= max(pwrVals) && ysel >= min(pwrVals);
        if (boundary) % Process data only when user click with in the proper axes
            % Limit the range of wavelength selection
            wvlVals_filter = wvlVals(abs(wvlVals - xsel) <= tol);
            pwrVals_filter = pwrVals(abs(wvlVals - xsel) <= tol);
            
            % Find the peak power value within the limited range above
            if isMaxima
                [pwrPeak, ind] = max(pwrVals_filter); % look for index of min y in range
            else
                [pwrPeak, ind] = min(pwrVals_filter); % look for index of min y in range
            end
            wvlPeak = wvlVals_filter(ind);
            
            % update plot /w X on selected point
            plot(obj.gui.selectPeaksPopup.sweepScanSubplot(index), wvlPeak, pwrPeak, 'r+'); % make a red-x at point
            n = n + 1;
            if n > 10
                error('Cannot select more than 10 peaks');
            end
            
            % Set window size for the selected peak ------------
            windowSelF = figure(...
                'Unit', 'normalized', ...
                'Position', [0, 0, 0.33, 0.33],...
                'Menu', 'None',...
                'Name', 'Please Specify Window Size',...
                'NumberTitle', 'off');
            windowSelA = axes('Parent', windowSelF);
            windowLeftIndex = find(wvlVals - (wvlPeak - defaultWindowSize(1)) <= 0);
            if ~isempty(windowLeftIndex)
                windowLeftIndex = windowLeftIndex(end);
            else
                windowLeftIndex = 1;
            end
            windowRightIndex = find(wvlVals - (wvlPeak + defaultWindowSize(1)) <= 0);
            windowRightIndex = windowRightIndex(end);
            defaultWvlWindow = wvlVals(windowLeftIndex:windowRightIndex);
            defaultPwrWindow = pwrVals(windowLeftIndex:windowRightIndex);
            plot(windowSelA, defaultWvlWindow, defaultPwrWindow, 'b');
            hold(windowSelA, 'on')
            plot(windowSelA, wvlPeak, pwrPeak, 'r+');
            hold(windowSelA, 'off')
            movegui(windowSelF, 'center')
            
            % Set a default value for window size
            windowSize = 3;
            % -----------------------------------
            pause(0.2)
            validWindow = false;
            while ~validWindow
                newWindow = getrect(windowSelA);
                windowSize = newWindow(3);
                wl = newWindow(1);
                wr = wl + windowSize;
                validWindow = (wl < wvlPeak && wvlPeak < wr);
            end
            windowLeft = wvlPeak - windowSize/2;
            windowRight = wvlPeak + windowSize/2;
%             windowLeft = newWindow(1);
%             windowRight = windowLeft + windowSize;
            windowLeftIndex = find(wvlVals - windowLeft <= 0);
            if isempty(windowLeftIndex)
                windowLeftIndex = 1;
            else
                windowLeftIndex = windowLeftIndex(end);
            end
            windowRightIndex = find(wvlVals - windowRight <= 0);
            windowRightIndex = windowRightIndex(end);
            try
                close(windowSelF);
            end
            % ---------------------------------------------------
            
            PeakInfo{n, 1} = wvlPeak;
            PeakInfo{n, 2} = windowLeftIndex;
            PeakInfo{n, 3} = windowRightIndex;
            set(obj.gui.selectPeaksPopup.peaksTable(index), 'Data', PeakInfo);
            set(obj.gui.selectPeaksPopup.instructions, 'String', instructions{3});
        end
    elseif (button == 2 || button == 3)  %user right or middle mouse click
        finish = true;
    end
end
hold(obj.gui.selectPeaksPopup.sweepScanSubplot(index), 'off');
end

%% CALLBACK FUNCTIONS
function closeWindow(hObject, ~)
delete(hObject);
end

function peak_button_cb(hObject, ~, obj, targetDevice, index)
isChecked = get(hObject, 'Value');
if isChecked % set flags for positive peak tracking in device object
    obj.devices.(targetDevice).isPeak(index) = 1; % peak, not null
else % clear settings in device object
    obj.devices.(targetDevice).isPeak(index) = 0; % resonant null, not peak
end
end

function start_button_cb(hObject, ~, obj, instructions, index)
set(hObject, 'Enable', 'off'); % disable the start button that was pressed
% set(obj.gui.selectPeaksPopup.doneButton(index), 'Enable', 'on');
set(obj.gui.selectPeaksPopup.instructions, 'String', instructions{2});
set(obj.gui.selectPeaksPopup.doneButton(index), 'Enable', 'on');
peak_selection(obj,instructions, index);
end

function done_button_cb(hObject, ~, obj, instructions, targetDevice, index)
% save wvls (meters) of selected peaks to device object
% also find the min/max of selected peaks from all detectors and save in
% device object as start and stop wvls
% obj.devices.(targetDevice).PeakLocations{index} = {};
% obj.devices.(targetDevice).PeakLocationsN{index} = {};
% obj.devices.(targetDevice).PeakTrackWindows{index} = {};
obj.devices.(targetDevice).clearPeakSelection(index);

set(obj.gui.selectPeaksPopup.instructions, 'String', instructions{1}); % update displayed instructions
set(obj.gui.selectPeaksPopup.startButton(index), 'Enable', 'on'); % enable start button again
peakInfo = get(obj.gui.selectPeaksPopup.peaksTable(index), 'data');
wvl_data = cell2mat(peakInfo(:, 1)); % get wvl data from table
window_data(:, 1) = cell2mat(peakInfo(:, 2));
window_data(:, 2) = cell2mat(peakInfo(:, 3));
% find min and max of data
data_min = min(wvl_data);
data_max = max(wvl_data);
% save data to the device object
% for ii = 1:length(wvl_data)
%     obj.devices.(targetDevice).PeakLocations{index}{ii} = wvl_data(ii);
%     obj.devices.(targetDevice).PeakLocationsN{index}{ii} = 0;
%     obj.devices.(targetDevice).PeakTrackWindows{index}{ii} = window_data(ii, 1):window_data(ii, 2);
% end
obj.devices.(targetDevice).setPeakSelection(index, wvl_data, window_data);
% determine if overall min/max is within data and set if so
% min (start wvl)
if isempty(obj.devices.(targetDevice).getProp('StartWvl')) % device property not set yet
    obj.devices.(targetDevice).setProp('StartWvl', data_min);
elseif data_min < obj.devices.(targetDevice).getProp('StartWvl') % current start higher than lowest selected peak
    obj.devices.(targetDevice).setProp('StartWvl', data_min);
end
% max (stop wvl)
if isempty(obj.devices.(targetDevice).getProp('StopWvl'))
    obj.devices.(targetDevice).setProp('StopWvl', data_max);
elseif data_max > obj.devices.(targetDevice).getProp('StopWvl')
    obj.devices.(targetDevice).setProp('StopWvl', data_max);
end

set(hObject, 'Enable', 'off'); % disable done button that was pushed

% enable selectPeakTracking window button
% set(obj.gui.selectPeaksPopup.peakTrackWindowButton(index), 'Enable', 'on');
end

function save_and_close_cb(~, ~, obj, targetDevice, numDetectors)
msg = obj.devices.(targetDevice).checkPeakSelection();
obj.msg(msg);
% if obj.devices.(targetDevice).hasPeakSelected
%     if numDetectors > length(obj.devices.(targetDevice).PeakLocations)
%         for index = length(obj.devices.(targetDevice).PeakLocations):numDetectors
%             obj.devices.(targetDevice).PeakLocations{index} = {};
%             obj.devices.(targetDevice).PeakLocationsN{index} = {};
%         end
%     end
%     obj.devices.(targetDevice).trackPeaks();
% end
close(obj.gui.selectPeaksPopup.mainWindow);
obj.gui.popup_peaks = [];
end


function selectPeakTrackWindow_cb(hObject, ~, obj, targetDevice, index)
% pop-up a new window with X nm's of range on either side of the FIRST
% selected peak. After the window is selected, pop-up a new window w/ the
% SECOND peak, etc. until all the selected peaks have tracking windows

% TODO: add a default xRange to the default AppSettigs and load user's pref
xRange_nm = 2; % in nm

% convert nm to # of points (need StepWvl, also in nm)
StepWvl = obj.instr.laser.getProp('StepWvl');
xRange_pts = xRange_nm/StepWvl;

% get the number of peak locations selected for this detector
PeakLocations = get(obj.gui.selectPeaksPopup.peaksTable(index), 'Data');
numPeaks = length(PeakLocations);

% for 1 to n peaks selected, loop
% for ii = 1:numPeaks
%     % pop-up a new window
%     % window should have 'save' 'reselect' 'cancel' buttons
%     popupWinH = new window handle...
%     ... create all the buttons and callbacks ...
%     popupWinFigureH = ... create the figure window ...
% 
%     % TODO: right now, only x_peaks are saved, we also need to save pwr values
% 
%     % plot a portion of the entire pwr/wvl vector
%     % wvlVector =
%     x = (PeakLocations{ii,1}-xRange_pts/2:PeakLocations{ii,1}+xRange_pts/2);
%     y = pwrVals(x);
%     plot(x,y);
% 
%     ... mode to select window, perhaps put some instructions? ...
%     % 
% end

end

function cell_edit_cb(hObject, eventdata, index)
end

function cell_sel_cb(hObject, eventdata, index)
end