%% Claude_run_eye_lmms.m
% Corrected counterpart of run_eye_lmms.m and run_eye_transfer_lmms.m for the gaze measures.
% Uses Claude_outputs/eye/eye_features_claude.mat (from Claude_eye_extract_features_v2.m) and the
% same random effects as Claude_robust_lmms.m. Reports each measure as originally computed and as
% corrected, side by side, plus the subject-level change-from-L1 test.
% Writes ONLY to <output_root>/Claude_outputs/eye.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','eye');
L = load(fullfile(out_dir,'eye_features_claude.mat'),'T'); T = L.T;
T.haptic = logical(T.haptic); T.haptic_num = double(T.haptic);
T.subject_cat = categorical(T.subject); T.level_cat = categorical(T.level);
T.subj_level = categorical(strcat(string(T.subject),'_',string(T.level)));
T.log_fix_dur = log(T.fixation_mean_dur);
T.log_fix_dur_orig = log(T.fixation_mean_dur_orig);
oc = {'saccade_rate','corrected'; 'saccade_rate_orig','original'; 'fixation_rate','corrected'; 'fixation_rate_orig','original'; ...
      'log_fix_dur','corrected'; 'log_fix_dur_orig','original'; 'gaze_entropy_fixed','corrected'; 'gaze_entropy_orig','original'};
rows = {}; rowsT = {}; rowsS = {}; rowsE = {};
for i = 1:size(oc,1)
    y = oc{i,1};
    D = T(strcmp(T.phase_type,'training') & isfinite(T.(y)),:);
    fe = sprintf('%s ~ haptic_num*level_cat + haptic_num*repetition',y);
    m = fitlme(D,[fe ' + (1+repetition|subject_cat) + (1|subj_level)'],'FitMethod','REML');
    [~,~,st] = fixedEffects(m,'DFMethod','satterthwaite');
    terms = [{'repetition:haptic_num'}, arrayfun(@(l) sprintf('level_cat_%d:haptic_num',l),2:5,'UniformOutput',false)];
    for t = 1:numel(terms)
        ix = local_find(st.Name,terms{t});
        rows(end+1,:) = {y,oc{i,2},terms{t},height(D),st.Estimate(ix),st.SE(ix),st.DF(ix),st.pValue(ix)}; %#ok<AGROW>
    end
    % Simple effects for the level terms, by group
    fe2 = fixedEffects(m); nm = st.Name; cv = m.CoefficientCovariance;
    for lv = 2:5
        c = zeros(numel(fe2),1); c(strcmp(nm,sprintf('level_cat_%d',lv))) = 1;
        rowsE(end+1,:) = {y,oc{i,2},lv,'NHF',c'*fe2,sqrt(c'*cv*c)}; %#ok<AGROW>
        c(local_find(nm,sprintf('level_cat_%d:haptic_num',lv))) = 1;
        rowsE(end+1,:) = {y,oc{i,2},lv,'HF',c'*fe2,sqrt(c'*cv*c)}; %#ok<AGROW>
    end
    % Subject-level Lk - L1
    u = unique(D.subject); M = nan(numel(u),5); isH = false(numel(u),1);
    for s = 1:numel(u)
        idx = strcmp(D.subject,u{s}); isH(s) = any(D.haptic(idx));
        for lv = 1:5, M(s,lv) = mean(D.(y)(idx & D.level==lv),'omitnan'); end
    end
    for lv = 2:5
        d = M(:,lv)-M(:,1);
        [~,p] = ttest2(d(isH),d(~isH),'Vartype','unequal');
        rowsS(end+1,:) = {y,oc{i,2},lv,sum(isfinite(d)&~isH),sum(isfinite(d)&isH),mean(d(isH),'omitnan')-mean(d(~isH),'omitnan'),p,ranksum(d(isH),d(~isH))}; %#ok<AGROW>
    end
    % Transfer
    for fam = {{'elastic','baseline','Baseline1','Baseline2'},{'peg','test','Test1','Test2'}}
        fm = fam{1};
        B = T(strcmp(T.phase_type,fm{2}) & ismember(T.phase,{fm{3},fm{4}}) & isfinite(T.(y)),:);
        B.phase_post = double(strcmp(B.phase,fm{4}));
        if strcmp(fm{1},'elastic')
            frm = sprintf('%s ~ phase_post*haptic_num + level_cat + (1+phase_post|subject_cat)',y);
        else
            frm = sprintf('%s ~ phase_post*haptic_num + (1|subject_cat)',y);
        end
        mT = fitlme(B,frm,'FitMethod','REML');
        [~,~,sT] = fixedEffects(mT,'DFMethod','satterthwaite');
        ix = local_find(sT.Name,'phase_post:haptic_num');
        rowsT(end+1,:) = {fm{1},y,oc{i,2},numel(unique(B.subject)),sT.Estimate(ix),sT.SE(ix),sT.DF(ix),sT.pValue(ix)}; %#ok<AGROW>
    end
    fprintf('%s done\n',y);
end
TR = cell2table(rows,'VariableNames',{'outcome','version','term','n_obs','beta','se','df','p'});
TT = cell2table(rowsT,'VariableNames',{'task','outcome','version','n_subj','beta','se','df','p'});
TS = cell2table(rowsS,'VariableNames',{'outcome','version','level','n_N','n_H','diff_H_minus_N','p_welch','p_rank'});
TE = cell2table(rowsE,'VariableNames',{'outcome','version','level','group','beta','se'});
% FDR across the corrected gaze family only
isc = strcmp(TR.version,'corrected') & ~strcmp(TR.term,'repetition:haptic_num');
TR.p_fdr = nan(height(TR),1); TR.p_fdr(isc) = local_bh(TR.p(isc));
isc2 = strcmp(TS.version,'corrected'); TS.p_fdr = nan(height(TS),1); TS.p_fdr(isc2) = local_bh(TS.p_welch(isc2));
writetable(TR,fullfile(out_dir,'eye_training_terms.csv'));
writetable(TT,fullfile(out_dir,'eye_transfer_terms.csv'));
writetable(TS,fullfile(out_dir,'eye_subject_level_change.csv'));
writetable(TE,fullfile(out_dir,'eye_simple_effects.csv'));
save(fullfile(out_dir,'eye_lmm_claude.mat'),'TR','TT','TS','TE');
fprintf('EYELMM_DONE\n');

function ix = local_find(names,name)
    want = sort(strsplit(name,':'));
    ix = find(cellfun(@(n) isequal(sort(strsplit(n,':')),want),names),1);
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
