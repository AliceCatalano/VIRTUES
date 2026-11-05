# Exploratory analysis plan, written before these results were computed

Date: 2026-11-05. Author: Claude, for the VIRTUES analysis.

Everything here is exploratory and must be reported as such. It was written after the main group
results were known, but before any test below was run. It is not a preregistration.
All tests use subjects as the unit of inference or by-subject random slopes. s16N is excluded from
collision outcomes. One Benjamini-Hochberg family covers all tests in sections 1 to 8 together.

## Performance outcomes used throughout
Completion time, collision count, log TSSF, log TSSV.

## 1. Feedback on at the end (Test3). Needs confirmation of what Test3 was.
Assumption, from survey comments: both groups had vibrotactile feedback in Test3 and neither had it in Test2.
- Change Test2 to Test3 in each group, on each performance outcome.
- Group difference in that change: does feedback help more after training with it?
Test3 force and vibration were not visually screened as the other phases were, so TSSF and TSSV here
use rank-based tests as well.

## 2. Online benefit during training
HF vs NHF on each subject's mean across all training trials, each performance outcome (Welch t, Hedges g).

## 3. Feedback dependence (guidance hypothesis)
Per subject and level: last 3 training repetitions vs the same level at Baseline2. Group difference in that
change on each performance outcome. Assumes the training and Baseline tasks are the same task.

## 4. Consistency
Within-subject coefficient of variation of completion time across repetitions, averaged over levels, and
SD of collision count across repetitions. HF vs NHF.

## 5. Workload efficiency
Paas & Van Merrienboer efficiency, E = (z performance - z workload) / sqrt(2), per subject per level, using completion
time and composite SURG-TLX, z-scored across the sample within level. HF vs NHF on the mean across levels.

## 6. Do objective measures track reported workload?
Repeated-measures correlation across the 5 levels between composite SURG-TLX and each of: completion time,
collisions, log TSSF, tonic SCL, SCR frequency, normalised pupil, per-trial gaze entropy, corrected fixation rate.
Level order is fixed, so this cannot separate workload from practice or fatigue.

## 7. Who benefits? Individual differences
Group x moderator on the subject-level Baseline1 to Baseline2 change in completion time and collisions, for
video-game frequency and prior robot experience.

## 8. Perceived vs measured benefit
Closing-survey item "supported my performance" (and "made me more aware of contacts"):
- HF vs NHF rating (rank-sum).
- Rank correlation with each person's measured Test2 to Test3 change in completion time and collisions.
The survey has identifier problems (S02 appears twice; 20h conflicts with s20N), so S02 is excluded
and groups are taken from the study's subject list, not the survey.

## Amendment, 2026-11-05, before any test in this file was run
`Draft_reports_2026.docx` says the final peg-transfer phase (Test3) was performed "with or without haptic
feedback" and was fixed-time, with as many repetitions as possible. Section 1's assumption is therefore
unconfirmed, and completion time is not a valid outcome there. Sections 1 and the Test3 part of 8 are
deferred, and no Test3 group result is computed, until the conditions and repetition counts are known from
the researcher. The BH family below then covers sections 2 to 8 as run. Deferred tests get their own family.

## Amendment 2, 2026-11-05, before any Test3 group result was computed
The researcher confirmed that Test3 used the opposite condition to training: HF performed it with feedback off
and NHF with feedback on. Repetition counts were noted by hand. Everyone answered the closing survey after the
final rest, so NHF ratings rest on Test3 alone, while HF ratings follow training with feedback.

Consequence: group and feedback condition are fully confounded in Test3. It cannot show whether feedback helps
on its own, or whether that depends on training. It can only compare "feedback newly on" with "feedback newly off".

Replacement for section 1, as its own BH family, all reported as HF minus NHF:
- Repetitions completed in Test3, adjusted for Test2 completion time (ANCOVA), and unadjusted.
- Per-minute log TSSF and log TSSV in Test3, adjusted for the same measure in Test2. Rank-based check included,
  because Test3 force and vibration were not visually screened.
- Tonic SCL, corrected fixation rate and corrected saccade rate in Test3, adjusted for the same measure in Test2.
Replacement for the deferred part of section 8: within each group, rank correlation of "supported my performance"
with repetitions completed in Test3, and with Baseline1 to Baseline2 improvement in completion time.

Survey identifiers: use the last S02 entry, per the researcher. Row "20h" is resolved only from evidence in the
files, and the result is reported with that row excluded if the evidence is unclear.

## Amendment 3, 2026-11-05, made AFTER seeing a first Test3 output
The first run rejected force and vibration for 24 subjects with a 5% missing-data gate. The cause is that the
NIDAQ recording ends early in Test3 for those subjects (13 NHF, 11 HF), often at 100 to 170 s of about 185 s.
That first output had all p_FDR = .45, and it is not used. Change: TSSF and TSSV in Test3 are rates over the time actually
recorded, requiring at least 60 s, with a sensitivity analysis on the first 75 s only. Subjects with whole-subject
sensor exclusions stay excluded. No other test or outcome changes.

## Not planned, and not to be added after seeing results
No searching over additional outcomes, subgroups, time windows or exclusions. Any further idea gets written here
first, with its date, and is labelled as added later.
