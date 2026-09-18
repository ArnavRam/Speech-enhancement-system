#Speech Enhancement Toolkit (MATLAB)

Single-channel speech-enhancement mini-project for a 3rd-year DSP course.
Records or loads a noisy speech signal and produces a cleaner version using
classical STFT-domain processing, with a secondary adaptive-filter
(LMS) comparison mode.

## Method (main pipeline)

1. Resample to 16 kHz, mono.
2. Pre-emphasis `H(z) = 1 − 0.97 z⁻¹`.
3. STFT: 32 ms Hann frames, 50 % overlap (COLA-satisfying).
4. Noise PSD estimation (speech-aware):
   - Bootstrap: per-bin 15 th percentile of `|X(k,n)|²` over the first
     ~1.5 s. Does *not* assume the region is silent.
   - Continuous update: MMSE speech-presence probability
     (Gerkmann–Hendriks, 2011) — per-bin SPP freezes the noise update
     during speech and lets it move only during noise-only intervals.
     A safety cap on SPP keeps a slow drift channel open.
5. Suppression gain:
   - **Wiener (recommended)**: `G = ξ / (1 + ξ)` with a priori SNR ξ
     obtained by the Ephraim–Malah **decision-directed** recursion.
   - **Spectral subtraction (Berouti)**: power subtraction with
     over-subtraction factor α and spectral floor β — optional comparison.
6. Apply `G(k,n)` to magnitude, keep noisy phase.
7. Inverse STFT with weighted overlap-add, then de-emphasis, then peak
   normalisation.

The Wiener + SPP variant is the reliable default: the SPP estimator
keeps the noise model from being contaminated by speech, so Wiener does
not over-suppress speech harmonics or consonants. The gain floor
(`-15 dB` by default) provides a small safety net against residual
musical noise without dulling speech.

## Secondary method (LMS tab)

Two-microphone adaptive noise cancellation, simulated end-to-end:

- Synthetic clean speech is generated internally.
- A "reference" noise is filtered through an unknown room-like FIR to
  create the noise component that hits the primary mic.
- Primary = clean + noise; the reference is available separately.
- Normalised LMS learns the FIR that maps reference to primary noise;
  the residual `e = d − y` is the enhanced speech.

This gives the viva a second, contrasting DSP concept (time-domain
adaptive filtering vs. STFT-domain masking) with a clean learning-curve
plot.

## Project layout

```
SpeechEnhancer/
├── +dsp/
│   ├── stftAnalyze.m         analysis STFT
│   ├── istftSynthesize.m     synthesis ISTFT (weighted OLA)
│   ├── estimateNoisePSD.m    SPP-based, speech-aware (default)
│   ├── estimateNoisePSD_minstats.m  legacy min-statistics (A/B only)
│   ├── wienerGain.m          decision-directed Wiener
│   ├── spectralSubtract.m    Berouti power subtraction
│   ├── lmsCancel.m           normalised LMS ANC
│   └── enhanceSpeech.m       top-level pipeline
├── +senh/
│   ├── addSyntheticNoise.m   white / pink / babble at chosen SNR
│   └── computeMetrics.m      SNR, seg-SNR, noise-floor drop
├── SpeechEnhancerApp.m       programmatic uifigure app
├── demo_offline.m            headless test / demo backup
├── demo_compare.m            A/B/C - noisy vs old vs new pipeline
├── assets/                   optional clean sample + generated outputs
└── docs/
    └── report_outline.md     report + viva talking points
```

## Requirements

- MATLAB R2021a or later.
- Signal Processing Toolbox (for `butter`, `fir1`, `resample`, `hann`).
- Audio recording uses `audiorecorder` (no Audio Toolbox needed).

## How to run

From the SpeechEnhancer project root:

```matlab
% Headless demo (recommended smoke test first):
>> demo_offline

% Launch the GUI:
>> app = SpeechEnhancerApp;
```

**Live demo tip.** In the GUI, press **Record**, stay silent for about
half a second (so the noise bootstrap has clean noise-only data), then
speak. Press **Stop → Process → Play enhanced**.

If your mic misbehaves during the presentation, load one of the
pre-recorded clips in `assets/` instead — the pipeline works identically.

## Files produced by `demo_offline`

Written into `assets/out/`:
- `noisy.wav`   — clean + injected noise at the chosen SNR.
- `wiener.wav`  — enhanced with the recommended pipeline.
- `specsub.wav` — enhanced with Berouti spectral subtraction (compare).

Three MATLAB figures also open: waveforms, spectrograms, and the Wiener
gain surface plus its mean-vs-frequency profile.

## What to say about metrics

The GUI shows an **input SNR** / **output SNR** / **SNR improvement** row.
For live recordings these are marked `n/a` because you have no clean
reference — this is honest, not a bug. Use the **synthetic test** in
`demo_offline.m` (which does know the clean signal) to quote hard numbers
in the report. For live captures, the **noise-floor drop** measured on
the initial silent segment is the reference-free number to quote — it
directly reflects what a listener perceives.
