function [y, e, w, mseTrace] = lmsCancel(d, xref, filterLen, mu, opts)
%LMSCANCEL  Adaptive noise cancellation via Normalised LMS.
%   [y, e, w] = lmsCancel(d, xref, filterLen, mu, opts) treats d as the
%   primary microphone (speech + noise) and xref as a correlated reference
%   for the noise. An adaptive FIR of length filterLen is trained to
%   estimate the noise component of d from xref; the residual e = d - y
%   is the enhanced speech.
%
%   Uses Normalised LMS for stability across signal levels:
%
%       w(n+1) = w(n) + mu * x(n) * e(n) / (x(n)'x(n) + eps)
%
%   opts.leak  (default 0)      : optional leakage factor for stability
%   opts.eps   (default 1e-6)   : NLMS regularisation

    if nargin < 5, opts = struct(); end
    if ~isfield(opts, 'leak'), opts.leak = 0; end
    if ~isfield(opts, 'eps'),  opts.eps  = 1e-6; end

    d    = d(:);
    xref = xref(:);
    N    = min(numel(d), numel(xref));
    d    = d(1:N);
    xref = xref(1:N);

    w        = zeros(filterLen, 1);
    y        = zeros(N, 1);
    e        = zeros(N, 1);
    mseTrace = zeros(N, 1);
    xbuf     = zeros(filterLen, 1);
    emaMse   = 0;
    emaAlpha = 0.995;

    for n = 1:N
        xbuf = [xref(n); xbuf(1:end-1)];
        yn   = w.' * xbuf;
        en   = d(n) - yn;
        normX = xbuf.' * xbuf + opts.eps;
        w = (1 - opts.leak) * w + (mu / normX) * xbuf * en;
        y(n) = yn;
        e(n) = en;
        emaMse = emaAlpha * emaMse + (1 - emaAlpha) * en^2;
        mseTrace(n) = emaMse;
    end
end
