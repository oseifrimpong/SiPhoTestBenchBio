% Function to update assay and device table during experiment
function assayUpdateTable(obj, recipeIndex, deviceIndex, remaining)
%% Recipe Summary Table
testPanel = panel_index('test');

recipeTable = obj.gui.panel(testPanel).assayUI.recipeTable;
recipeTable{recipeIndex, 1} = remaining;
recipeTable(recipeIndex, 2) = strcat(...
    '<html><span style="color: #FF9900; font-weight: bold;">', ...
    obj.recipe.reagent(recipeIndex), ...
    '</span></html>');

%% Device Table
deviceTable = obj.gui.panel(testPanel).assayUI.deviceTable;
deviceTable(deviceIndex, 1) = strcat(...
    '<html><span style="color: #FF9900; font-weight: bold;">', ...
    obj.gui.panel(testPanel).assayUI.deviceTable(deviceIndex, 1), ...
    '</span></html>');

%% Set Data
set(obj.gui.panel(testPanel).assayUI.recipeSummaryTable, ...
    'Data', ...
    recipeTable);

set(obj.gui.panel(testPanel).assayUI.resultTable, ...
    'Data', ...
    deviceTable);
end