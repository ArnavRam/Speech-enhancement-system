function [G, snrPrio] = wienerGain(magSq, noisePSD, opts)
%WIENERGAIN  Decision-directed Wiener suppression gain.
%   [G, snrPrio] = wienerGain(magSq, noisePSD, opts) computes the per-bin
%   Wiener gain G = xi / (1 + xi), where xi is the a priori SNR estimated
%   by the Ephraim-Malah decision-directed recursion:
%
%       xi(k,n) = alphaDD * |S_hat(k,n-1)|^2 / N(k,n)  +
%                 (1 - alphaDD) * max(gamma(k,n) - 1, 0)
%
%   with gamma = |X|^2 / N the a posteriori SNR. The gain is floored at
%   opts.Gmin to avoid audible dropouts and musical noise.
%
%   opts fields:
%       alphaDD (default 0.98)
%       Gmin    (default 10^(-18/20))  ~ -18 dB spectral floor

    if nargin < 3, opts = struct(); end
    opts = setDefault(opts, 'alphaDD', 0.98);
    opts = setDefault(opts, 'Gmin',    10^(-15/20));   % gain floor  ~ -15 dB
    opts = setDefault(opts, 'xiMin',   10^(-25/10));   % a-priori SNR floor
    xiMin = opts.xiMin;

    [numBin, numFrames] = size(magSq);
    G       = zeros(numBin, numFrames);
    snrPrio = zeros(numBin, numFrames);

    prevSest2 = zeros(numBin, 1);

    for n = 1:numFrames
        N        = max(noisePSD(:, n), 1e-12);
        gamma    = magSq(:, n) ./ N;
        snrPost  = max(gamma - 1, 0);

        if n == 1
            xi = max(snrPost, xiMin);
        else
            xi = opts.alphaDD * (prevSest2 ./ N) + ...
                 (1 - opts.alphaDD) * snrPost;
            xi = max(xi, xiMin);
        end

        Gn = xi ./ (1 + xi);
        Gn = max(Gn, opts.Gmin);

        G(:, n)       = Gn;
        snrPrio(:, n) = xi;
        prevSest2     = (Gn.^2) .* magSq(:, n);
    end
end

function s = setDefault(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
