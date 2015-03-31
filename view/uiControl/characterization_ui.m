% Vince Wu 2014

function obj = characterization_ui(obj, parentName, parentObj, position)

parentStruct = getParentStruct(parentName);
if (~isempty(strfind(parentStruct, 'panel')))
    panelIndex = str2double(parentStruct(end - 1));
    parentStruct = parentStruct(1:end - 3);
else
    panelIndex = 1;
end

charTest = obj.AppSettings.infoParams.CharacterizationTest;

% Panel element size variables
stringBoxSize = [0.45, 0.03];
pushButtonSize = [0.20, 0.05];
editBoxSize = [0.15, 0.03];

%% Parent Panel
obj.gui.(parentStruct)(panelIndex).charUI.mainPanel = uipanel(...
    'Parent', parentObj, ...
    'Unit', 'Pixels', ...
    'Units', 'normalized', ...
    'Visible', 'on', ...
    'BackgroundColor', [0.9, 0.9, 0.9], ...
    'Title', 'Test Setup Characterization', ...
    'FontSize', 9, ...
    'FontWeight', 'Bold', ...
    'Position', position);

%% test file string
uicontrol(...
    'Parent', obj.gui.(parentStruct)(panelIndex).charUI.mainPanel, ...
    'Style', 'text', ...
    'HorizontalAlignment','left', ...
    'BackgroundColor', [0.9, 0.9, 0.9], ...
    'Units', 'normalized', ...
    'String', 'Test File:', ...
    'FontSize', 9, ...
    'Position', [0.01, 0.951, stringBoxSize]);

% filename display box
obj.gui.(parentStruct)(panelIndex).charUI.fileNameEdit = uicontrol(...
    'Parent', obj.gui.(parentStruct)(panelIndex).charUI.mainPanel, ...
    'Style', 'edit', ...
    'BackGroundColor', [0.8, 0.8, 0.8], ...
    'Enable', 'on', ...
    'HorizontalAlignment','left', ...
    'Units', 'normalized', ...
    'FontSize', 9, ...
    'String', [charTest, '.m'],...
    'Position', [0.25, 0.952, stringBoxSize]);

obj.gui.(parentStruct)(panelIndex).charUI.loadTestFile = uicontrol(...
    'Parent', obj.gui.(parentStruct)(panelIndex).charUI.mainPanel, ...
    'Style', 'pushbutton', ...
    'CData',  iconRead(fullfile('icons', 'file_open.png')),...
    'FontSize', 10, ...
    'Units', 'normalized', ...
    'Position', [.70, .951, .066, .035], ...
    'Callback', {@load_testScript_cb, obj, parentStruct, panelIndex});

end

function load_testScript_cb(~, ~, obj, parentStruct, panelIndex)
[characterizationTest, path] = uigetfile('*.m', 'Select the test file.', '.\testSetupCharacterizationScripts\');
if ~isequal(characterizationTest, 0) && ~isequal(path, 0)
    [~, characterizationTest, ~] = fileparts(characterizationTest);
end
obj.AppSettings.infoParams.CharacterizationTest = characterizationTest;
set(obj.gui.(parentStruct)(panelIndex).charUI.fileNameEdit, [characterizationTest, '.m']);
end