function Peristimulus_Time_Histograms(FV)
%
%
%
global Spiky

[sCh, ~] = Spiky.main.SelectChannelNumber(fieldnames(FV.tSpikes)');

if isempty(sCh), warndlg('No channels were found that contained spiking data.'); return; end

if isfield(FV.tSpikes.(sCh), 'hierarchy')
    % Analyze sorted units
    vUnits = unique(FV.tSpikes.(sCh).hierarchy.assigns); % unit names
else
    % Analyze un-sorted units
    vUnits = NaN;
end

% Find event indices
vEventIndx = [];
cFields = fieldnames(FV.tData);
% Ignore DAQ_Start, _Stop and _Trigger fields (default fields generated by DAQ Toolbox)
cIgnoreFields = {'DAQ_Start_Up', 'DAQ_Stop_Up', 'DAQ_Trigger_Up'};
for e = 1:length(cFields) % iterate over fieldnames
    if ~isempty(strfind(cFields{e}, '_Up')) && ~ismember(cFields{e}, cIgnoreFields)
        vEventIndx(end+1) = e;
    end
end
if isempty(vEventIndx)
    waitfor(warndlg('No events to trigger PSTHs on were detected.'));
    return
end

% Ask for PSTH parameters
persistent p_nStimDel p_nPreStimDur p_nPostStimDur p_nBinRes p_nSmoothWin
if isempty(p_nStimDel), p_nStimDel = 0; end
if isempty(p_nPreStimDur), p_nPreStimDur = 0.05; end
if isempty(p_nPostStimDur), p_nPostStimDur = 0.15; end
if isempty(p_nBinRes), p_nBinRes = 0.001; end
if isempty(p_nSmoothWin), p_nSmoothWin = 1; end
cAnswer = inputdlg({'Stimulus delay (ms)','Pre-stim period (s)','Post-stim period (s)','Bin resolution (ms)','Smooth window (ms)'},...
    'PSTH', 1, {num2str(p_nStimDel), num2str(p_nPreStimDur), num2str(p_nPostStimDur), num2str(p_nBinRes), num2str(p_nSmoothWin)});
if isempty(cAnswer), return, end
p_nStimDel = str2num(cAnswer{1});
p_nPreStimDur = str2num(cAnswer{2});
p_nPostStimDur = str2num(cAnswer{3});
p_nBinRes = str2num(cAnswer{4});
p_nSmoothWin = ceil(str2num(cAnswer{5}));
 
% Check that events have enough data
vRemIndx = [];
for e = 1:length(vEventIndx) % iterate over fieldnames
    if isempty(strfind(cFields{vEventIndx(e)}, '_Up'))
        vRemIndx(end+1) = e;
        continue
    end
    vUpTimes = FV.tData.(cFields{vEventIndx(e)}); % sec, abs time
    if (length(vUpTimes) < 2)
        vRemIndx(end+1) = e;
    end
end
vEventIndx(vRemIndx) = [];

% Create figure
hFig = figure();
Spiky.main.ThemeObject(hFig)
drawnow
set(hFig, 'name', 'Spiky Peristimulus Time Histograms (PSTH)', 'NumberTitle', 'off');
vXLim = [-.1 .1];
nTrialLen = 100;

% Iterate over units
nRow = 1;
for u = 1:length(vUnits)
    % Iterate over events
    nCol = 1;
    for e = 1:length(vEventIndx) % iterate over fieldnames
        % Get event up times
        nFs = FV.tSpikes.(sCh).Fs;
        vUpTimes = FV.tData.(cFields{vEventIndx(e)}); % sec, abs time
        
        % Skip channels that have more than 10,000 events
        if length(vUpTimes) > 10000
            uiwait(warndlg(sprintf('Channel %s has more than 10,000 events and will be skipped.', cFields{vEventIndx(e)}), 'Spiky'))
            continue
        end
        
        % Get spiketimes
        if isnan(vUnits(u))
            % Un-sorted unit
            vSpiketimes = FV.tSpikes.(sCh).spiketimes(:) ./ nFs; % sec
        else
            % Sorted unit
            vIndx = FV.tSpikes.(sCh).hierarchy.assigns == vUnits(u);
            vSpiketimes = FV.tSpikes.(sCh).spiketimes(vIndx) ./ nFs; % sec
        end

        % Subtract stimulus delay from spiketimes
        vSpiketimes = vSpiketimes - (p_nStimDel/1000); % sec
        
        % Iterate over event times
        vPSTH = [];
        for et = 1:length(vUpTimes)-1
            vIndx = vSpiketimes >= (vUpTimes(et)-p_nPreStimDur) & vSpiketimes < vUpTimes(et+1);
            vRelTimes = vSpiketimes(vIndx) - vUpTimes(et);
            vPSTH = [vPSTH vRelTimes'];
        end

        if ~ishandle(hFig) return; end
        
        % Plot PSTH
        nX = .08; nY = .1; nW = .88; nH = .80;
        nNN = length(vEventIndx); nNNY = length(vUnits);
        hAx = axes('position', [nX+(nCol-1)*(nW/nNN) (1-nY)-u*(nH/nNNY) nW/nNN nH/nNNY]);

        if vUnits(u) == 0, vCol = [.5 .5 .5]; % outliers
        else vCol = FV.mColors(u,:); end

        nYMax = median(diff(vUpTimes));

        vPSTH(vPSTH>nYMax) = [];
        [vC, vT] = hist(vPSTH, -p_nPreStimDur:p_nBinRes:nYMax);
        vC = (vC./et) * (1/p_nBinRes); % normalize to spikes/sec

        % Convolve with a right-angled triangular window
        if ~isempty(vC) && (p_nSmoothWin > 1)
            vWin = [linspace(1,0,p_nSmoothWin)];
            vWin = vWin/sum(vWin); % normalize so sum is 1
            vC = conv(vC, vWin);
        else p_nSmoothWin = 1; end

        % Plot as bars
        if ~isempty(vT)
            hBar = bar(vT, vC(1:end-(p_nSmoothWin-1)));
            set(hBar, 'facecolor', vCol, 'edgecolor', vCol)
        end
        
        if isnan(nYMax) || nYMax < 0, nYMax = 0.1; end
        Spiky.main.ThemeObject(hAx)
        set(hAx, 'fontsize', 7, 'xlim', [-p_nPreStimDur p_nPostStimDur])
        box on; grid on

        if nCol == 1
            ylabel('Spikes/s')
            if isnan(vUnits(u))
                % Un-sorted unit
                hTxt = text(0,0, ' Unit UN-SORTED');
            else
                % Sorted unit
                hTxt = text(0,0,sprintf(' Unit %d', vUnits(u)));
            end
            set(hTxt, 'color', FV.mColors(u,:), 'fontsize', 8, 'fontweight', 'bold', 'backgroundcolor', [.1 .1 .1], ...
                'interpreter', 'none', 'HorizontalAlignment', 'center', 'units', 'normalized', ...
                'backgroundcolor', [.1 .1 .1], 'position', [-.1 .5 0], 'Rotation', 90)
        end

        if nRow == 1
            sChName = cFields{vEventIndx(e)}(1:end-3);
            if isfield(FV, 'tChannelDescriptions')
                nIndx = find(strcmpi({FV.tChannelDescriptions.sChannel}, sChName));
            else nIndx = []; end
            if isempty(nIndx), hTit = title(sChName);
            else
                hTit = title(sprintf('%s (%s) n=%d', ...
                    FV.tChannelDescriptions(nIndx).sDescription, sChName, length(vUpTimes)));
            end
            Spiky.main.ThemeObject(hTit)
            set(hTit, 'FontSize', 8, 'FontWeight', 'bold', 'interpreter', 'none')
        elseif u == length(vUnits)
            xlabel('Time (s)');
        end
        
        nCol = nCol + 1; % increment column counter
        drawnow
    end
nRow = nRow + 1; % increment row counter
end

return
