%DEMO_OFFLINE  End-to-end test of the enhancement pipeline (no GUI, no mic).
%   Run this from the SpeechEnhancer project root:
%       >> demo_offline
%   It uses a synthetic "speech-like" signal so the demo works out of the
%   box; if assets/sample_clean.wav exists that is loaded instead. Then it
%   adds noise at a known SNR, runs the Wiener enhancer, prints metrics
%   and plots waveforms + spectrograms + Wiener gain.

clear; clc; close all;
addpath(pwd);

targetFs = 16000;
snrIn    = 5;                  % dB
noiseKind = 'babble';          % 'white' | 'pink' | 'babble'

cleanPath = fullfile('assets', 'sample_clean.wav');
if isfile(cleanPath)
    [clean, fs] = audioread(cleanPath);
    if size(clean, 2) > 1, clean = mean(clean, 2); end
    if fs ~= targetFs
        clean = resample(clean, targetFs, fs);
        fs = targetFs;
    end
else
    fprintf('assets/sample_clean.wav not found - using synthetic speech-like signal.\n');
    fs = targetFs;
    clean = syntheticSpeech(fs, 4.0);
end
clean = clean / (max(abs(clean)) + 1e-9) * 0.8;

% Insert 0.6 s of silence at the very start so the noise bootstrap works
silencePad = zeros(round(0.6 * fs), 1);
clean = [silencePad; clean];

rng(7);
[noisy, ~, actualSNR] = senh.addSyntheticNoise(clean, fs, snrIn, noiseKind);
fprintf('Injected noise (%s) at %.2f dB SNR.\n', noiseKind, actualSNR);

opts = struct('algorithm', 'wiener');
[yWiener, infoW] = dsp.enhanceSpeech(noisy, fs, opts);

opts2 = struct('algorithm', 'specsub');
[ySS, infoS] = dsp.enhanceSpeech(noisy, fs, opts2);

mW = senh.computeMetrics(clean, noisy, yWiener, fs);
mS = senh.computeMetrics(clean, noisy, ySS,     fs);

fprintf('\n--- Wiener (DD + MinStats) ---\n');
printMetrics(mW);
fprintf('\n--- Spectral Subtraction (Berouti) ---\n');
printMetrics(mS);

% Save outputs so you can compare them by ear
outDir = fullfile('assets', 'out');
if ~isfolder(outDir), mkdir(outDir); end
audiowrite(fullfile(outDir, 'noisy.wav'),    normalizeAudio(noisy),   fs);
audiowrite(fullfile(outDir, 'wiener.wav'),   normalizeAudio(yWiener), fs);
audiowrite(fullfile(outDir, 'specsub.wav'),  normalizeAudio(ySS),     fs);
fprintf('\nWrote noisy.wav / wiener.wav / specsub.wav into %s\n', outDir);

% ---- Plots -----------------------------------------------------------------
t = (0:numel(noisy)-1)/fs;
figure('Name', 'Waveforms', 'Color', 'w');
tl = tiledlayout(3,1, 'TileSpacing', 'compact');
nexttile; plot(t, clean);          title('Clean');        ylabel('amp'); grid on;
nexttile; plot(t, noisy);          title('Noisy');        ylabel('amp'); grid on;
nexttile; plot(t(1:numel(yWiener)), yWiener); title('Enhanced (Wiener)'); xlabel('time (s)'); ylabel('amp'); grid on;
title(tl, sprintf('Input SNR %.1f dB  ->  Output SNR %.1f dB   (\\Delta = %+.1f dB)', ...
    mW.inputSNRdB, mW.outputSNRdB, mW.snrImprovementdB));

figure('Name', 'Spectrograms', 'Color', 'w');
tiledlayout(3,1, 'TileSpacing', 'compact');
nexttile; plotSpec(clean,   fs); title('Clean');
nexttile; plotSpec(noisy,   fs); title('Noisy');
nexttile; plotSpec(yWiener, fs); title('Enhanced (Wiener)');

figure('Name', 'Wiener gain', 'Color', 'w');
tiledlayout(2,1, 'TileSpacing', 'compact');
nexttile;
imagesc(20*log10(infoW.G + 1e-6));
axis xy; colormap(parula); cb = colorbar; cb.Label.String = 'dB';
title('Wiener gain G(k,n) [dB]'); xlabel('frame'); ylabel('freq bin');

nexttile;
fVec = (0:size(infoW.G,1)-1) * fs / infoW.frameLen;
plot(fVec, mean(20*log10(infoW.G + 1e-6), 2), 'LineWidth', 1.5);
grid on; xlim([0 fs/2]); xlabel('frequency (Hz)'); ylabel('mean gain (dB)');
title('Mean Wiener gain vs frequency');

fprintf('\nDone. Play out\\noisy.wav then out\\wiener.wav to compare.\n');

% ============================== helpers ====================================
function printMetrics(m)
    fprintf('  input SNR       : %6.2f dB\n', m.inputSNRdB);
    fprintf('  output SNR      : %6.2f dB\n', m.outputSNRdB);
    fprintf('  SNR improvement : %+6.2f dB\n', m.snrImprovementdB);
    fprintf('  seg SNR in / out: %6.2f / %6.2f dB\n', m.segSNRinDB, m.segSNRoutDB);
    fprintf('  noise-floor drop: %+6.2f dB   (silent segment %.2fs)\n', ...
            m.noiseFloorDropDB, m.silentSec);
end

function y = normalizeAudio(x)
    p = max(abs(x));
    if p > 0, y = 0.98 * x / p; else, y = x; end
end

function plotSpec(x, fs)
    win = hann(round(0.032*fs), 'periodic');
    hop = numel(win)/2;
    [S, prm] = dsp.stftAnalyze(x(:), numel(win), hop, win);
    mag = 20*log10(abs(S) + 1e-6);
    f = (0:size(S,1)-1) * fs / prm.nfft;
    t = (0:size(S,2)-1) * hop / fs;
    imagesc(t, f, mag); axis xy;
    ylim([0 fs/2]); ylabel('Hz'); xlabel('time (s)');
    colormap(parula); cb = colorbar; cb.Label.String = 'dB';
    caxis([max(mag(:))-60, max(mag(:))]);
end

function x = syntheticSpeech(fs, durSec)
    % Formant-modulated synthetic vowel-like signal + short pauses so the
    % pipeline sees speech-shaped structure without needing an audio file.
    N = round(fs * durSec);
    t = (0:N-1)'/fs;
    % Pitch contour ~ 120 Hz with vibrato
    f0 = 120 + 8*sin(2*pi*4.5*t);
    phase = 2*pi*cumsum(f0)/fs;
    % Glottal-ish source: sum of harmonics with 1/k decay
    x = zeros(N,1);
    for k = 1:20
        x = x + (1/k) * sin(k*phase);
    end
    % Time-varying formants via cascaded biquads
    F1 = 500 + 200*sin(2*pi*0.7*t);
    F2 = 1500 + 400*sin(2*pi*0.5*t + 1);
    F3 = 2500 + 300*sin(2*pi*0.3*t + 2);
    x = applyFormant(x, F1, 80, fs);
    x = applyFormant(x, F2, 100, fs);
    x = applyFormant(x, F3, 120, fs);
    % Insert two short pauses
    x(round(0.25*N):round(0.30*N)) = 0;
    x(round(0.62*N):round(0.68*N)) = 0;
    x = x / (max(abs(x)) + 1e-9);
end

function y = applyFormant(x, Ft, BW, fs)
    y = zeros(size(x));
    zi = [0;0];
    for n = 1:numel(x)
        r = exp(-pi*BW/fs);
        theta = 2*pi*Ft(n)/fs;
        a1 = -2*r*cos(theta);
        a2 = r*r;
        y(n) = x(n) - a1*zi(1) - a2*zi(2);
        zi = [y(n); zi(1)];
    end
end
