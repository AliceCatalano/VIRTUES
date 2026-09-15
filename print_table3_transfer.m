%% print_table3_transfer.m
% Prints the Baseline1-vs-Baseline2 (elastic task, SAP 4.3/H2) Phase x
% Haptic interaction for every outcome across all three modalities --
% exactly what Table 3 in PAPER_DRAFT_CONSOLIDATED.md needs. Pulls from
% the 'baseline_transfer_elastic' family already saved by
% run_transfer_lmms.m / run_eye_transfer_lmms.m /
% run_performance_transfer_lmms.m (run those first if the corresponding
% .mat file doesn't exist yet -- the script below tells you which is
% missing rather than silently skipping it).
%
% Note: collision_scr_amp_mean / collision_pupil_response_mean are NOT
% modeled at Baseline/Test (see run_transfer_lmms.m's header -- single
% unrepeated trials, too sparse for an event-locked estimate), so those
% two rows are correctly absent from Table 3, not a bug.

clear; clc;
cfg = config();

sources = struct( ...
    'file',     {fullfile(cfg.output_root,'transfer_lmm_results.mat'), ...
                  fullfile(cfg.output_root,'eye_transfer_lmm_results.mat'), ...
                  fullfile(cfg.output_root,'performance_transfer_lmm_results.mat')}, ...
    'modality', {'GSR', 'Eye', 'Performance'});

fprintf('%-14s %-22s %10s %10s %10s %10s  %s\n', ...
    'Modality', 'Outcome', 'beta', 'SE', 'p', 'p_FDR', 'RE note');

for s = 1:numel(sources)
    if ~isfile(sources(s).file)
        fprintf('  [MISSING] %s -- run %s first\n', sources(s).file, local_driver_name(sources(s).modality));
        continue;
    end
    loaded = load(sources(s).file, 'all_results');
    fam    = loaded.all_results.baseline_transfer_elastic;
    for i = 1:numel(fam.outcomes)
        r = fam.results{i};
        note = '';
        if isfield(r, 're_degenerate') && r.re_degenerate
            note = sprintf('flagged degenerate random-intercept (SD=%.3g)', r.re_intercept_sd);
        end
        fprintf('%-14s %-22s %10.4f %10.4f %10.4f %10.4f  %s\n', ...
            sources(s).modality, fam.outcomes{i}, r.interaction_beta, r.interaction_se, ...
            r.interaction_p, fam.p_fdr(i), note);
    end
end

function name = local_driver_name(modality)
    switch modality
        case 'GSR',         name = 'run_transfer_lmms';
        case 'Eye',          name = 'run_eye_transfer_lmms';
        case 'Performance',  name = 'run_performance_transfer_lmms';
    end
end
