function x = istftSynthesize(S, params)
%ISTFTSYNTHESIZE  Weighted overlap-add reconstruction from one-sided STFT.
%   x = istftSynthesize(S, params) inverts stftAnalyze. Uses square-window
%   weighted OLA: the analysis window is re-applied in synthesis and the
%   output is normalised by the summed squared window, giving perfect
%   reconstruction when no spectral modification is applied (Hann + 50%
%   overlap satisfies COLA of w^2).

    frameLen  = params.frameLen;
    hopLen    = params.hopLen;
    win       = params.win(:);
    nfft      = params.nfft;
    numFrames = size(S, 2);

    outLen = (numFrames - 1) * hopLen + frameLen;
    x      = zeros(outLen, 1);
    winSum = zeros(outLen, 1);
    w2     = win .^ 2;

    for k = 1:numFrames
        Sk = S(:, k);
        % Reconstruct conjugate-symmetric full spectrum for real ifft
        Ffull = [Sk; conj(Sk(end-1:-1:2))];
        frame = real(ifft(Ffull, nfft));
        idx   = (k-1)*hopLen + (1:frameLen);
        x(idx)      = x(idx)      + frame .* win;
        winSum(idx) = winSum(idx) + w2;
    end

    nz = winSum > 1e-8;
    x(nz) = x(nz) ./ winSum(nz);

    if isfield(params, 'origLen') && params.origLen > 0
        x = x(1:min(numel(x), params.origLen));
    end
end
