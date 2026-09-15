function T = join_demographics(T, cfg)
% JOIN_DEMOGRAPHICS  Left-join demographic covariates (SAP Section 6: age,
% gender, handedness, gaming experience, prior robotic/simulator exposure)
% onto any feature table T that has a 'subject' column.
%
% Expects cfg.demographics_file (default: fullfile(cfg.data_root,
% 'demographics.csv')) with one row per subject and these columns:
%   subject   - MUST match T.subject exactly (e.g. 'subject_s02N')
%   age       - years, numeric
%   gender    - categorical (e.g. 'M'/'F'/'Other') -- converted to
%               categorical here; fitlme/fitglme will dummy-code it
%   handedness - categorical (e.g. 'Right'/'Left')
%   gaming_experience   - numeric (e.g. hours/week, or an ordinal scale --
%                          whatever your actual instrument produced;
%                          adjust the column name/type below if different)
%   robotic_experience  - numeric or categorical (e.g. prior robotic/
%                          simulator hours, or a yes/no flag) -- same
%                          caveat as gaming_experience
%
% ADJUST THE COLUMN NAMES ABOVE to match your actual demographics file --
% these are placeholders based on the SAP's wording ("age, gender,
% handedness, video-gaming experience, and prior robotic or simulator
% exposure"), not a real file this pipeline has ever seen. No demographics
% file has been supplied to this pipeline before now; this function will
% error clearly, naming the missing file and expected path, rather than
% silently producing a table without covariates if the file isn't there.
%
% Per the SAP: "These variables are treated as covariates of no
% theoretical interest and will not be interpreted unless they
% substantially alter the primary effects" -- i.e. include them as
% additive fixed effects (see gsr_training_lmm.m's covariate_cols
% argument), not as effects to report on their own, and not with
% interactions unless you have a specific reason to test one.

    if ~isfield(cfg, 'demographics_file') || isempty(cfg.demographics_file)
        cfg.demographics_file = fullfile(cfg.data_root, 'demographics.csv');
    end
    if ~isfile(cfg.demographics_file)
        error(['join_demographics: %s not found. This pipeline has no demographics ' ...
            'data joined yet (SAP Section 6 gap, flagged since the training-phase models ' ...
            'were first built) -- point cfg.demographics_file at your actual file, and check ' ...
            'the column-name assumptions in this function''s header match it.'], ...
            cfg.demographics_file);
    end

    D = readtable(cfg.demographics_file);
    required = {'subject','age','gender','handedness','gaming_experience','robotic_experience'};
    missing_cols = setdiff(required, D.Properties.VariableNames);
    if ~isempty(missing_cols)
        error('join_demographics: %s is missing expected column(s): %s -- update this function''s column list to match your file.', ...
            cfg.demographics_file, strjoin(missing_cols, ', '));
    end

    if iscell(D.gender),      D.gender      = categorical(D.gender);      end
    if iscell(D.handedness),  D.handedness  = categorical(D.handedness);  end

    n_before = height(T);
    T = outerjoin(T, D, 'Keys', 'subject', 'MergeKeys', true, 'Type', 'left');
    if height(T) ~= n_before
        error('join_demographics: row count changed after join (%d -> %d) -- demographics.csv likely has duplicate subject rows.', ...
            n_before, height(T));
    end

    n_missing = sum(ismissing(T.age));
    if n_missing > 0
        subj_missing = unique(T.subject(ismissing(T.age)));
        warning('join_demographics: %d rows (%d subjects) have no demographics match: %s', ...
            n_missing, numel(subj_missing), strjoin(subj_missing, ', '));
    end
end
