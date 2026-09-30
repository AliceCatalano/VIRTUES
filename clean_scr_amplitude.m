%% scr_amplitude_clean.m
% Defines and applies the correct cleaning strategy for scr_amp_local_bc:
% 1. Hard bounds only: remove < -0.5 and > 5 (10 values, 0.11%)
% 2. No MAD-based removal
% 3. Log-transform for statistical analysis: log(x + offset)
%    where offset shifts the distribution to be strictly positive
% 4. subject_s33H flagged for sensitivity analysis but kept

function [x_clean, x_log, excluded_mask] = clean_scr_amplitude(x)
    LOWER_BOUND = -0.5;   % artefactual pre-collision elevation
    UPPER_BOUND = 5.0;    % physiologically implausible given normalisation scale

    excluded_mask = x < LOWER_BOUND | x > UPPER_BOUND;
    x_clean = x;
    x_clean(excluded_mask) = NaN;

    % log-transform: shift so minimum clean value maps to a small positive number
    % use x + |min(x_clean)| + 0.01 to preserve sign information while enabling log
    % this is the standard approach for zero-bounded responses with negatives
    % [Boucsein 2012; Bach 2009]
    min_clean = min(x_clean(isfinite(x_clean)));
    offset    = abs(min_clean) + 0.01;
    x_log     = log(x_clean + offset);
    fprintf('SCR clean: %d excluded (%.2f%%)  offset=%.4f for log-transform\n', ...
        sum(excluded_mask), 100*mean(excluded_mask), offset);
end