# Report & Viva Outline

## 1. Problem statement

Single-channel additive-noise speech enhancement: given
`y(n) = s(n) + v(n)` where `s` is speech and `v` is background noise
uncorrelated with `s`, estimate `s(n)`. Constraints: one microphone, no
external reference for the noise, must run in MATLAB with modest latency.

## 2. Why the STFT / short-time processing

Speech is quasi-stationary over 20–40 ms; noise typically stationary over
longer windows. Move to the STFT domain to exploit both scales:

- Short-time spectra let us separate low-SNR bins from high-SNR bins.
- The magnitude of speech is sparse in TF; noise fills the "gaps".
- Overlap-add reconstruction gives artefact-free time-domain output.

Frame length 32 ms (512 samples @ 16 kHz), 50 % overlap, Hann window
(satisfies the constant-overlap-add condition for `w²`, so weighted OLA
reconstructs exactly when no spectral modification is applied).

## 3. Noise-PSD estimation  (speech-aware, MMSE-SPP)

The previous version used minimum-statistics with a 1.5× bias and a
"silent start" assumption. Two things went wrong: (i) the bias inflated
the noise floor by ~50 %, so Wiener over-suppressed speech; (ii) if the
file began with speech the bootstrap was contaminated, and the min-tracker
did not recover during the utterance. Replaced with the MMSE
speech-presence-probability estimator of **Gerkmann & Hendriks (2011)**:

1. **Robust bootstrap** — per-bin 15 th percentile of `|X(k,n)|²` over
   the first 1.5 s. Even if that window is entirely speech, each
   frequency bin has some quiet frames within it; the low-quantile
   captures them. No "silent start" assumption.
2. **Per-bin, per-frame SPP** — under a fixed a-priori SNR `ξ_H1 = 15 dB`,
   compute the a-posteriori SNR `γ = |X|²/N̂` and the log-likelihood
   `logZ = log(q/(1−q)) − log(1+ξ_H1) + γ·ξ_H1/(1+ξ_H1)`, then
   `p̂ = 1/(1+exp(−logZ))`. Temporally smooth `p̂` with α = 0.9 and
   **cap at 0.99** as a safety valve (noise can still track slow drift
   during long voiced passages).
3. **Speech-aware noise update** — effective smoothing constant
   `α_eff = α_N + (1−α_N)·p̂`, with `α_N = 0.8`. When `p̂ → 1` speech
   is likely and `α_eff → 1` freezes the noise estimate; when `p̂ → 0`
   noise is dominant and `α_eff = α_N` updates fast. The 1.5× bias is
   gone — SPP itself provides the necessary bias against speech leakage.

## 4. Suppression gain

### Wiener with decision-directed a priori SNR (main method)

- A posteriori SNR: `γ(k,n) = |X(k,n)|² / N̂(k,n)`.
- A priori SNR (Ephraim–Malah): `ξ = α_DD · |Ŝ(k,n-1)|²/N̂(k,n) +
  (1 − α_DD)·max(γ − 1, 0)`, with `α_DD ≈ 0.98`.
- Gain: `G(k,n) = ξ / (1 + ξ)` (Wiener). A-priori SNR floored at −25 dB;
  gain floored at −15 dB. The gain floor is deliberately mild — the SPP
  estimator no longer inflates noise, so aggressive flooring is not
  needed and hurts intelligibility of consonants and harmonics.
- Apply `G` to magnitude only; keep noisy phase (near-optimal for SNR
  above ~-5 dB and much simpler than phase-sensitive reconstruction).

### Berouti spectral subtraction (comparison)

`|Ŷ|² = max(|X|² − α·N̂, β·N̂)`, α ∈ [1, 3], β small. Simpler, well
known, but more musical noise — good foil to demonstrate why Wiener +
minimum-statistics is preferred.

## 5. Secondary comparison: LMS ANC

Two-microphone adaptive noise cancellation, simulated. The reference is
filtered by an unknown room-like FIR to produce the noise at the primary
mic. Normalised LMS (`μ / (x'x + ε)`) learns the mapping; the error
signal `e = d − y` is the enhanced speech. Report shows:

- Convergence of the learning curve.
- SNR gain vs step size and filter length.
- Why the STFT method is preferable when no reference mic exists.

## 6. Evaluation

**With clean reference** (synthetic-noise mode):
- Global SNR before / after.
- Segmental SNR (30 ms frames, clipped to `[-10, 35]` dB per the
  standard convention).

**Without clean reference** (real recordings):
- Noise-floor drop measured on the initial silent segment.
- Visual spectrogram comparison — the noise-floor floor visibly recedes.

## 7. Results to include

- Waveform: clean / noisy / enhanced (stacked).
- Spectrogram: clean / noisy / enhanced (stacked).
- Wiener gain surface `G(k, n)` (image) + mean gain vs frequency.
- Bar chart: input SNR, output SNR, improvement, for `{white, pink,
  babble}` × `{Wiener, Spectral Subtraction}`. `demo_offline.m` gives
  you the numbers per run — record 3–4 runs to build the bar chart.
- LMS learning curve.

## 8. Practical limitations to acknowledge (viva-friendly)

- **Speaker must stay silent for the first ~0.5 s** so the bootstrap has
  clean noise data. Otherwise noise is overestimated and speech is
  attenuated.
- **Non-stationary noise** (door slam, someone else talking) can leak
  through — minimum statistics adapts slowly by design.
- **Very low SNR (< −5 dB)** produces audible musical noise even after
  gain flooring; deep-learning suppressors do better but were out of
  scope.
- **Phase is unchanged**, so the reconstructed signal inherits noisy
  phase — acceptable for intelligibility, not for pristine quality.

## 9. Viva talking points (short answers you can memorise)

- *Why 32 ms frames?* — Speech is quasi-stationary over 20–40 ms; 32 ms
  gives 50 Hz resolution which resolves formants without smearing
  transients too much.
- *Why 50 % Hann overlap?* — Hann `w²` sums to a constant at 50 %
  overlap, so weighted OLA reconstructs perfectly when no modification
  is applied. Fewer overlap → COLA violated; more overlap → wasted work.
- *Why decision-directed?* — Direct `γ − 1` is noisy per frame and
  produces musical noise; DD averages across frames and produces
  smoother, more perceptually acceptable enhancement.
- *Why did you replace minimum statistics with SPP?* — Minimum
  statistics is speech-blind and needs a bias factor. On files that
  start with speech, the bootstrap is contaminated and the min-tracker
  cannot recover. SPP (Gerkmann–Hendriks 2011) freezes the noise
  update per-bin when speech is likely there, so speech harmonics stop
  leaking into "noise". Same computational cost, dramatically better
  speech preservation.
- *What if the SPP mistakenly declares noise-only regions as speech?* —
  We cap the smoothed SPP at 0.99 so `α_eff` cannot reach 1. The noise
  estimate can still crawl up during long voiced regions if the noise
  itself is drifting. This is the "safety valve".
- *Why keep noisy phase?* — Above ~0 dB SNR, phase estimation gives
  negligible improvement; magnitude dominates perception. Keeps the
  pipeline simple.
- *Why not deep learning?* — Overkill for a 3rd-year DSP course, hard
  to defend as *DSP*, and doesn't fit the 3-day timeline.
- *Where does LMS fit?* — Complementary: needs a reference mic. Useful
  when you can get one; the STFT method wins when you can't.

## 10. Deliverables checklist

- [ ] `assets/sample_clean.wav`, `sample_noisy_recording.wav`,
      `sample_babble_reference.wav` (2–3 backup clips for the demo).
- [ ] Screenshots of the GUI in Enhance and LMS tabs.
- [ ] Figures from `demo_offline.m` (waveforms, spectrograms, Wiener
      gain).
- [ ] SNR/segSNR table across noise types.
- [ ] Report following sections 1–8 above.
