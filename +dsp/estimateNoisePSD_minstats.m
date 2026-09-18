function noisePSD = estimateNoisePSD_minstats(magSq, fs, hopLen, opts)
%ESTIMATENOISEPSD_MINSTATS  Bootstrap + minimum-statistics noise-power estimation.
%   Legacy estimator kept for A/B comparison in demo_compare.m.
%   The main pipeline now uses the SPP-based estimateNoisePSD.m.
%   noisePSD = estimateNoisePSD(magSq, fs, hopLen, opts) tracks the noise
%   PSD per frequency bin using the two-stage method described in the
%   report: (1) bootstrap from the first bootstrapSec of the signal
%   (assumed noise-only while the speaker is silent), (2) continuous
%   minimum-statistics update over a windowSec window with recursive
%   smoothing (Martin 1994, simplified). A fixed bias factor compensates
%   for the downward bias of the minimum operator.
%
%   opts fields:
%       bootstrapSec (default 0.5)
%       windowSec    (default 1.0)
%       alpha        (default 0.8)  smoothing of per-bin power
%       bias         (default 1.5)  min-tracker bias correction

    if nargin < 4, opts = struct(); end
    opts = setDefault(opts, 'bootstrapSec', 0.5);
    opts = setDefault(opts, 'windowSec',    1.0);
    opts = setDefault(opts, 'alpha',        0.8);
    opts = setDefault(opts, 'bias',         1.5);

    [numBin, numFrames] = size(magSq);
    framesPerSec = fs / hopLen;
    bootN = max(1, round(opts.bootstrapSec * framesPerSec));
    winN  = max(1, round(opts.windowSec    * framesPerSec));
    bootN = min(bootN, numFrames);

    initPSD = mean(magSq(:, 1:bootN), 2);
    if all(initPSD < 1e-12)
        initPSD = initPSD + 1e-10;
    end

    noisePSD = zeros(numBin, numFrames);
    smoothed = initPSD;
    buffer   = repmat(initPSD, 1, winN);
    bufIdx   = 1;

    for n = 1:numFrames
        smoothed = opts.alpha * smoothed + (1 - opts.alpha) * magSq(:, n);
        buffer(:, bufIdx) = smoothed;
        bufIdx = mod(bufIdx, winN) + 1;
        minP = min(buffer, [], 2);
        noisePSD(:, n) = opts.bias * minP;
    end
end

function s = setDefault(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
