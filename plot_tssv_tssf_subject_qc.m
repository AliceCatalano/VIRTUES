%% plot_tssv_tssf_subject_qc.m
% QC tool: shows TSSV/TSSF behavior per subject across training levels,
% baseline levels, and test phases, before and after removing known-
% noisy subjects, and reports exactly which subjects drive the
% difference between the two.
%
% Reads the RAW (pre-cleaning) force_vibration_features.mat so nothing
% is silently pre-filtered -- this script does its own filtering, in
% front of you, so you can see what's being removed and why.
%
% Run requirement: force_vibration_features.mat must already exist
% (i.e. perf_extract_force_vibration_features(cfg) has been run).

clear; clc; cfg = config();

% ---- Step 1: load the RAW, uncleaned feature table ----------------
% This is the table straight out of perf_extract_force_vibration_features,
% before ANY outlier exclusion script has touched it.
S = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T');
T = S.T;

% ---- Step 2: known/suspected noisy subjects, per sensor ------------
% TSSF: force (ATI Mini45) channel issues -- as you specified.
tssf_known_bad = {'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};

% TSSV: accelerometer issues -- from accel_exclusion_list.m (the
% "revised" exclusion script currently in your repo).
tssv_known_bad = {'subject_s09N','subject_s10H','subject_s11N','subject_s12H', ...
                   'subject_s44N','subject_s02N','subject_s48N','subject_s05N'};

metrics = struct('name',{'tssv','tssf'}, 'known_bad',{tssv_known_bad, tssf_known_bad});

% ---- Step 3: the three phase configurations to QC -------------------
% Training and Baseline both have a 1-5 difficulty-level structure, so
% they're plotted the same way (x = Level). Test has no level -- just
% Test1 and Test2 -- so it's plotted with x = Test phase instead.
phase_configs = struct( ...
    'phase_type', {'training','baseline','test'}, ...
    'x_is_level', {true,       true,      false}, ...
    'x_labels',   {{'L1','L2','L3','L4','L5'}, {'L1','L2','L3','L4','L5'}, {'Test1','Test2'}});

if ~exist(fullfile(cfg.output_root,'figures'),'dir')
    mkdir(fullfile(cfg.output_root,'figures'));
end

for m = 1:numel(metrics)
    oc        = metrics(m).name;
    known_bad = metrics(m).known_bad;

    for pc = 1:numel(phase_configs)
        ptype     = phase_configs(pc).phase_type;
        x_is_level= phase_configs(pc).x_is_level;
        x_labels  = phase_configs(pc).x_labels;
        n_x       = numel(x_labels);

        Tp = T(strcmp(T.phase_type, ptype), :);
        if x_is_level
            Tp = Tp(isfinite(Tp.level), :);
        end
        if isempty(Tp)
            fprintf('[skip] %s / %s: no rows found\n', upper(oc), ptype);
            continue;
        end

        % ---- per-subject, per-x-bin mean, log scale -----------------
        % TSSV/TSSF are sums of squares -- heavy-tailed, so log scale,
        % same as every outlier/stats script elsewhere in this pipeline.
        subj_list = unique(Tp.subject);
        n_subj    = numel(subj_list);
        mu_bin    = nan(n_subj, n_x);
        for si = 1:n_subj
            s = subj_list{si};
            for xi = 1:n_x
                if x_is_level
                    bin_mask = Tp.level == xi;
                else
                    bin_mask = strcmp(Tp.phase, x_labels{xi});
                end
                v = Tp.(oc)(strcmp(Tp.subject,s) & bin_mask & isfinite(Tp.(oc)) & Tp.(oc)>0);
                if ~isempty(v)
                    mu_bin(si,xi) = mean(log(v),'omitnan');
                end
            end
        end

        % ---- flag who's actually driving the extremes ----------------
        % overall_mu = each subject's own mean across all x-bins in this
        % phase. Flag a subject if they're on your known-bad list, OR if
        % they sit more than 3 MAD away from the across-subject median.
        overall_mu = mean(mu_bin,2,'omitnan');
        med_mu     = median(overall_mu,'omitnan');
        mad_mu     = mad(overall_mu,1);
        auto_flag  = abs(overall_mu - med_mu) > 3*mad_mu;
        is_known   = ismember(subj_list, known_bad);
        is_flagged = auto_flag | is_known;

        % ---- PLOT 1 -- everyone, flagged subjects highlighted --------
        figure('Position',[2000 2000 1400 1900]); hold on;
        for si = 1:n_subj
            col = [0.75 0.75 0.75];               % default: faint gray
            lw  = 0.75;
            if is_known(si)
                col = [0.85 0.10 0.10]; lw = 1.75; 
            elseif auto_flag(si)
                col = [1 0.5 0.0]; lw = 1.75; 
            end   % flagged: red
            plot(1:n_x, mu_bin(si,:), '-', 'Color', col, 'LineWidth', lw);
            if is_known(si)
                last = find(isfinite(mu_bin(si,:)), 1, 'last');
                if ~isempty(last)
                    text(last+0.08, mu_bin(si,last), erase(subj_list{si},'subject_'),'FontSize',8, 'Color',[0.85 0.10 0.10], 'FontWeight','bold');
                end
            elseif auto_flag(si)
                last = find(isfinite(mu_bin(si,:)), 1, 'last');
                if ~isempty(last)
                    text(last+0.08, mu_bin(si,last), erase(subj_list{si},'subject_'),'FontSize',10, 'Color',[1 0.5 0.0], 'FontWeight','bold');
                end
            end
        end
        grp_mean = mean(mu_bin,1,'omitnan');
        plot(1:n_x, grp_mean, 'k-', 'LineWidth', 3);
        xlabel(local_xlabel(ptype)); ylabel(sprintf('log(%s)', upper(oc)));
        title(sprintf('%s -- %s -- ALL subjects (red = known-bad orage = auto-flagged, n=%d flagged of %d)', ...
              upper(oc), ptype, sum(is_flagged), n_subj));
        xlim([0.8 n_x+0.5]); xticks(1:n_x); xticklabels(x_labels); grid on; box on;
        saveas(gcf, fullfile(cfg.output_root,'figures', sprintf('%s_%s_qc_all_subjects.png',oc,ptype)));

        % ---- PLOT 2 -- known-bad subjects removed ---------------------
        keep = ~is_known;
        figure('Position',[2000 2000 1400 1900]); hold on;
        for si = find(keep)'
            plot(1:n_x, mu_bin(si,:), '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.75);
        end
        grp_mean_clean = mean(mu_bin(keep,:),1,'omitnan');
        plot(1:n_x, grp_mean_clean, 'b-', 'LineWidth', 3);
        xlabel(local_xlabel(ptype)); ylabel(sprintf('log(%s)', upper(oc)));
        title(sprintf('%s -- %s -- known-bad subjects removed (n=%d excluded, %d remain)', ...
              upper(oc), ptype, sum(is_known), sum(keep)));
        xlim([0.8 n_x+0.5]); xticks(1:n_x); xticklabels(x_labels); grid on; box on;
        saveas(gcf, fullfile(cfg.output_root,'figures', sprintf('%s_%s_qc_cleaned.png',oc,ptype)));

        % ---- print exactly who was driving the result -----------------
        fprintf('\n=== %s / %s: known-bad subjects and their influence ===\n', upper(oc), ptype);
        fprintf('%-18s %10s %10s %10s\n','Subject','mean(log)','grp_med','dev(MAD)');
        for si = find(is_known)'
            fprintf('%-18s %10.3f %10.3f %10.2f\n', subj_list{si}, overall_mu(si), med_mu, ...
                    (overall_mu(si)-med_mu)/mad_mu);
        end

        extra_flagged = find(auto_flag & ~is_known)';
        if ~isempty(extra_flagged)
            fprintf('\n[!] Statistically extreme but NOT on your known-bad list -- check these:\n');
            for si = extra_flagged
                fprintf('%-18s %10.3f %10.3f %10.2f\n', subj_list{si}, overall_mu(si), med_mu, ...
                        (overall_mu(si)-med_mu)/mad_mu);
            end
        else
            fprintf('\nNo additional subjects auto-flagged beyond your known-bad list.\n');
        end

        fprintf('\nGroup mean BEFORE removing known-bad subjects: %.4f (log scale)\n', mean(overall_mu,'omitnan'));
        fprintf('Group mean AFTER  removing known-bad subjects: %.4f (log scale)\n', mean(overall_mu(keep),'omitnan'));
        fprintf('Shift from removing known-bad subjects: %.4f log-units\n', ...
                mean(overall_mu(keep),'omitnan') - mean(overall_mu,'omitnan'));
    end
end
%%
%% tssv_tssf_qc_followup.m
% Two follow-up QC checks on force_vibration_features.mat:
%
% PART A -- missingness audit: for each subject x phase-bin, what
% fraction of acquisitions have NO valid (finite, >0) tssv/tssf value?
% This catches cases like s20N/Test1, where the value isn't an extreme
% number (which the earlier QC script flags) -- it's just ABSENT,
% because perf_extract_force_vibration_features.m's Gate 2 noise check
% already NaN'd it before this table was ever saved. A subject who is
% ~100% missing in one bin but fine elsewhere is exactly the case the
% first QC script's value-based flagging cannot see.
%
% PART B -- per-repetition breakdown for one subject/metric/phase, so
% you can see exactly which acquisitions are driving a flagged mean
% (e.g. s38H / tssf / training).

clear; clc; cfg = config();
S = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T');
T = S.T;

% ---- PART A: missingness audit -------------------------------------
% For every subject, in every phase_type/level (or phase, for test),
% report: n_total acquisitions vs n_valid (finite & >0). Flag any bin
% where a subject has ZERO valid values but other subjects at that same
% bin mostly do have data -- that is a silent total-dropout, not an
% outlier.
fprintf('==================== PART A: missingness audit ====================\n');

phase_configs = struct( ...
    'phase_type', {'training','baseline','test'}, ...
    'x_is_level', {true,       true,      false}, ...
    'x_labels',   {{'L1','L2','L3','L4','L5'}, {'L1','L2','L3','L4','L5'}, {'Test1','Test2'}});

for oc = {'tssv','tssf'}
    oc = oc{1};
    fprintf('\n--- %s ---\n', upper(oc));
    for pc = 1:numel(phase_configs)
        ptype      = phase_configs(pc).phase_type;
        x_is_level = phase_configs(pc).x_is_level;
        x_labels   = phase_configs(pc).x_labels;
        n_x        = numel(x_labels);

        Tp = T(strcmp(T.phase_type, ptype), :);
        if x_is_level, Tp = Tp(isfinite(Tp.level), :); end
        if isempty(Tp), continue; end

        subj_list = unique(Tp.subject);
        for xi = 1:n_x
            if x_is_level
                bin_mask = Tp.level == xi;
            else
                bin_mask = strcmp(Tp.phase, x_labels{xi});
            end
            Tbin = Tp(bin_mask, :);
            if isempty(Tbin), continue; end

            % fraction valid across ALL subjects at this bin, for context
            pct_valid_all = 100 * mean(isfinite(Tbin.(oc)) & Tbin.(oc) > 0);

            for si = 1:numel(subj_list)
                s = subj_list{si};
                Ts = Tbin(strcmp(Tbin.subject, s), :);
                if isempty(Ts), continue; end
                n_tot   = height(Ts);
                n_valid = sum(isfinite(Ts.(oc)) & Ts.(oc) > 0);
                % flag: this subject has 0 valid values here, but the
                % bin overall has reasonable data elsewhere (so it's not
                % just a phase nobody has data for)
                if n_valid == 0 && pct_valid_all > 30
                    fprintf('[MISSING]  %-18s %s / %-6s  0/%d valid  (bin overall %.0f%% valid)\n', ...
                        s, ptype, x_labels{xi}, n_tot, pct_valid_all);
                end
            end
        end
    end
end

%% ---- PART B: per-repetition breakdown for a flagged subject ---------
% Edit subj/oc/ptype below to inspect any subject/metric/phase flagged
% by the main QC script. Defaults to s38H / tssf / training, per your
% question.
subj_check  = 'subject_s38H';
oc_check    = 'tssf';
ptype_check = 'training';

fprintf('\n================ PART B: per-acquisition breakdown ================\n');
fprintf('%s / %s / %s\n', subj_check, upper(oc_check), ptype_check);

Tc = T(strcmp(T.subject, subj_check) & strcmp(T.phase_type, ptype_check) ...
       & isfinite(T.(oc_check)) & T.(oc_check) > 0, :);
if isempty(Tc)
    fprintf('No valid rows found for this subject/metric/phase.\n');
else
    Tc = sortrows(Tc, oc_check, 'descend');
    fprintf('%-10s %-10s %12s %12s\n', 'Level', 'Rep', 'raw', 'log');
    for i = 1:height(Tc)
        fprintf('%-10s %-10s %12.4g %12.4f\n', ...
            Tc.phase{i}, Tc.acquisition{i}, Tc.(oc_check)(i), log(Tc.(oc_check)(i)));
    end
    med_others = median(T.(oc_check)(~strcmp(T.subject,subj_check) & strcmp(T.phase_type,ptype_check) ...
                         & isfinite(T.(oc_check)) & T.(oc_check)>0), 'omitnan');
    fprintf('\nFor comparison, median %s across all OTHER subjects in %s: %.4g (raw)\n', ...
        upper(oc_check), ptype_check, med_others);
    n_above = sum(Tc.(oc_check) > med_others);
    fprintf('%d of %d acquisitions for %s are above that median.\n', n_above, height(Tc), subj_check);
end

function lbl = local_xlabel(ptype)
    if strcmp(ptype,'test'), lbl = 'Test phase';
    else, lbl = sprintf('%s Level', local_capitalize(ptype));
    end
end
function s = local_capitalize(s)
    s(1) = upper(s(1));
end