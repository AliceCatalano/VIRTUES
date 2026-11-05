%% =====================================================================
%  SURG-TLX Repeated-Measures Analysis
%  Reads a wide-format CSV (one row per subject, blocks of columns
%  repeated per training level) and runs full statistical analysis.
% =====================================================================

clear; clc; close all;

%% ---------------- USER SETTINGS ----------------
filename    = 'surgtlx_data.csv';   % <-- change to your file name
subjectCol  = 'Subject ID';         % column name holding subject IDs
subscaleNames = {'Mental','Physical','Temporal','Complexity','Stress','Distractions'};
nSubscales  = numel(subscaleNames);
alpha       = 0.05;

%% ---------------- READ DATA ----------------
opts = detectImportOptions(filename, 'VariableNamingRule','preserve');
T = readtable(filename, opts);

varNames = T.Properties.VariableNames;

% Auto-detect number of levels & block structure based on repeated
% "MENTAL DEMAND" header occurrences
mentalIdx = find(contains(varNames, 'MENTAL DEMAND', 'IgnoreCase', true));
nLevels   = numel(mentalIdx);
if nLevels == 0
    error('Could not find "MENTAL DEMAND" columns — check column headers.');
end
metaCols     = mentalIdx(1) - 1;
colsPerBlock = round((width(T) - metaCols) / nLevels);

fprintf('Detected %d training levels, %d columns per block.\n', nLevels, colsPerBlock);

nSubjects = height(T);
subjID = string(T{:, subjectCol});

%% ---------------- RESHAPE INTO 3D ARRAY (Subject x Level x Subscale) ----------------
data = nan(nSubjects, nLevels, nSubscales);

for lvl = 1:nLevels
    startCol = metaCols + (lvl-1)*colsPerBlock + 1;
    numericCols = startCol : startCol + nSubscales - 1;
    data(:, lvl, :) = T{:, numericCols};
end

% Composite score per subject per level (mean of 6 subscales, 1-20 scale)
compositeScore = squeeze(mean(data, 3, 'omitnan'));
if nLevels == 1
    compositeScore = compositeScore'; % edge case fix for squeeze
end

%% ---------------- BUILD LONG-FORMAT TABLE (for export / inspection) ----------------
longTbl = table();
idx = 1;
for s = 1:nSubjects
    for lvl = 1:nLevels
        for sc = 1:nSubscales
            longTbl.Subject(idx,1)   = subjID(s);
            longTbl.Level(idx,1)     = lvl;
            longTbl.Subscale(idx,1)  = string(subscaleNames{sc});
            longTbl.Score(idx,1)     = data(s,lvl,sc);
            idx = idx+1;
        end
    end
end
writetable(longTbl, 'surgtlx_long_format.csv');
fprintf('Long-format data exported to surgtlx_long_format.csv\n');

%% ---------------- CHECK SAMPLE SIZE ----------------
completeRows = all(~isnan(compositeScore), 2);
nComplete = sum(completeRows);
fprintf('%d of %d subjects have complete data across all %d levels.\n', ...
    nComplete, nSubjects, nLevels);

if nComplete < 2
    warning(['Fewer than 2 complete subjects — inferential stats are not meaningful. ' ...
             'Only descriptive plots will be generated.']);
end

%% ---------------- STATISTICAL ANALYSIS: COMPOSITE SCORE ----------------
if nComplete >= 2
    fprintf('\n================ COMPOSITE SCORE ANALYSIS ================\n');
    resultsComposite = analyzeRepeatedMeasures(compositeScore(completeRows,:), 'Composite Score', alpha);
end

%% ---------------- STATISTICAL ANALYSIS: EACH SUBSCALE ----------------
subscaleResults = struct();
if nComplete >= 2
    for sc = 1:nSubscales
        fprintf('\n================ %s SUBSCALE ANALYSIS ================\n', upper(subscaleNames{sc}));
        subMat = squeeze(data(completeRows, :, sc));
        subscaleResults.(subscaleNames{sc}) = analyzeRepeatedMeasures(subMat, subscaleNames{sc}, alpha);
    end
end

%% ================== VISUALIZATION ==================

% 1. Composite score trend across levels (mean +/- SEM)
meanComposite = mean(compositeScore, 1, 'omitnan');
nPerLevel = sum(~isnan(compositeScore), 1);
semComposite = std(compositeScore, 0, 1, 'omitnan') ./ sqrt(nPerLevel);

figure('Name','Composite Workload Trend');
errorbar(1:nLevels, meanComposite, semComposite, '-o', ...
    'LineWidth', 1.5, 'MarkerFaceColor','b', 'CapSize',8);
xlabel('Training Level'); ylabel('Composite SURG-TLX Score (1-20)');
title('Workload Across Training Levels');
xlim([0.5 nLevels+0.5]); xticks(1:nLevels); grid on;

% 2. Subscale trends across levels
meanBySubscale = squeeze(mean(data, 1, 'omitnan')); % nLevels x nSubscales
if nLevels == 1, meanBySubscale = meanBySubscale'; end

figure('Name','Subscale Trends'); hold on;
colors = lines(nSubscales);
for sc = 1:nSubscales
    plot(1:nLevels, meanBySubscale(:,sc), '-o', 'Color', colors(sc,:), ...
        'LineWidth', 1.5, 'DisplayName', subscaleNames{sc});
end
xlabel('Training Level'); ylabel('Mean Score (1-20)');
title('SURG-TLX Subscale Scores Across Training Levels');
xticks(1:nLevels); legend('Location','bestoutside'); grid on; hold off;

% 3. Boxplots of composite score per level
figure('Name','Composite Score Boxplots');
boxplot(compositeScore, 'Labels', compose('Level %d',1:nLevels));
ylabel('Composite SURG-TLX Score');
title('Distribution of Composite Workload Scores by Training Level');

% 4. Radar chart: first vs last level subscale profile
firstLevelMean = squeeze(mean(data(:,1,:), 1, 'omitnan'));
lastLevelMean  = squeeze(mean(data(:,end,:), 1, 'omitnan'));

theta = linspace(0, 2*pi, nSubscales+1);
r1 = [firstLevelMean(:); firstLevelMean(1)];
r2 = [lastLevelMean(:);  lastLevelMean(1)];

figure('Name','Subscale Radar Profile');
polarplot(theta, r1, '-o', 'LineWidth', 1.5); hold on;
polarplot(theta, r2, '-o', 'LineWidth', 1.5);
thetaticks(rad2deg(theta(1:end-1)));
thetaticklabels(subscaleNames);
rlim([0 20]);
legend({'Level 1','Last Level'}, 'Location','best');
title('Subscale Profile: First vs Last Training Level');

fprintf('\nAnalysis complete. Figures generated, tables exported.\n');

%% =====================================================================
%  LOCAL FUNCTION: Repeated-measures analysis (auto parametric/non-param)
% =====================================================================
function results = analyzeRepeatedMeasures(dataMat, labelStr, alpha)
% dataMat: Subjects x Levels matrix (no NaNs)
% labelStr: name for display purposes
% alpha: significance threshold

    [nSubj, nLev] = size(dataMat);
    results = struct();

    % ---- Normality check (Lilliefors test) per level ----
    isNormal = true;
    for lvl = 1:nLev
        try
            [h, p] = lillietest(dataMat(:,lvl));
        catch
            h = 1; p = NaN; % fallback if sample too small
        end
        fprintf('  Level %d normality: h=%d, p=%.3f\n', lvl, h, p);
        if h == 1
            isNormal = false;
        end
    end

    if isNormal && nSubj >= 10
        % ---------------- PARAMETRIC: Repeated-measures ANOVA ----------------
        fprintf('  --> Data approx. normal: running repeated-measures ANOVA\n');

        varNames = compose('Level%d', 1:nLev);
        rmTbl = array2table(dataMat, 'VariableNames', varNames);
        within = table((1:nLev)', 'VariableNames', {'Level'});
        rm = fitrm(rmTbl, sprintf('%s-%s ~ 1', varNames{1}, varNames{end}), 'WithinDesign', within);

        ranovaTbl = ranova(rm);
        disp(ranovaTbl);

        % Partial eta squared
        SS_effect = ranovaTbl.SumSq(1);
        SS_error  = ranovaTbl.SumSq(2);
        partialEtaSq = SS_effect / (SS_effect + SS_error);
        fprintf('  Partial eta^2 = %.3f\n', partialEtaSq);

        % Post-hoc with Bonferroni correction
        postHoc = multcompare(rm, 'Level', 'ComparisonType', 'bonferroni');
        disp(postHoc);

        results.method = 'RM-ANOVA';
        results.omnibusTable = ranovaTbl;
        results.effectSize = partialEtaSq;
        results.postHoc = postHoc;

        writetable(postHoc, sprintf('posthoc_%s_ANOVA.csv', matlab.lang.makeValidName(labelStr)));

    else
        % ---------------- NON-PARAMETRIC: Friedman test ----------------
        fprintf('  --> Data non-normal or small N: running Friedman test\n');

        [pFriedman, tblFriedman, statsFriedman] = friedman(dataMat, 1, 'off');
        fprintf('  Friedman chi-sq = %.3f, p = %.4f\n', tblFriedman{2,5}, pFriedman);

        % Post-hoc pairwise Wilcoxon signed-rank with Bonferroni correction
        pairs = nchoosek(1:nLev, 2);
        nPairs = size(pairs,1);
        pVals = nan(nPairs,1);
        effectR = nan(nPairs,1);

        for i = 1:nPairs
            a = pairs(i,1); b = pairs(i,2);
            [p, ~, stats] = signrank(dataMat(:,a), dataMat(:,b));
            pVals(i) = p;
            if isfield(stats, 'zval')
                effectR(i) = abs(stats.zval) / sqrt(nSubj);
            end
        end
        pAdj = min(pVals * nPairs, 1); % Bonferroni correction

        postHoc = table(pairs(:,1), pairs(:,2), pVals, pAdj, effectR, ...
            'VariableNames', {'Level_A','Level_B','p_raw','p_bonferroni','effect_r'});
        disp(postHoc);

        results.method = 'Friedman';
        results.pOmnibus = pFriedman;
        results.chiSq = tblFriedman{2,5};
        results.postHoc = postHoc;

        writetable(postHoc, sprintf('posthoc_%s_Friedman.csv', matlab.lang.makeValidName(labelStr)));
    end

    % Significance flag for quick reference
    if isfield(results, 'pOmnibus')
        results.significant = results.pOmnibus < alpha;
    else
        results.significant = ranovaTbl.pValue(1) < alpha;
    end
end