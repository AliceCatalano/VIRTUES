%  A PRIORI POWER ANALYSIS – Haptic × Repetition LMM
%  Based on Statistical Analysis Plan (SAP) for da Vinci robotic motor-learning study.
%
%  Design (from SAP §1, §9):
%    • Between-subjects factor : Haptic group (HF vs NHF)
%    • Within-subjects factors : Repetition (learning trials)
%                                Level (task difficulty)
%    • Random effects          : per-subject intercept + slope
%    • Primary test            : Haptic × Repetition interaction
%    • Target power            : 80%   (SAP §9)
%    • Alpha                   : 0.05  (SAP §4.1)
%    • ICC                     : ~0.4  (SAP §9)
%
%  Strategy: Monte-Carlo simulation of the LMM for a range of total sample sizes, then interpolate to find the minimum N
%  that achieves ≥ 80% power.
%  Usage:
%    1. Set the "EDIT THESE" parameters in Section 1.
%    2. Optionally point 'data_file' to your preliminary CSV.
%    3. Run the script.  A power-curve figure is saved.


clear; clc; close all;
rng(42);   % reproducibility

%  SECTION 1 – DESIGN & EFFECT-SIZE PARAMETERS  (EDIT THESE)

% --- Experimental design ---
n_rep    = 10;   % repetitions per subject (Phase 3 trials)
n_levels = 5;    % difficulty levels

% --- Fixed-effect assumptions (standardised units) ---
%   Set these from your preliminary data or keep SAP defaults.
beta_0           = 22.5244;  %0;     % grand intercept
beta_haptic      = 0.3420; %0.20;  % main effect of group (HF vs NHF)
beta_rep         = 6.5520; %0.10;  % within-subject learning slope
beta_level       = -0.5361; %0.15;  % difficulty main effect
beta_interaction = 0.15; %0.30;  % KEY: Haptic × Repetition (primary test)

% --- Variance components (target ICC ≈ 0.4, SAP §9) ---
%   Total variance = between-subject + residual = 1 (standardised)
icc                  = 0.2523; %0.40;
sd_subj_intercept    = 9.4109; %sqrt(icc);   % between-subject SD  (≈ 0.632)
sd_subj_slope        = 0.2384; %0.20;        % SD of individual learning rates
cor_int_slope        = -1.0000; %0.20;        % random intercept-slope correlation
sd_residual          = 16.1988; %sqrt(1 - icc); % residual SD (≈ 0.775)

% --- Power analysis settings ---
alpha         = 0.05;
target_power  = 0.80;
nsim          = 500;   % simulations per N  (increase for smoother curve)

% Sample sizes to sweep (total N, split equally per group)
n_vec = 20:4:80;   % e.g. [20 24 28 … 80]

% --- Optional: load preliminary data to override betas ---
% If you have a CSV with columns [Subject, Haptic, Repetition, Level, Y]:
%   data_file = 'my_pilot_data.csv';
%   [beta_0, beta_haptic, beta_rep, beta_level, beta_interaction, ...
%    sd_subj_intercept, sd_subj_slope, cor_int_slope, sd_residual] = ...
%        estimate_params_from_data(data_file, n_rep, n_levels);
% (see helper function at bottom of this file)

%
%  SECTION 2 – RANDOM-EFFECT COVARIANCE MATRIX

Sigma_re = [sd_subj_intercept^2, ...
            cor_int_slope * sd_subj_intercept * sd_subj_slope; ...
            cor_int_slope * sd_subj_intercept * sd_subj_slope, ...
            sd_subj_slope^2];

%  SECTION 3 – POWER SIMULATION LOOP
fprintf('\n=== Haptic × Repetition Power Analysis ===\n');
fprintf('nsim = %d per sample size\n\n', nsim);
fprintf('%-12s %-10s\n', 'Total N', 'Power');
fprintf('%s\n', repmat('-', 1, 24));

power_vec = zeros(size(n_vec));

for ni = 1:numel(n_vec)

    n_subj = n_vec(ni);          % total participants
    n_half = n_subj / 2;         % per group (must be even)
    n_obs  = n_subj * n_rep * n_levels;  % total observations

    % Build design matrices (fixed across sims for this N)
    Subject    = repelem((1:n_subj)', n_rep * n_levels);
    Haptic_num = [zeros(n_half * n_rep * n_levels, 1); ...
                  ones( n_half * n_rep * n_levels, 1)];
    Repetition = repmat(repelem((1:n_rep)', n_levels), n_subj, 1);
    Level_num  = repmat((1:n_levels)', n_subj * n_rep, 1);

    sig_count = 0;

    for s = 1:nsim

        % --- Simulate random effects ---
        re = mvnrnd([0 0], Sigma_re, n_subj);
        u0 = re(:, 1);   % random intercepts
        u1 = re(:, 2);   % random slopes

        u0_exp = u0(Subject);
        u1_exp = u1(Subject);

        % --- Generate outcome ---
        Y = beta_0 ...
          + beta_haptic      .* Haptic_num ...
          + beta_rep         .* Repetition ...
          + beta_level       .* Level_num  ...
          + beta_interaction .* Haptic_num .* Repetition ...
          + u0_exp ...
          + u1_exp .* Repetition ...
          + normrnd(0, sd_residual, n_obs, 1);

        % --- Fit LMM (SAP §4.2 model) ---
        tbl = table(Subject, Haptic_num, Repetition, Level_num, Y, ...
            'VariableNames', {'Subject','Haptic','Repetition','Level','Y'});

        try
            lme = fitlme(tbl, ...
                'Y ~ Haptic * Repetition + Level + (1 + Repetition | Subject)', ...
                'FitMethod', 'REML');

            % --- Extract p-value for Haptic:Repetition interaction ---
            anova_tbl = anova(lme);
            row_idx   = strcmp(anova_tbl.Term, 'Haptic:Repetition');

            if any(row_idx)
                p_val = anova_tbl.pValue(row_idx);
                if p_val < alpha
                    sig_count = sig_count + 1;
                end
            end
        catch
            % Convergence failure: skip this sim
        end

    end % sim loop

    power_vec(ni) = sig_count / nsim;
    fprintf('%-12d %-10.3f\n', n_subj, power_vec(ni));

end

%  SECTION 4 – FIND MINIMUM N FOR TARGET POWER
% Interpolate smoothly
n_fine     = linspace(n_vec(1), n_vec(end), 1000);
power_fine = interp1(n_vec, power_vec, n_fine, 'pchip');
power_fine = max(0, min(1, power_fine));   % clamp to [0,1]

idx_target = find(power_fine >= target_power, 1, 'first');

fprintf('\n%s\n', repmat('=', 1, 40));
if ~isempty(idx_target)
    n_required = ceil(n_fine(idx_target));
    % Round up to nearest even number (equal groups)
    if mod(n_required, 2) ~= 0
        n_required = n_required + 1;
    end
    fprintf('Minimum total N for %.0f%% power : %d participants\n', ...
            target_power * 100, n_required);
    fprintf('  → %d per group (HF / NHF)\n', n_required / 2);
else
    fprintf('Target power not reached within N = %d. Increase n_vec range.\n', ...
            n_vec(end));
    n_required = NaN;
end
fprintf('%s\n\n', repmat('=', 1, 40));

%  SECTION 5 – POWER CURVE FIGURE
fig = figure('Color', 'w', 'Position', [100 100 800 500]);

% Simulated points
scatter(n_vec, power_vec * 100, 60, [0.2 0.4 0.8], 'filled', ...
    'DisplayName', 'Simulated power'); hold on;

% Smooth interpolated curve
plot(n_fine, power_fine * 100, 'Color', [0.2 0.4 0.8], ...
    'LineWidth', 2, 'DisplayName', 'Interpolated curve');

% Target power line
yline(target_power * 100, '--r', 'LineWidth', 1.5, ...
    'Label', sprintf('%.0f%% target', target_power * 100), ...
    'LabelVerticalAlignment', 'bottom', ...
    'DisplayName', 'Target power');

% Mark required N
if ~isempty(idx_target) && ~isnan(n_required)
    xline(n_required, ':k', 'LineWidth', 1.5, ...
        'Label', sprintf('N = %d', n_required), ...
        'LabelVerticalAlignment', 'top', ...
        'DisplayName', sprintf('Required N = %d', n_required));
    scatter(n_required, target_power * 100, 120, 'r', 'filled', ...
        'HandleVisibility', 'off');
end

xlabel('Total Sample Size (N)', 'FontSize', 13);
ylabel('Estimated Power (%)', 'FontSize', 13);
title({'Power Analysis: Haptic \times Repetition Interaction (LMM)', ...
       sprintf('\\beta_{interaction} = %.2f,  ICC = %.2f,  \\alpha = %.2f', ...
               beta_interaction, icc, alpha)}, 'FontSize', 13);
legend('Location', 'southeast', 'FontSize', 11);
ylim([0 105]);
xlim([n_vec(1) - 2, n_vec(end) + 2]);
grid on; box on;

%saveas(fig, 'power_curve_haptic.png');
%fprintf('Power curve saved to: power_curve_haptic.png\n');

%  HELPER FUNCTION – estimate params from your pilot CSV


function [b0, b_h, b_r, b_l, b_int, sd_u0, sd_u1, cor_u, sd_e] = ...
         estimate_params_from_data(csv_file, n_rep, n_levels) %#ok<DEFNU>
%ESTIMATE_PARAMS_FROM_DATA  Fit LMM to pilot data and return parameters.
%
%  CSV must have columns: Subject, Haptic (0/1), Repetition, Level, Y
%  (one row per observation).
%
%  Standardise Y before passing in for interpretable effect sizes.

    tbl = readtable(csv_file);

    lme = fitlme(tbl, ...
        'Y ~ Haptic * Repetition + Level + (1 + Repetition | Subject)', ...
        'FitMethod', 'REML');

    fe   = fixedEffects(lme);
    b0   = fe(1);
    b_h  = fe(2);
    b_r  = fe(3);
    b_l  = fe(4);
    b_int = fe(end);  % Haptic:Repetition

    % Random-effect covariance
    [~, ~, re_stats] = randomEffects(lme);
    psi = covarianceParameters(lme);
    sd_u0 = sqrt(psi{1}(1,1));
    sd_u1 = sqrt(psi{1}(2,2));
    cor_u = psi{1}(1,2) / (sd_u0 * sd_u1);
    sd_e  = lme.MSE^0.5;

    fprintf('\n--- Parameters estimated from pilot data (%s) ---\n', csv_file);
    fprintf('beta_0           = %.4f\n', b0);
    fprintf('beta_haptic      = %.4f\n', b_h);
    fprintf('beta_rep         = %.4f\n', b_r);
    fprintf('beta_level       = %.4f\n', b_l);
    fprintf('beta_interaction = %.4f\n', b_int);
    fprintf('sd_subj_intercept= %.4f\n', sd_u0);
    fprintf('sd_subj_slope    = %.4f\n', sd_u1);
    fprintf('cor_int_slope    = %.4f\n', cor_u);
    fprintf('sd_residual      = %.4f\n', sd_e);
end