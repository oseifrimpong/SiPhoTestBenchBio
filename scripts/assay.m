function assay(obj)
% Shon Schmidt 2013/ Vince Wu 2014

test_type = obj.AppSettings.infoParams.Task;
testPanel = panel_index('test');

%% Initiate Assay Control Class
if exist('obj.assayCtl', 'class')
    delete(obj.assayCtl);
end
if strcmpi(test_type, 'BioAssay') || strcmpi(test_type, 'SaltSteps')
    if isempty(obj.assayCtl) || ~strcmpi(class(obj.assayCtl), 'AssayCtlClass')
        obj.assayCtl = AssayCtlClass(obj);
    end
end

%% Start Assay and Setup
obj.msg('<<<<<<<<<< Starting Assay Setup >>>>>>>>>');
obj.assayCtl.startTest();

%% Assay orchestration
obj.msg('<<<<<<<<<<  Start Test  >>>>>>>>>>')
obj.assayCtl.orchestrateTest('Start') % Or "Continue"

%% Finish Test
obj.assayCtl.finishTest();

% Re-enable buttons
set(obj.gui.panel(testPanel).testControlUI.stopButton, 'UserData', false); % stop
set(obj.gui.panel(testPanel).testControlUI.stopButton, 'Enable', 'off');
set(obj.gui.panel(testPanel).testControlUI.pauseButton, 'Enable', 'off');
set(obj.gui.panel(testPanel).testControlUI.startButton, 'Enable', 'on');

obj.msg('<<<<<  Test Finished.  >>>>>');

% Pop-up window for user
message = sprintf('Test finished.\nClick OK to continue');
uiwait(msgbox(message));
end