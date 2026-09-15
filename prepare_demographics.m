function prepare_demographics(raw_csv_path, out_csv_path)
% PREPARE_DEMOGRAPHICS  One-time cleaning step: maps the raw LimeSurvey
% demographics export onto the column schema join_demographics.m expects
% (subject, age, gender, handedness, gaming_experience, robotic_experience)
% and writes the result to out_csv_path (default: cfg.data_root/demographics.csv,
% i.e. wherever join_demographics.m looks by default).
%
% Run this ONCE against the raw survey export. run_covariate_sensitivity_check.m
% and join_demographics.m consume the cleaned output, not the raw file.
%
% --- Mapping decisions, verified against the actual export (49 respondents) ---
%
% subject: raw values are inconsistently formatted ('S00h','S02n','16N',
% '21h','S43N', ...) -- optional leading S/s, 1-2 digit number, case-
% insensitive H/N suffix. Regex-normalized here to the pipeline's
% 'subject_sNNH'/'subject_sNNN' format (config.m's cfg.all_subjects),
% zero-padding the number to 2 digits. Every one of config.m's 47 analyzed
% subjects is present in this file under one formatting or another; the
% only extras are two respondents (s00H, s01H) not in cfg.all_subjects
% (presumably pilot/excluded). They are kept in the output rather than
% dropped here: join_demographics.m's left-join simply won't match them
% to any feature-table row, so leaving them is harmless and keeps the
% mismatch inspectable instead of silently hidden.
%
% gender <- "What is your sex (biological context)?" (Male/Female in this
% file -- named `gender` only because that's the column name
% join_demographics.m requires, not a claim that sex and gender were
% distinguished in the instrument).
%
% handedness: NOT a single item in this instrument -- it's the 10-item
% Edinburgh-Handedness-Inventory-style per-activity checklist (Writing,
% Drawing, Throwing an object, ...). Each item is scored on the standard
% EHI scale (Exclusively Left=-1, Mostly Left=-0.5, Both=0, Mostly
% Right=+0.5, Exclusively Right=+1) and averaged across all 10 into a
% laterality quotient LQ (-100..+100, EHI convention), then bucketed with
% the conventional +-40 cutoff into the categorical Left/Mixed/Right that
% join_demographics.m's required `handedness` column expects. The
% continuous score is also kept as `handedness_LQ` (not required by
% join_demographics.m's column check, but available if a continuous
% covariate is ever preferred over the 3-level bucket).
%
% gaming_experience <- "How often do you play video games?",
% robotic_experience <- "What is your level of experience with robots?"
% -- both ordinal Likert items, encoded here as ordinal integers 0..(k-1)
% in the order the response options were presented (join_demographics.m's
% header allows either numeric or categorical; integers work as either).
%
% Two related items exist in the raw file but are deliberately NOT folded
% into robotic_experience or included in the output: experience with the
% da Vinci system specifically, and experience with haptic interfaces
% specifically. Haptic-interface experience in particular is confounded
% with this study's own manipulation (the Haptic condition IS a haptic
% interface) -- collapsing it into a generic "robotic experience"
% covariate would misrepresent what was measured. If a sensitivity check
% against either of those specific items is ever wanted, add them as
% their own named covariate column rather than merging them in here.

    if nargin < 2 || isempty(out_csv_path)
        cfg = config();
        out_csv_path = fullfile(cfg.data_root, 'Demographics.csv');
    end

    opts = detectImportOptions(raw_csv_path, 'VariableNamingRule', 'preserve');
    Draw = readtable(raw_csv_path, opts);
    vn = Draw.Properties.VariableNames;

    col_subject = local_find_col(vn, 'Subject ID');
    col_age     = local_find_col(vn, 'your age');
    col_sex     = local_find_col(vn, 'your sex');
    col_games   = local_find_col(vn, 'play video games');
    col_robots  = local_find_col(vn, 'experience with robots');

    anchor_idx = find(contains(vn, 'fine motor precision'), 1);
    if isempty(anchor_idx)
        error('prepare_demographics: could not find the "fine motor precision" column used as the anchor for the 10 handedness items -- raw file format may have changed.');
    end
    hand_cols = vn(anchor_idx+1:end);
    if numel(hand_cols) ~= 10
        error('prepare_demographics: expected 10 handedness columns after "%s", found %d -- raw file format may have changed.', vn{anchor_idx}, numel(hand_cols));
    end

    n = height(Draw);

    % --- subject ---
    subject = strings(n, 1);
    for i = 1:n
        raw_id = char(strtrim(string(Draw.(col_subject)(i))));
        tok = regexp(raw_id, '^[Ss]?(\d{1,2})([HhNn])$', 'tokens', 'once');
        if isempty(tok)
            error('prepare_demographics: subject ID "%s" (row %d) does not match the expected [S]NN[HN] pattern.', raw_id, i);
        end
        subject(i) = sprintf('subject_s%02d%s', str2double(tok{1}), upper(tok{2}));
    end

    % --- age ---
    age = double(string(Draw.(col_age)));

    % --- gender ---
    gender = categorical(string(Draw.(col_sex)));

    % --- handedness: EHI-style scoring across the 10 activity items ---
    ehi_map = containers.Map( ...
        {'Exclusively Left', 'Mostly Left', 'Both', 'Mostly Right', 'Exclusively Right'}, ...
        {-1, -0.5, 0, 0.5, 1});
    item_scores = nan(n, numel(hand_cols));
    for j = 1:numel(hand_cols)
        vals = string(Draw.(hand_cols{j}));
        for i = 1:n
            key = char(strtrim(vals(i)));
            if ~isKey(ehi_map, key)
                error('prepare_demographics: unrecognized handedness response "%s" in column "%s", row %d.', key, hand_cols{j}, i);
            end
            item_scores(i, j) = ehi_map(key);
        end
    end
    handedness_LQ = 100 * mean(item_scores, 2);
    handedness = repmat(categorical({'Mixed'}), n, 1);
    handedness(handedness_LQ >= 40)  = categorical({'Right'});
    handedness(handedness_LQ <= -40) = categorical({'Left'});

    % --- gaming_experience / robotic_experience: ordinal, response order ---
    gaming_experience  = local_ordinal_code(string(Draw.(col_games)),  {'Never', 'Rarely', 'Occasionally', 'Frequently'});
    robotic_experience = local_ordinal_code(string(Draw.(col_robots)), {'No experience', 'Occasional user', 'Professional expertise'});

    D = table(subject, age, gender, handedness, gaming_experience, robotic_experience, handedness_LQ);
    writetable(D, out_csv_path);
    fprintf('prepare_demographics: wrote %d subjects to %s\n', height(D), out_csv_path);

    pipeline_subjects = config().all_subjects;
    missing = setdiff(pipeline_subjects, cellstr(D.subject));
    extra   = setdiff(cellstr(D.subject), pipeline_subjects);
    if ~isempty(missing)
        warning('prepare_demographics: %d pipeline subject(s) have no demographics row: %s', numel(missing), strjoin(missing, ', '));
    end
    if ~isempty(extra)
        fprintf('prepare_demographics: %d demographics row(s) are not among config().all_subjects (kept anyway, harmless): %s\n', numel(extra), strjoin(extra, ', '));
    end
end

function col = local_find_col(vn, needle)
    idx = find(contains(vn, needle), 1);
    if isempty(idx)
        error('prepare_demographics: could not find a column containing "%s" -- raw file format may have changed.', needle);
    end
    col = vn{idx};
end

function code = local_ordinal_code(responses, levels_in_order)
    responses = strtrim(responses);
    code = nan(numel(responses), 1);
    for k = 1:numel(levels_in_order)
        code(startsWith(responses, levels_in_order{k})) = k - 1;
    end
    if any(isnan(code))
        bad = unique(responses(isnan(code)));
        error('prepare_demographics: unrecognized ordinal response(s): %s', strjoin(cellstr(bad), '; '));
    end
end
