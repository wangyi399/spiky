function FV = export_mat(sFile, FV)
%Matlab file

% Export data to .mat file. Each trace is exported as a vector.
%
% This function exports:
%  Currently viewed continuous channels
%  Analog channels are renamed to their descriptive names
%
% Todo:
%  Export spike data
%

global Spiky

[FV, ~] = Spiky.main.GetStruct();

% Create vectors to export
csFields = FV.csDisplayChannels;
tSpikyExport = struct([]);

if isfield(FV.tData, 'FileStart')
    tSpikyExport(1).FileStart = FV.tData.FileStart;
end
if isfield(FV.tData, 'FileEnd')
    tSpikyExport(1).FileEnd = FV.tData.FileEnd;
end
if isfield(FV, 'sLoadedTrial')
    tSpikyExport(1).OriginFile = FV.sLoadedTrial;
end
if isfield(FV, 'sDirectory')
    tSpikyExport(1).OriginDir  = FV.sDirectory;
end

for c = 1:length(csFields)
    csName = Spiky.main.GetChannelDescription(csFields{c});
    if isempty(csName)
        csName = csFields{c};
    end
    if isfield(FV.tData, csFields{c})
        tSpikyExport.(csName) = FV.tData.(csFields{c});
    end
    if isfield(FV.tData, [csFields{c} '_KHz'])
        tSpikyExport.([csName 'KHz']) = FV.tData.([csFields{c} '_KHz']);
    end
    if isfield(FV.tData, [csFields{c} '_TimeBegin'])
        tSpikyExport.([csName '_TimeBegin']) = FV.tData.([csFields{c} '_TimeBegin']);
    end
end

save(sFile, 'tSpikyExport')

return
