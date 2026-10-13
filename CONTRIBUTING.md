# Contributing

Thanks for helping improve the Speech Enhancement Toolkit. This is a
small MATLAB project, so the process is deliberately light.

## Setup

- MATLAB with the Signal Processing Toolbox (developed and tested on
  R2025b; the code targets R2021a or later).
- Clone the repository and set MATLAB's current folder to its root (the
  folder containing `SpeechEnhancerApp.m`) so the `+dsp` and `+senh`
  packages are found.

## Reporting a bug

Open an issue with the **Bug report** template. Include your MATLAB
release, the exact commands or GUI steps, what you expected, and the full
error message. A short script that reproduces the problem is the most
useful thing you can provide.

## Making a change

1. Open (or pick) an issue describing the problem.
2. Create a branch from `main`, e.g. `fix/<short-name>` or
   `docs/<short-name>`. Do not commit directly to `main`.
3. Keep the change small and focused; avoid unrelated reformatting.
4. For a bug fix, add a regression test in `tests/` that fails before
   the fix and passes after it.
5. Run the tests from the repository root:

   ```matlab
   results = runtests('tests');
   table(results)
   ```

   If you change the DSP pipeline, also run `demo_offline` and check that
   it completes.
6. Open a pull request against `main` using the template, link the issue
   (`Fixes #<number>`), and describe how you tested it.

## Code style

- Follow the existing style: functions in the `+dsp` (signal processing)
  and `+senh` (evaluation helpers) packages, a help comment at the top of
  each function, and optional parameters passed in an `opts` struct with
  defaults filled in by a local `setDefault` helper.
- Do not commit generated audio or anything under `results/`.

## License

By contributing, you agree that your contributions are released under
the project's license (see `LICENSE`).
