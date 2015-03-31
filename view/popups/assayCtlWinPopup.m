function assayCtlWinPopup(obj, ctlWinButtonList)
% Shon Schmidt, 2014
% Added to provide more real-time control of assay

obj.gui.assayCtlWinPopup.mainWindow = dialog(...
    'WindowStyle', 'modal', ...
    'Units', 'normalized', ...
    'Position', [0 0 .5 .5], ...
    'Name', 'Assay Control Window');

movegui(obj.gui.assayCtlWinPopup.mainWindow, 'center')

numOfButtons = length(ctlWinButtonList);
numX = ceil(sqrt(numOfButtons));
numY = floor(sqrt(numOfButtons));
if numX*numY < numOfButtons
    numY = numX;
end

btnX = 0.9/(numX*1.5);
btnY = 0.9/(numY*1.5);

xInit = 0.05;
yInit = 0.95 - btnY;

xOffset = 1.25*btnX;
yOffset = 1.25*btnY;

btnFontSize = 10;

x = xInit;
y = yInit;
% button list defined in assayCtl class
for ii = 1:length(ctlWinButtonList)
    
    obj.gui.assayCtlWinPopup.button(ii) = uicontrol(...
        'Parent', obj.gui.assayCtlWinPopup.mainWindow, ...
        'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [x y btnX btnY], ...
        'String', ctlWinButtonList{ii}, ...
        'FontSize', btnFontSize, ...
        'Enable', 'on', ...
        'Callback', {@callbackFunction, obj});
    
    % start a new row every 3rd column
    if mod(ii,numX) > 0 % increment x
        x = x + xOffset;
    else % reset x and increment y
        x = xInit;
        y = y - yOffset;
    end
    
end

    % stop execution until the user closes the window
    % not sure this works as needed in this context
    uiwait;
   
end
% ------------------------- Callback Function ----------------------------

function callbackFunction(hObject, eventdata, obj)
if ~isempty(obj.assayCtl) && strcmpi(class(obj.assayCtl), 'AssayCtlClass')
    % get the button's 'userData' -- it has the return code
    button = get(hObject, 'String');
    
    % call method in the assayCtl class to handle the event
    obj.assayCtl.ctlWinPopupReply(button);
    
    % close window
    if strcmpi(button, 'Resume') || ...
            strcmpi(button, 'Stop')
        % close the window
        uiresume;
        % obj.assayCtl.assayEnable = true; % start assay again
        close(obj.gui.assayCtlWinPopup.mainWindow);
    end
end
end
