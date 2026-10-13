classdef ShortAudioTest < matlab.unittest.TestCase
%SHORTAUDIOTEST  Regression tests for very short audio clips (issue #1).
%   At 16 kHz the pipeline uses 512-sample frames with a 256-sample hop,
%   so a clip of 768 samples (48 ms) or fewer gives only one or two STFT
%   frames. dsp.estimateNoisePSD used to force its bootstrap window to at
%   least three frames and failed with MATLAB:badsubscript.
%
%   Run from the project root:
%       >> results = runtests('tests')

    properties (TestParameter)
        algorithm  = {'wiener', 'specsub'}
        numSamples = struct('oneFrame10ms',  160, 'oneFrame32ms',  512, ...
                            'twoFrames40ms', 640, 'twoFrames48ms', 768, ...
                            'threeFrames',   769)
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function seedRandom(testCase)
            testCase.addTeardown(@rng, rng(1));
        end
    end

    methods (Test)
        function enhancesShortClip(testCase, algorithm, numSamples)
            x = 0.1 * randn(numSamples, 1);
            y = dsp.enhanceSpeech(x, 16000, struct('algorithm', algorithm));
            testCase.verifySize(y, [numSamples 1]);
            testCase.verifyTrue(all(isfinite(y)), 'Output contains NaN or Inf.');
        end

        function enhancesShortClipAfterResampling(testCase, algorithm)
            % 40 ms at 44.1 kHz becomes 640 samples (two frames) at 16 kHz.
            x = 0.1 * randn(1764, 1);
            [y, info] = dsp.enhanceSpeech(x, 44100, struct('algorithm', algorithm));
            testCase.verifyEqual(info.fs, 16000);
            testCase.verifySize(y, [640 1]);
            testCase.verifyTrue(all(isfinite(y)), 'Output contains NaN or Inf.');
        end

        function noiseEstimateCoversEveryFrame(testCase)
            for numFrames = 1:3
                magSq    = rand(257, numFrames) + 0.01;
                noisePSD = dsp.estimateNoisePSD(magSq, 16000, 256);
                testCase.verifySize(noisePSD, [257 numFrames]);
                testCase.verifyTrue(all(isfinite(noisePSD(:)) & noisePSD(:) > 0), ...
                    sprintf('Invalid noise estimate for %d frame(s).', numFrames));
            end
        end
    end
end
