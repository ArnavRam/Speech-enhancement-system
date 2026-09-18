function [y, info] = enhanceSpeech(x, fs, opts)
%ENHANCESPEECH  Top-level single-channel speech enhancement pipeline.
%   [y, info] = enhanceSpeech(x, fs, opts) resamples to 16 kHz mono,
%   applies pre-emphasis, computes an STFT with 32 ms Hann frames at 50%
%   overlap, estimates noise PSD (bootstrap + minimum statistics), applies
%   the selected magnitude gain (Wiener or spectral subtraction) while
%   preserving noisy phase, reconstructs by weighted overlap-add, and
%   undoes the pre-emphasis. info contains intermediate quantities for
%   plotting and reporting.
%
%   opts fields (all optional):
%       algorithm    'wiener' (default) | 'specsub'
%       targetFs     default 16000
%       frameMs      default 32
%       overlap      default 0.5   (0 < overlap < 1)
%       preemph      default true
%       normalize    default true
%       noise        struct passed to estimateNoisePSD
%       wiener       struct passed to wienerGain
%       specsub      struct passed to spectralSubtract

    if nargin < 3, opts = struct(); end
    opts = setDefault(opts, 'algorithm', 'wiener');
    opts = setDefault(opts, 'targetFs',  16000);
    opts = setDefault(opts, 'frameMs',   32);
    opts = setDefault(opts, 'overlap',   0.5);
    opts = setDefault(opts, 'preemph',   true);
    opts = setDefault(opts, 'normalize', true);
    opts = setDefault(opts, 'noise',     struct());
    opts = setDefault(opts, 'wiener',    struct());
    opts = setDefault(opts, 'specsub',   struct());

    x = x(:, :);
    if size(x, 2) > 1
        x = mean(x, 2);
    end
    x = x(:);

    if fs ~= opts.targetFs
        x  = resample(x, opts.targetFs, fs);
        fs = opts.targetFs;
    end

    if opts.preemph
        x = filter([1 -0.97], 1, x);
    end

    frameLen = 2 * round(opts.frameMs * 1e-3 * fs / 2);   % force even
    hopLen   = max(1, round(frameLen * (1 - opts.overlap)));
    win      = hann(frameLen, 'periodic');

    [S, prm] = dsp.stftAnalyze(x, frameLen, hopLen, win);
    magSq    = abs(S).^2;

    noisePSD = dsp.estimateNoisePSD(magSq, fs, hopLen, opts.noise);

    switch lower(opts.algorithm)
        case 'wiener'
            [G, snrPrio] = dsp.wienerGain(magSq, noisePSD, opts.wiener);
        case 'specsub'
            G = dsp.spectralSubtract(magSq, noisePSD, opts.specsub);
            snrPrio = [];
        otherwise
            error('enhanceSpeech:algo', 'Unknown algorithm: %s', opts.algorithm);
    end

    Y = G .* S;
    y = dsp.istftSynthesize(Y, prm);

    if opts.preemph
        y = filter(1, [1 -0.97], y);
    end

    if opts.normalize
        peak = max(abs(y));
        if peak > 0
            y = 0.98 * y / peak;
        end
    end

    info = struct( ...
        'fs',        fs, ...
        'S',         S, ...
        'Y',         Y, ...
        'G',         G, ...
        'noisePSD',  noisePSD, ...
        'snrPrio',   snrPrio, ...
        'frameLen',  frameLen, ...
        'hopLen',    hopLen, ...
        'win',       win, ...
        'algorithm', opts.algorithm);
end

function s = setDefault(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
