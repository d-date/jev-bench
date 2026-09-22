# Jev and Foundation Models benchmark

This benchmark compares four paths for 12 Japanese support inquiries. Arms A, C, and D use [swift-jev](https://github.com/d-date/swift-jev)'s `JevClient` and read typed answers through `ChoiceQuestion<Department>` and `NoulQuestion`. The Swift package pins a specific swift-jev revision so the client does not change between runs.

| Arm | Path |
|---|---|
| A | Raw Japanese inquiry → Jev |
| B | Raw Japanese inquiry → Foundation Models classifier |
| C | Foundation Models structured English normalizer → Jev |
| D | Raw inquiry → Jev assessment; FM receives both and makes the final routing decision |

For D, Jev supplies its department prediction, confidence, option probabilities,
and urgency probability. FM receives those values together with the original
Japanese inquiry. The per-sample output shows both D's Jev prediction and FM's
final prediction so changes can be counted directly.

On macOS 26 or later with Apple Intelligence enabled, provide `TYPESAFE_API_KEY` to the process and run from this directory:

```sh
swift run jevbench > run.out 2> run.err
```

Run it five times to assess variation. Each run writes `normalized.json`, the structured states sent to Jev in arm C. Move that file after each run if you want to retain all five. Run `python3 aggregate.py results-four-arms` to summarize a directory containing `run1.out` through `run5.out`.

The checked-in [`results-four-arms/`](results-four-arms/) were measured on a Mac
Studio (M4 Max, 128 GB), macOS 27.0, Swift 6.4 on 2026-09-23. All 240
arm/sample evaluations completed across five runs. The earlier A/B/C only
measurements remain in [`results/`](results/). The output files include
per-sample classifications and timing, and `normalized-run*.json` contains the
generated states sent to Jev in C. The API key is not stored in these files.

Department accuracy compares predictions with the dataset labels. Urgency reports *label agreement*: the `s11` urgent label is outside the urgency question's stated criteria, so that column cannot rank the arms. Repeated runs reuse the same 12 samples and are not 60 independent examples. The benchmark applies `>= 0.5` to a Noul probability.

In the four-arm runs, D's FM stage changed none of Jev's 60 department
predictions. Small differences between A and D arise from separate Jev calls.
