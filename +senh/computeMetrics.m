function m = computeMetrics(clean, noisy, enhanced, fs, opts)
%COMPUTEMETRICS  SNR / segmental SNR / noise-floor drop.
%   m = computeMetrics(clean, noisy, enhanced, fs, opts) returns a struct
%   of quantitative metrics for reporting. If a clean reference is not
%   available pass [] for clean; reference-free metrics still populate.
%
%   Fields returned:
%       inputSNRdB       overall SNR of noisy vs clean         (needs clean)
%       outputSNRdB      overall SNR of enhanced vs clean      (needs clean)
%       snrImprovementdB outputSNRdB - inputSNRdB               (needs clean)
%       segSNRinDB       segmental SNR of noisy                 (needs clean)
%       segSNRoutDB      segmental SNR of enhanced              (needs clean)
%       noiseFloorDropDB reduction in silent-segment RMS (dB)
%       silentSec        length of silent segment used
%
%   opts.silentSec (default 0.5)   window at start assumed noise-only
%   opts.frameMs   (default 30)    frame length for segmental SNR

    if nargin < 5, opts = struct(); end
    if ~isfield(opts, 'silentSec'), opts.silentSec = 0.5; end
    if ~isfield(opts, 'frameMs'),   opts.frameMs   = 30;  end

    m = struct();
    m.inputSNRdB = NaN; m.outputSNRdB = NaN; m.snrImprovementdB = NaN;
    m.segSNRinDB = NaN; m.segSNRoutDB = NaN;

    L = min([numel(noisy), numel(enhanced), ...
             ternaryLen(clean, numel(noisy))]);

    noisy    = noisy(1:L);
    enhanced = enhanced(1:L);

    if ~isempty(clean)
        clean = clean(1:L);
        m.inputSNRdB      = snrDB(clean, noisy    - clean);
        m.outputSNRdB     = snrDB(clean, enhanced - clean);
        m.snrImprovementdB = m.outputSNRdB - m.inputSNRdB;
        m.segSNRinDB  = segmentalSNR(clean, noisy,    fs, opts.frameMs);
        m.segSNRoutDB = segmentalSNR(clean, enhanced, fs, opts.frameMs);
    end

    Nsil = min(L, max(1, round(opts.silentSec * fs)));
    rmsIn  = rms(noisy(1:Nsil));
    rmsOut = rms(enhanced(1:Nsil));
    m.noiseFloorDropDB = 20*log10((rmsIn + 1e-12) / (rmsOut + 1e-12));
    m.silentSec = Nsil / fs;
end

function v = snrDB(sig, noise)
    v = 10*log10( (sum(sig.^2) + 1e-12) / (sum(noise.^2) + 1e-12) );
end

function v = segmentalSNR(clean, test, fs, frameMs)
    L = min(numel(clean), numel(test));
    clean = clean(1:L); test = test(1:L);
    N = max(1, round(frameMs*1e-3*fs));
    numFr = floor(L / N);
    if numFr < 1, v = NaN; return; end
    snrs = zeros(numFr, 1);
    for k = 1:numFr
        idx = (k-1)*N + (1:N);
        s = clean(idx); e = test(idx) - s;
        sp = sum(s.^2); ep = sum(e.^2);
        if sp < 1e-8, snrs(k) = NaN; continue; end
        val = 10*log10(sp / (ep + 1e-12));
        snrs(k) = min(max(val, -10), 35);   % clip per convention
    end
    v = mean(snrs, 'omitnan');
end

function r = rms(x)
    r = sqrt(mean(x.^2));
end

function L = ternaryLen(a, fallback)
    if isempty(a), L = fallback; else, L = numel(a); end
end
