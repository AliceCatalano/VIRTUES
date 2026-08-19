%% sanity_check_features.m
% Run after gsr_extract_features.m to catch structural/units problems
% before feeding T into any LMM. Prints a report; produces a few plots.

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'eda_features.mat');
if ~isfile(feat_file)
    error('sanity_check_features: %s not found -- run gsr_extract_features(config()) first', feat_file);
end
loaded = load(feat_file, 'T', 'T_coll');
T = loaded.T;
T_coll = loaded.T_coll;

fprintf('=== Table shape ===\n');
fprintf('Block-level rows: %d   Collision-level rows: %d\n', height(T), height(T_coll));
fprintf('Unique subjects: %d\n', numel(unique(T.subject)));

%% 1. Row counts per subject / phase_type
fprintf('\n=== Rows per subject x phase_type (expect training=50, baseline=5, test=5) ===\n');
counts = groupsummary(T, {'subject','phase_type'});
pivoted = unstack(counts(:, {'subject','phase_type','GroupCount'}), 'GroupCount', 'phase_type');
disp(pivoted);

expected = struct('training', cfg.n_training_reps * numel(cfg.training_levels), ...
                   'baseline', numel(cfg.level_names) * numel(cfg.baseline_phases), ...
                   'test',     numel(cfg.level_names) * numel(cfg.test_phases));
fn = fieldnames(expected);
for i = 1:numel(fn)
    col = fn{i};
    if ~ismember(col, pivoted.Properties.VariableNames), continue; end
    short = pivoted.subject(pivoted.(col) < expected.(col) | isnan(pivoted.(col)));
    if ~isempty(short)
        fprintf('  [short on %s, expected %d] %s\n', col, expected.(col), strjoin(cellstr(short), ', '));
    end
end

%% 2. Group balance
fprintf('\n=== Group balance ===\n');
subj_group = unique(T(:, {'subject','haptic'}), 'rows');
fprintf('Haptic=true subjects: %d   Haptic=false subjects: %d\n', ...
    sum(subj_group.haptic), sum(~subj_group.haptic));

%% 3. Duplicate acquisition rows
fprintf('\n=== Duplicate check ===\n');
key = strcat(T.subject, '|', T.phase, '|', T.acquisition);
[~, ia] = unique(key);
n_dup = height(T) - numel(ia);
if n_dup > 0
    fprintf('  WARNING: %d duplicate subject+phase+acquisition rows found\n', n_dup);
    dup_keys = key(setdiff(1:height(T), ia));
    disp(unique(dup_keys));
else
    fprintf('  none found\n');
end

%% 4. Physiological plausibility ranges
fprintf('\n=== Range checks (flag if outside expected physiological bounds) ===\n');
check_range(T, 'scl_mean',  0.5, 30,  'uS (typical resting-to-task SCL)');
check_range(T, 'gsr_mean',  0.5, 30,  'uS');
check_range(T, 'scr_freq',  0,   40,  'SCRs/min');
check_range(T, 'scr_mean_amp', 0, 5,  'uS (per-SCR amplitude)');
check_range(T, 'duration_s', 1, 600,  's (per acquisition)');

%% 5. NaN summary
fprintf('\n=== NaN counts per numeric column ===\n');
numeric_vars = T.Properties.VariableNames(varfun(@isnumeric, T, 'OutputFormat','uniform'));
for i = 1:numel(numeric_vars)
    v = numeric_vars{i};
    n_nan = sum(isnan(T.(v)));
    if n_nan > 0
        fprintf('  %-25s %d NaN (%.1f%%)\n', v, n_nan, 100*n_nan/height(T));
    end
end
fprintf('(NaN in repetition for baseline/test rows, and in collision_* columns when no\n');
fprintf(' collision_results.mat existed, is expected. NaN elsewhere is not.)\n');

%% 6. Quick visual distributions
figure('Name','Feature distributions','Position',[100 100 1000 600]);
vars_to_plot = {'scl_mean','scr_freq','scr_mean_amp','gsr_mean'};
for i = 1:numel(vars_to_plot)
    subplot(2,2,i);
    histogram(T.(vars_to_plot{i}), 30);
    title(vars_to_plot{i}, 'Interpreter','none');
end

figure('Name','By group and phase','Position',[100 100 1000 400]);
subplot(1,2,1);
boxchart(categorical(T.haptic), T.scl_mean, 'GroupByColor', categorical(T.phase_type));
title('scl\_mean by haptic group / phase');
legend('Location','best');
subplot(1,2,2);
boxchart(categorical(T.haptic), T.scr_freq, 'GroupByColor', categorical(T.phase_type));
title('scr\_freq by haptic group / phase');
legend('Location','best');

fprintf('\nDone. Review printed warnings above and the two figure windows.\n');


function check_range(T, varname, lo, hi, unit)
    v = T.(varname);
    bad = v < lo | v > hi;
    bad = bad & ~isnan(v);
    if any(bad)
        fprintf('  [%s] %d/%d rows outside [%.2f, %.2f] %s\n', ...
            varname, sum(bad), height(T), lo, hi, unit);
        bad_rows = T(bad, {'subject','phase','acquisition',varname});
        disp(bad_rows(1:min(10,height(bad_rows)), :));
        if height(bad_rows) > 10
            fprintf('  ... and %d more\n', height(bad_rows)-10);
        end
    else
        fprintf('  [%s] all values within [%.2f, %.2f] %s\n', varname, lo, hi, unit);
    end
end