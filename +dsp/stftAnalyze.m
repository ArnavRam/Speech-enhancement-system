function [S, params] = stftAnalyze(x, frameLen, hopLen, win)
%STFTANALYZE  One-sided STFT of a real signal.
%   [S, params] = stftAnalyze(x, frameLen, hopLen, win) frames x with the
%   given window (length frameLen) and hop, applies FFT, and returns the
%   one-sided spectrogram S of size [frameLen/2+1, numFrames] plus a params
%   struct used by istftSynthesize for perfect reconstruction bookkeeping.
%
%   Uses a Hann-type window at 50% overlap to satisfy the COLA condition.

    x = x(:);
    N = numel(x);
    win = win(:);
    if numel(win) ~= frameLen
        error('stftAnalyze:winLen', 'Window length must equal frameLen.');
    end

    % Pad so we get an integer number of frames covering the whole signal
    numFrames = max(1, ceil((N - frameLen) / hopLen) + 1);
    padLen = (numFrames - 1) * hopLen + frameLen;
    if padLen > N
        x(end+1:padLen) = 0;
    end

    nfft   = frameLen;
    numBin = nfft/2 + 1;
    S      = complex(zeros(numBin, numFrames));

    for k = 1:numFrames
        idx = (k-1)*hopLen + (1:frameLen);
        frame = x(idx) .* win;
        F = fft(frame, nfft);
        S(:, k) = F(1:numBin);
    end

    params = struct( ...
        'frameLen', frameLen, ...
        'hopLen',   hopLen, ...
        'win',      win, ...
        'nfft',     nfft, ...
        'numFrames', numFrames, ...
        'origLen',  N);
end
