function [noisePSD, sppOut] = estimateNoisePSD(magSq, fs, hopLen, opts)
%ESTIMATENOISEPSD  Speech-presence-aware noise PSD tracker.
%   [noisePSD, sppOut] = estimateNoisePSD(magSq, fs, hopLen, opts)
%
%   Implements the MMSE speech-presence-probability estimator of
%   Gerkmann & Hendriks, "Unbiased MMSE-Based Noise Power Estimation With
%   Low Complexity and Low Tracking Delay", IEEE T-ASLP 2011.
%
%   Per bin, per frame:
%     gamma       = |X|^2 / N_prev                       (a-posteriori SNR)
%     logZ        = log(qRatio) - log(1+xiH1) + gamma*xiH1/(1+xiH1)
%     sppInst     = 1 / (1 + exp(-logZ))                 (SPP under fixed xiH1)
%     spp         = sppSmooth * spp_prev + (1-sppSmooth)*sppInst
%     spp         = min(spp, sppMax)                     (safety cap)
%     alphaEff    = alphaN + (1 - alphaN) * spp          (freeze during speech)
%     N_next      = alphaEff * N_prev + (1-alphaEff) * |X|^2
%
%   The safety cap keeps alphaEff < 1 so the noise floor can still creep
%   up during long voiced passages if the noise itself drifts.
%
%   Bootstrap uses a per-bin low-quantile of |X|^2 over the first
%   bootstrapSec seconds. This does NOT assume the region is silent -
%   it only assumes each bin has *some* low-energy frames within it,
%   which is true even when the whole window contains speech (each bin
%   is quiet at different moments).
%
%   opts (all optional):
%       bootstrapSec       default 1.5    window for percentile bootstrap
%       bootstrapQuantile  default 0.15   per-bin quantile used
%       xiH1_dB            default 15     fixed a-priori SNR under H1
%       priorAbsence       default 0.5    a-priori P(H0)
%       sppSmooth          default 0.9    temporal SPP smoothing
%       sppMax             default 0.99   cap on smoothed SPP
%       alphaN             default 0.80   noise update speed when speech absent

    if nargin < 4, opts = struct(); end
    opts = setDefault(opts, 'bootstrapSec',      1.5);
    opts = setDefault(opts, 'bootstrapQuantile', 0.15);
    opts = setDefault(opts, 'xiH1_dB',           15);
    opts = setDefault(opts, 'priorAbsence',      0.5);
    opts = setDefault(opts, 'sppSmooth',         0.9);
    opts = setDefault(opts, 'sppMax',            0.99);
    opts = setDefault(opts, 'alphaN',            0.80);

    [numBin, numFrames] = size(magSq);
    framesPerSec = fs / hopLen;

    % ---- Robust per-bin bootstrap -----------------------------------------
    bootWin = max(3, min(numFrames, round(opts.bootstrapSec * framesPerSec)));
    q       = min(max(opts.bootstrapQuantile, 0.05), 0.5);
    if bootWin >= 5
        initPSD = quantile(magSq(:, 1:bootWin), q, 2);
    else
        initPSD = mean(magSq(:, 1:bootWin), 2);
    end
    initPSD = max(initPSD, 1e-12);

    % ---- Precomputed scalars for the SPP recursion ------------------------
    xiH1       = 10^(opts.xiH1_dB / 10);
    qRatio     = (1 - opts.priorAbsence) / max(opts.priorAbsence, 1e-6);
    gainFactor = xiH1 / (1 + xiH1);
    logConst   = log(qRatio) - log(1 + xiH1);

    N        = initPSD;
    sppSm    = zeros(numBin, 1);
    noisePSD = zeros(numBin, numFrames);
    sppOut   = zeros(numBin, numFrames);

    for n = 1:numFrames
        gamma   = magSq(:, n) ./ max(N, 1e-12);
        logZ    = logConst + gamma * gainFactor;
        sppInst = 1 ./ (1 + exp(-logZ));
        sppSm   = opts.sppSmooth * sppSm + (1 - opts.sppSmooth) * sppInst;
        sppSm   = min(sppSm, opts.sppMax);

        alphaEff = opts.alphaN + (1 - opts.alphaN) * sppSm;
        N = alphaEff .* N + (1 - alphaEff) .* magSq(:, n);

        noisePSD(:, n) = N;
        sppOut(:, n)   = sppSm;
    end
end

function s = setDefault(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
