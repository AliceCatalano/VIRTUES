# Test3 collision-locked EDA and eye analysis: plan written before the EDA and eye results

Date: 2026-11-05. Author: Claude. Status: exploratory, not registered.

## Design facts
Final peg-transfer phase. Participants did as many transfers as possible within 180 s and did not know the limit.
HF had feedback off and NHF had it on. Group and condition are fully confounded, so group contrasts here mean
"newly off after training with it" vs "newly on after training without it". They cannot isolate the effect of feedback.

## Questions, in order
Q1. Are collisions followed by EDA and pupil responses above chance?
Q2. On collisions that produce a larger EDA response, is the pupil response also larger, beyond background coupling?
Q3. Do Q1 or Q2 differ by group, and do they change from Test2 to Test3 differently by group?
Q4. Do responses scale with impact strength or change with time on task?

## Events
Collision times come from the audio detector used for the saved results (80-1000 Hz, max across channels, 20 ms RMS,
threshold 0.015, at least 0.5 s apart). It must reproduce the saved Test2 results before use. Detection is checked for
threshold sensitivity, for noise floor, and against the independent NIDAQ accelerometer wherever that recording exists,
because feedback being on could leak into the detection signal. s16N is excluded if the artifact persists.

## Signals
EDA: microsiemens at 10 Hz, gaps over 1 s masked rather than rejecting the trial, cvxEDA, using the phasic driver.
Single-event EDA response: driver integral from 1 to 4 s after the collision.
Pupil: duplicates removed, blinks removed with a 100 ms margin, 2-8 mm limit, outliers by a median-based dilation-speed rule
on 10 Hz data, gaps up to 250 ms interpolated, 4 Hz low-pass.
Single-event pupil response: mean over 0.5 to 2.5 s minus mean over -0.5 to 0 s, in mm. No peak values, which are biased by noise.
Gaze: saccade rate 0 to 1 s vs -1 to 0 s, and gaze dispersion 0 to 2 s vs -2 to 0 s, using the corrected detector.

## Overlap
Collisions are often seconds apart and EDA responses last longer. Time courses therefore come from a per-subject FIR
deconvolution (0.5 s bins, -2 to 10 s for EDA and -2 to 6 s for pupil) with drift terms, not from simple averaging.

## Inference. Subjects are the unit.
Chance level: for each subject, 2,000 circular shifts of the collision train inside the task, at least 10 s, keep the
timing structure and each signal's autocorrelation.
Q1. Observed minus shifted mean per subject, tested across subjects with sign-flip permutation. FIR time courses use
cluster-based sign-flip tests.
Q2. Per-subject Spearman r between event EDA and pupil responses, compared with the same statistic under shifted times
(the shift moves both signals together, which keeps background coupling in the null). Then a mixed model:
EDA ~ pupil_within * group + log intensity + time in task + previous interval + baseline pupil + (1 + pupil_within | subject).
Q3. Welch tests with CIs, Hedges g, JZS Bayes factors. Test2 to Test3 change per subject, using the same pipeline in both.
Q4. Mixed models with by-subject slopes for log audio intensity and for time in task.
Multiple testing: BH across the Q1 to Q4 primary tests listed in the output table.

## Sensitivity
Windows shorter than 170 s (s03H, s08H, s10H) removed. Rank-transformed EDA response. Events with no other collision in the
previous 5 s only. NIDAQ peak as the intensity measure where available.

## Amendment 1, 2026-11-05, after detector validation and before any EDA or eye result
Detector reproduces all 400 saved Test2 collisions. s16N is normal in Test3 (25 events), so it stays in Test3 and is
removed only from Test2 comparisons. Event times are corrected by the audio-NIDAQ lag when cross-correlation is at least .7 and
the lag is at least 50 ms. Minimum events per subject: 5 for response tests and FIR, 8 for within-subject coupling.

## Amendment 2, 2026-11-05, before any EDA or eye result was viewed
Secondary, because the question covers eye tracking in general: mixed models of the EDA response on the saccade-rate change and on
the gaze-dispersion change, with the same structure as Q2. Both are secondary and sit outside the primary BH family.

## Amendment 3, 2026-11-05, added AFTER seeing that collisions showed no above-chance response
These are controls, labelled as post hoc. They test whether the null is real, and were not planned at the start.
A. Injection and recovery: known responses added to the real Test3 signals at collision times (EDA 0.02, 0.05, 0.1 uS with a Bateman
shape; pupil 0.02, 0.05, 0.1 mm with a Hoeks-Levelt shape), then the same metrics and tests.
B. Isolated collisions (none within 6 s either side) vs collision-free moments in the same trial (at least 6 s from any collision), raw
conductance change 1-5 s vs -1-0 s, and pupil change 0.5-2.5 s vs -0.5-0 s, per subject. Phases: Test3, Test2, Baseline2, training L1-L5.
s16N is excluded outside Test3.
C. Trial start as a reference event, same windows, to check that an event response can be seen at all.
Reason for B: at high collision rates, shifted times land near other real collisions, which can make the Q1 null too strict.

## Not done
No group-specific intensity bins, no pooled collision-level tests of group, no Levene tests on pooled collisions.
No extra outcomes, windows or subgroups are added after seeing results. Anything added later is dated and labelled here.
