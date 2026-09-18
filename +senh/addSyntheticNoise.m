function [y, noise, actualSNR] = addSyntheticNoise(clean, fs, targetSNRdB, noiseType)
%ADDSYNTHETICNOISE  Add coloured noise at a specified SNR.
%   [y, noise, actualSNR] = addSyntheticNoise(clean, fs, targetSNRdB, noiseType)
%   returns clean + noise where noise is scaled so that
%     10*log10( sum(clean.^2) / sum(noise.^2) ) == targetSNRdB.
%
%   noiseType: 'white' (default) | 'pink' | 'babble'
%   'babble' is a coarse approximation using low-pass filtered white noise
%   with random amplitude modulation - good enough for demo purposes when
%   a real babble recording is not available.

    if nargin < 4, noiseType = 'white'; end
    clean = clean(:);
    N = numel(clean);

    switch lower(noiseType)
        case 'white'
            n = randn(N, 1);
        case 'pink'
            n = pinkNoise(N);
        case 'babble'
            n = randn(N, 1);
            [b, a] = butter(4, 3500/(fs/2));
            n = filter(b, a, n);
            env = 0.6 + 0.4 * abs(filter(ones(1, round(fs*0.05))/round(fs*0.05), 1, randn(N,1)));
            n = n .* env;
        otherwise
            error('addSyntheticNoise:type', 'Unknown noise type: %s', noiseType);
    end

    sigPow   = mean(clean.^2) + 1e-12;
    noisePow = mean(n.^2) + 1e-12;
    scale = sqrt(sigPow / noisePow) * 10^(-targetSNRdB/20);
    noise = scale * n;

    y = clean + noise;
    actualSNR = 10*log10(sum(clean.^2) / sum(noise.^2));
end

function n = pinkNoise(N)
    % Voss-McCartney approximation via 1/f IIR shaping of white noise.
    w = randn(N, 1);
    b = [0.049922035 -0.095993537 0.050612699 -0.004408786];
    a = [1 -2.494956002 2.017265875 -0.522189400];
    n = filter(b, a, w);
    n = n / (std(n) + 1e-12);
end
