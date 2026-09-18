%DEMO_COMPARE  A/B/C evaluation: noisy vs OLD pipeline vs REVISED pipeline.
%   Runs both estimators on synthetic clean speech contaminated with three
%   noise types (white, pink, babble) at 5 dB SNR. Deliberately does NOT
%   pad silence at the start, so the robust bootstrap is exercised.
%
%   Writes assets/out/compare/*.wav and opens 3 comparison figures.
%   Prints a metrics table:
%       inSNR / outSNR-OLD / outSNR-NEW / delta-OLD / delta-NEW / segSNR
%       + reference-free noise-floor drop on both.
%
%   From project root:
%       >> demo_compare

clear; clc; close all;
addpath(pwd);

fs         = 16000;
snrIn      = 5;                       % dB
noiseTypes = {'white', 'pink', 'babble'};

% Build clean signal that starts with speech (no silence pad).
clean = syntheticSpeech(fs, 4.0);
clean = clean / (max(abs(clean)) + 1e-9) * 0.8;

outDir = fullfile('assets', 'out', 'compare');
if ~isfolder(outDir), mkdir(outDir); end

rows = {};
for k = 1:numel(noiseTypes)
    ntype = noiseTypes{k};
    rng(100 + k);
    [noisy, ~, ~] = senh.addSyntheticNoise(clean, fs, snrIn, ntype);

    yOld = enhanceWithMinStats(noisy, fs);            % legacy
    yNew = dsp.enhanceSpeech(noisy, fs);              % current default (SPP)

    mOld = senh.computeMetrics(clean, noisy, yOld, fs);
    mNew = senh.computeMetrics(clean, noisy, yNew, fs);

    audiowrite(fullfile(outDir, sprintf('%s_noisy.wav',    ntype)), normAudio(noisy), fs);
    audiowrite(fullfile(outDir, sprintf('%s_old.wav',      ntype)), normAudio(yOld),  fs);
    audiowrite(fullfile(outDir, sprintf('%s_new.wav',      ntype)), normAudio(yNew),  fs);

    rows(end+1, :) = { upper(ntype), ...
        sprintf('%+5.2f', mOld.inputSNRdB), ...
        sprintf('%+5.2f', mOld.outputSNRdB), sprintf('%+5.2f', mNew.outputSNRdB), ...
        sprintf('%+5.2f', mOld.snrImprovementdB), sprintf('%+5.2f', mNew.snrImprovementdB), ...
        sprintf('%+5.2f / %+5.2f', mOld.segSNRoutDB, mNew.segSNRoutDB), ...
        sprintf('%+5.2f / %+5.2f', mOld.noiseFloorDropDB, mNew.noiseFloorDropDB) }; %#ok<AGROW>

    plotComparison(clean, noisy, yOld, yNew, fs, ntype);
end

fprintf('\n');
fprintf('%-8s | %-7s | %-7s | %-7s | %-7s | %-7s | %-15s | %-15s\n', ...
    'noise', 'inSNR', 'outOLD', 'outNEW', 'dOLD', 'dNEW', 'segOLD/NEW', 'floor OLD/NEW');
fprintf('%s\n', repmat('-', 1, 110));
for i = 1:size(rows, 1)
    fprintf('%-8s | %-7s | %-7s | %-7s | %-7s | %-7s | %-15s | %-15s\n', rows{i, :});
end
fprintf('\nAll numbers in dB. Higher outSNR / dNEW / segNEW / floor is better.\n');
fprintf('Audio written to %s\n', outDir);

% =========================================================================
%  Helpers
% =========================================================================
function y = enhanceWithMinStats(x, fs)
    % Reproduce the OLD pipeline: minimum-statistics + Wiener.
    x = x(:); if size(x,2) > 1, x = mean(x, 2); end
    x = filter([1 -0.97], 1, x);

    frameLen = 2 * round(0.032 * fs / 2);
    hopLen   = frameLen / 2;
    win      = hann(frameLen, 'periodic');

    [S, prm] = dsp.stftAnalyze(x, frameLen, hopLen, win);
    magSq    = abs(S).^2;
    noisePSD = dsp.estimateNoisePSD_minstats(magSq, fs, hopLen, ...
        struct('bootstrapSec', 0.5, 'windowSec', 1.0, 'bias', 1.5));
    G = dsp.wienerGain(magSq, noisePSD, ...
        struct('alphaDD', 0.98, 'Gmin', 10^(-18/20)));
    Y = G .* S;
    y = dsp.istftSynthesize(Y, prm);
    y = filter(1, [1 -0.97], y);
    p = max(abs(y)); if p > 0, y = 0.98 * y / p; end
end

function y = normAudio(x)
    p = max(abs(x));
    if p > 0, y = 0.98 * x / p; else, y = x; end
end

function plotComparison(clean, noisy, yOld, yNew, fs, ntype)
    figure('Name', sprintf('Comparison - %s', ntype), 'Color', 'w', ...
        'Position', [80 80 1180 720]);
    tiledlayout(4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % Waveforms
    lim = [0, max(numel(noisy), max(numel(yOld), numel(yNew)))/fs];
    nexttile; plotWave(clean, fs, 'Clean', lim);
    nexttile; plotWave(noisy, fs, 'Noisy', lim);
    nexttile; plotWave(yOld,  fs, 'OLD  (MinStats + Wiener)', lim);
    nexttile; plotWave(yNew,  fs, 'NEW  (SPP + Wiener)',      lim);

    % Spectrograms
    nexttile; plotSpec(clean, fs, 'Clean');
    nexttile; plotSpec(noisy, fs, 'Noisy');
    nexttile; plotSpec(yOld,  fs, 'OLD');
    nexttile; plotSpec(yNew,  fs, 'NEW');
    sgtitle(sprintf('Noise = %s (5 dB SNR, no silence pad)', ntype), ...
        'FontWeight', 'bold');
end

function plotWave(x, fs, ttl, xl)
    t = (0:numel(x)-1)/fs;
    plot(t, x, 'LineWidth', 0.6); grid on;
    ylim([-1 1]); xlim(xl);
    title(ttl); xlabel('t (s)'); ylabel('amp');
end

function plotSpec(x, fs, ttl)
    frameLen = 2 * round(0.032 * fs / 2);
    hop      = frameLen / 2;
    win      = hann(frameLen, 'periodic');
    [S, prm] = dsp.stftAnalyze(x(:), frameLen, hop, win);
    mag = 20*log10(abs(S) + 1e-6);
    f = (0:size(S,1)-1) * fs / prm.nfft;
    t = (0:size(S,2)-1) * hop / fs;
    imagesc(t, f, mag); axis xy; ylim([0 fs/2]);
    colormap(parula); cb = colorbar; cb.Label.String = 'dB';
    top = max(mag(:));
    try, clim([top-60 top]); catch, caxis([top-60 top]); end
    title(ttl); xlabel('t (s)'); ylabel('Hz');
end

function x = syntheticSpeech(fs, durSec)
    N = round(fs*durSec); t = (0:N-1)'/fs;
    f0 = 120 + 8*sin(2*pi*4.5*t);
    phase = 2*pi*cumsum(f0)/fs;
    x = zeros(N,1);
    for k = 1:20, x = x + (1/k)*sin(k*phase); end
    F1 = 500  + 200*sin(2*pi*0.7*t);
    F2 = 1500 + 400*sin(2*pi*0.5*t + 1);
    F3 = 2500 + 300*sin(2*pi*0.3*t + 2);
    x = fmt(x, F1, 80, fs); x = fmt(x, F2, 100, fs); x = fmt(x, F3, 120, fs);
    x(round(0.25*N):round(0.30*N)) = 0;
    x(round(0.62*N):round(0.68*N)) = 0;
    x = x / (max(abs(x)) + 1e-9);
end
function y = fmt(x, Ft, BW, fs)
    y = zeros(size(x)); zi = [0;0];
    for n = 1:numel(x)
        r = exp(-pi*BW/fs); th = 2*pi*Ft(n)/fs;
        a1 = -2*r*cos(th); a2 = r*r;
        y(n) = x(n) - a1*zi(1) - a2*zi(2);
        zi = [y(n); zi(1)];
    end
end
