function FV = Import_Barrels(FV)
% Import barrel masks from intrinsic imaging session
%
% Requisites:
% 1) Prior to running this script, the barrel map needs to be constructed
%    using in Map_Barrels plugin in ISI_analysisGUI.
% 2) The path of the vessel image taken with GalvoScanner.
% 3) The path to the MapBarrelsResult.mat file is requested. This file is
%    generated by IOS_analysisGUI (using the Map_Barrels plugin).
%
% It is recommended that the 2 images and 1 .mat file are copied to the
% same directory as the electrophysiology data.
%
% The IOS image and all barrels masks are mapped onto the coordinates of
% the GalvoScanner image using either an affine or polynomial approach.
%

debug = 0;

% Load MapBarrelsResult.mat file and IOS vessel image
if ~exist(FV.sDirectory, 'dir')
    errordlg(sprintf('The directory %s no longer exists. Drive disconnected?', FV.sDirectory));
    return
end
cd(FV.sDirectory)
persistent p_sMapBarrelsResultPath
sPwd = pwd;
if ~isempty(p_sMapBarrelsResultPath)
    cd(p_sMapBarrelsResultPath)
end
[sFile, sPath] = uigetfile( {'*.mat'}, 'Pick a MapBarrelsResult.mat file');
p_sMapBarrelsResultPath = sPath;
cd(sPwd)

if ~sFile, return, end
load(fullfile(sPath, sFile))
unregistered = tResults.VesselImage(:,:,1); % IOS vessel (blue) image
cd(sPath)

% Load the GalvoScanner blue/vessel image WITHOUT stereotactic coordinates
persistent p_sRefImgPath
sPwd = pwd;
if ~isempty(p_sRefImgPath)
    cd(p_sRefImgPath)
end
[sFile, sPath] = uigetfile('*.png', 'Select GalvoScanner vessel image wo/coordinates');
p_sRefImgPath = sPath;
cd(sPwd)
if ~sFile, return, end
reference = imread(fullfile(sPath, sFile));
reference = reference(:,:,1);
reference = imresize(reference, [480 640]);

% Barrel map
barrelmap = tResults.CombinedMap;

% Check if controlpoint data exists on disk
sCtrlPntsPath = fullfile(sPath, 'ImageReControlPoints.mat');
if exist(sCtrlPntsPath, 'file')
    sAns = questdlg('Do you want to load existing controlpoint data from disk?', ...
        'Load controlpoints', 'Yes', 'No', 'Cancel', 'Yes');
    switch sAns
        case 'Yes', load(sCtrlPntsPath, '-MAT');
        case 'Cancel', return;
    end
end

% Get control points interactively
if exist('input_points', 'var')
    % Use existing control points
    [input_points, base_points] = cpselect(unregistered, reference, ...
        input_points, base_points, 'Wait', true);
else
    [input_points, base_points] = cpselect(unregistered, reference, 'Wait', true);
end

% Find transform
if size(input_points, 1) > 10
    sTransMethod = 'polynomial';
elseif size(input_points, 1) > 4
    sTransMethod = 'projective';
elseif size(input_points, 1) > 3
    sTransMethod = 'affine';
else
    warndlg('Too few control points. Aborting.', 'modal')
    return
end
TFORM = cp2tform(input_points, base_points, sTransMethod);

% Save controlpoints and transform
save(sCtrlPntsPath, 'input_points', 'base_points', 'TFORM', 'sTransMethod')

% Perform affine transformation of unregistered image (IOS blue/vessel image)
[nrows ncols] = size(reference);
registered = imtransform(unregistered, TFORM, 'XData',[1 ncols], 'YData',[1 nrows]);
registered = imresize(registered, [nrows ncols]);

% Transform barrel map
barrelmap_reg = imtransform(barrelmap, TFORM, 'XData',[1 ncols], 'YData',[1 nrows], 'FillValues', -.5);
barrelmap_reg = barrelmap_reg(1:size(reference,1),1:size(reference,2));
barrelmap_reg(barrelmap_reg == -.5) = NaN;

% Crop registered IOS image to same size as reference (GalvoScanner) vessel image
registered = registered(1:size(reference,1),1:size(reference,2));


%% Show all images
tBarrelOutlines = struct([]);
hFig = figure;
colormap gray

% IOS - unregistered w/barrel outlines
hAx = subplot(2,3,1);
imshow(unregistered); hold on
mIdentityMap = tResults.IdentityMap;
hContFig = figure;
set(hContFig, 'visible', 'off');
for i = unique(mIdentityMap(:))'
    if i == 0, continue; end
    mIMap = mIdentityMap == i;
    % Get new outline
    figure(hContFig); set(hContFig, 'visible', 'off')
    [mC, vH] = contour(mIMap, 1);

    % remove [0 0] from mC
    vZeroInd = find(all(mC' == zeros(size(mC, 2), size(mC, 1))));
    mC(:, all( mC < 10 )) = [];

    % Remove large jumps in mC
    mC = mC(:,2:end);
    vDiff = prod(abs(diff(mC')),2);
    vCIndx = find(vDiff > 5*mean(vDiff(vDiff>0)));
    mC(:, vCIndx:end) = [];
    
    % Smooth mC
    mC(1,:) = smooth(mC(1,:), 20);
    mC(2,:) = smooth(mC(2,:), 20);
    plot(hAx, mC(1,:), mC(2,:), 'w:') 
end
delete(hContFig)
axis image
title('IOS - Unregistered w/outlines')

% IOS - registered
subplot(2,3,2)
imshow(registered)
axis image
title('IOS - Registered')

% IOS - unregistered w/barrels
subplot(2,3,3)
h1 = imshow(unregistered); hold on % uint8 [H W 3]    0 - 255
mNorm = barrelmap;
mNorm = mNorm - min(mNorm(:));
mNorm = uint32( (mNorm ./ max(mNorm(:))) .* (2^16) );
h2 = subimage(mNorm, jet(2^16));
alphamap = ones(size(mNorm)) .* .5;
alphamap( mNorm < ((2^16)*.6) ) = 0;
set(h2, 'alphadata', alphamap, 'alphaDataMapping', 'none');
axis image
title('IOS - Unregistered w/barrels')

% GalvoScanner w/barrels outlines
hAx = subplot(2,3,4);
h1 = imshow(reference); hold on
mIdentityMap = tResults.IdentityMap;
mDistanceMap = tResults.DistanceMap;
cBarrelIdentities = tResults.BarrelIdentities;
hContFig = figure;
set(hContFig, 'visible', 'off');
for i = unique(mIdentityMap(:))'
    if i == 0, continue; end
    mIMap = mIdentityMap == i;
    % Transform barrel
    mIMap_reg = imtransform(mIMap, TFORM, 'XData',[1 ncols], 'YData',[1 nrows], 'FillValues', -.5);
    mIMap_reg = mIMap_reg(1:size(reference,1),1:size(reference,2));

    % Transform distance (from boundary) matrix
    mDMap = mDistanceMap;
    mDMap(~mIMap) = 0;
    mDMap_reg = imtransform(mDMap, TFORM, 'XData',[1 ncols], 'YData',[1 nrows], 'FillValues', 0);
    mDMap_reg = mDMap_reg(1:size(reference,1),1:size(reference,2));
    
    % Get new outline
    figure(hContFig); set(hContFig, 'visible', 'off')
    [mC, vH] = contour(mIMap_reg, 1);

    % remove [0 0] from mC
    vZeroInd = find(all(mC' == zeros(size(mC, 2), size(mC, 1))));
    mC(:, all( mC < 10 )) = [];

    % Remove large jumps in mC
    mC = mC(:,2:end);
    vDiff = prod(abs(diff(mC')),2);
    vCIndx = find(vDiff > 5*mean(vDiff(vDiff>0)));
    mC(:, vCIndx:end) = [];
    
    % Smooth mC
    mC(1,:) = smooth(mC(1,:), 20);
    mC(2,:) = smooth(mC(2,:), 20);
    plot(hAx, mC(1,:), mC(2,:), 'w:')
    
    % Compute centroid and display barrel identity
    vCentroidXY = geomean(mC, 2)';
    axes(hAx)
    plot(vCentroidXY(1), vCentroidXY(2), 'w.')
    sID = cBarrelIdentities{find(unique(mIdentityMap(:))' == i)-1};
    hTxt = text(vCentroidXY(1), vCentroidXY(2), sID);
    set(hTxt, 'horizontalalignment', 'center', 'color', 'k', 'fontsize', 7)
    
    % Keep copy of barrel outline
    tBarrelOutlines(end+1).vX = mC(1,:);
    tBarrelOutlines(end).vY = mC(2,:);
    tBarrelOutlines(end).sID = sID;
    tBarrelOutlines(end).nCentroidXY = vCentroidXY;
    tBarrelOutlines(end).mDistanceMap = mDMap_reg;
    
end
delete(hContFig)
title('Reference w/outlines')

% IOS - GalvoScanner
subplot(2,3,5)
imshow(reference)
axis image
title('Reference')

% GalvoScanner w/barrels
subplot(2,3,6)
h1 = imshow(reference); hold on
mNorm = barrelmap_reg;
mNorm = mNorm - min(mNorm(:));
mNorm = uint32( (mNorm ./ max(mNorm(:))) .* (2^16));
h2 = subimage(mNorm, jet(2^16));
alphamap = ones(size(mNorm)) .* .5;
alphamap( mNorm < ((2^16)*.6) ) = 0;
set(h2, 'alphadata', alphamap, 'alphaDataMapping', 'none');
title('Reference w/barrels')

header(sprintf('%s   (%s transform)', sPath, sTransMethod), 12)
%%

% Save barrel locations in reference image coordinates (in pixels)
FV.tData.BarrelOutlines = tBarrelOutlines;

return



function y = header(x, fontsize)
if nargin < 2; fontsize = 20; end;
t = findobj(gcf, 'Tag', 'header');
if isempty(t)
    ax = gca;
    axes('Position', [0 0 1 1], 'Visible', 'off');
    t = text(0.5, 0.98, x, ...
        'Units', 'normalized', ...
        'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'center', ...
        'Tag', 'header', ...
        'FontSize', fontsize);
    axes(ax);
else set(t, 'String', x, 'FontSize', fontsize); end
if nargout > 0; y = t; end;
return


function OldCrapBelow()

% Click and mark stereotactic coordinates (should be in square grid, so two
% points is enough).
hFig = figure;
imagesc(coordsimg)
% Click on [-1 -3]
title('Click on (-1,-3)')
[nX1, nY1] = ginput(1);
% Click on [-2 -3]
title('Click on (-2,-3)')
[nX2, nY2] = ginput(1);
close(hFig)

return


