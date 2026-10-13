# Speech Enhancement Toolkit (MATLAB)

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
Speech-enhancement-system/
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
└── docs/
    ├── SpeechEnhancer_Project_Report.pdf   project report
    └── SpeechEnhancer_Project_Report.docx  editable source of the report
```

Not in the repository:

- `assets/sample_clean.wav` — optional. If you add a clean speech
  recording here, `demo_offline` uses it instead of its built-in
  synthetic signal.
- `results/` — generated output, created on first use and git-ignored
  (see below).

## Requirements

- MATLAB with the Signal Processing Toolbox (for `butter`, `fir1`,
  `resample`, `hann`). The code targets R2021a or later; it has been
  run on R2025b, and older releases have not been re-verified.
- Audio recording uses `audiorecorder` (no Audio Toolbox needed).

## How to run

Set MATLAB's current folder to the repository root (the folder that
contains `SpeechEnhancerApp.m`), so the `+dsp` and `+senh` packages are
found:

```matlab
% Headless demo (recommended smoke test first):
>> demo_offline

% Launch the GUI:
>> app = SpeechEnhancerApp;
```

**Live demo tip.** In the GUI, press **Record**, stay silent for about
half a second (so the noise bootstrap has clean noise-only data), then
speak. Press **Stop → ENHANCE → Play enhanced**.

If your mic misbehaves during the presentation, press **Load audio** and
pick any WAV, FLAC, MP3 or OGG file instead — the pipeline works
identically. No audio clips are shipped with the repository.

## Where saved files live

All generated audio lands under `results/` in the project root (created
on first use, git-ignored):

- `results/enhanced_<timestamp>.wav` — default name and folder offered by
  the GUI's **Save enhanced** button.
- `results/offline/{noisy,wiener,specsub}.wav` — output of `demo_offline`.
- `results/compare/{white,pink,babble}_{noisy,old,new}.wav` — output of `demo_compare`.

`demo_offline` also opens three MATLAB figures: waveforms, spectrograms,
and the Wiener gain surface plus its mean-vs-frequency profile.
