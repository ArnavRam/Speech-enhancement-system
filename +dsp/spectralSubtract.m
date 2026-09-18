function G = spectralSubtract(magSq, noisePSD, opts)
%SPECTRALSUBTRACT  Berouti-style power spectral subtraction gain.
%   G = spectralSubtract(magSq, noisePSD, opts) returns the magnitude gain
%
%       G = sqrt( max( 1 - alpha * N/|X|^2 ,  beta * N/|X|^2 ) )
%
%   which corresponds to power subtraction with over-subtraction factor
%   alpha and spectral floor beta (relative to noise), as in
%   Berouti, Schwartz & Makhoul (1979). Larger alpha removes more noise
%   at the cost of speech distortion; larger beta reduces musical noise.
%
%   opts fields:
%       oversub (default 2.0)   alpha
%       floor   (default 0.02)  beta

    if nargin < 3, opts = struct(); end
    opts = setDefault(opts, 'oversub', 2.0);
    opts = setDefault(opts, 'floor',   0.02);

    ratio = noisePSD ./ max(magSq, 1e-12);
    gsq   = max(1 - opts.oversub .* ratio, opts.floor .* ratio);
    G     = sqrt(max(gsq, 0));
end

function s = setDefault(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
