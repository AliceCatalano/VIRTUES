%% claude_pooled_questions_01_extract.m
% Per-trial movement, vibration and force-direction measures for each tool, phases Baseline1/2, Test1/2 and training.
% See claude_pooled_questions_plan.md. Writes ONLY to <output_root>/Claude_outputs/pooled_questions.
clear; clc; cfg = config();
out = fullfile(cfg.output_root,'Claude_outputs','pooled_questions'); if ~exist(out,'dir'), mkdir(out); end
C = load_ati_cal(cfg.force_cal_path); phases = [cfg.baseline_phases cfg.training_levels cfg.test_phases]; rows = {};
for si = 1:numel(cfg.all_subjects)
    s = cfg.all_subjects{si};
    for p = 1:numel(phases)
        ph = phases{p}; tr = ismember(ph,cfg.training_levels); bl = ismember(ph,cfg.baseline_phases);
        if tr, acqs = arrayfun(@(k) sprintf('rep_%02d',k),1:10,'UniformOutput',false); elseif bl, acqs = arrayfun(@(k) sprintf('Level%d',k),1:5,'UniformOutput',false); else, acqs = {'main'}; end
        for a = 1:numel(acqs)
            acq = acqs{a}; if tr||bl, d = fullfile(cfg.data_root,s,ph,acq); if ~isfolder(d)&&isfolder([d '_R']), d = [d '_R']; end; else, d = fullfile(cfg.data_root,s,ph); end
            if ~isfile(fullfile(d,'events.mat')), continue; end
            try
                [t0,t1] = safe_trial_window(fullfile(d,'events.mat')); if isnan(t0)||isnan(t1)||t1-t0<5, continue; end
                lvl = NaN; rep = NaN; if tr, lvl = str2double(ph(end)); rep = a; elseif bl, lvl = a; end
                v = local_accel(fullfile(d,'accel.mat'),t0,t1,cfg); f = local_force(fullfile(d,'force.mat'),t0,t1,C);
                rows(end+1,:) = [{s,ph,acq,lvl,rep,t1-t0},num2cell(v),num2cell(f)]; %#ok<AGROW>
            catch ME
                fprintf('skip %s %s %s: %s\n',s,ph,acq,ME.message);
            end
        end
    end
    fprintf('%s done\n',s);
end
T = cell2table(rows,'VariableNames',{'subject','phase','acquisition','level','repetition','window_s','move_L','move_R','vib_L','vib_R','env_corr','one_hand_share','covered_a','fz_share','fz_rate','lat_rate','fz_peak','fz_mean','covered_f'});
writetable(T,fullfile(out,'trial_measures.csv')); save(fullfile(out,'trial_measures.mat'),'T');
fprintf('POOLED_EXTRACT_DONE %d rows\n',height(T));

function v = local_accel(p,a,b,cfg)
    v = nan(1,7); if ~isfile(p), return; end
    L = load(p,'ACCEL'); t = L.ACCEL.time_rel(:); fs = L.ACCEL.fs_nominal; w = t>=a&t<=b; if sum(w)<fs*5, return; end
    X = double(L.ACCEL.data(w,:))*cfg.accel_sensitivity_ms2_per_V; cover = (sum(w)/fs);
    [b1,a1] = butter(3,[.5 5]/(fs/2),'bandpass'); [b2,a2] = butter(4,[80 1000]/(fs/2),'bandpass');
    Xm = filtfilt(b1,a1,X-mean(X,1)); Xv = filtfilt(b2,a2,X-mean(X,1));
    mL = sqrt(sum(Xm(:,1:3).^2,2)); mR = sqrt(sum(Xm(:,4:6).^2,2));
    vL = sum(Xv(:,1:3).^2,2); vR = sum(Xv(:,4:6).^2,2);
    k = round(fs*.25); eL = movmean(mL,k); eR = movmean(mR,k); step = round(fs/20); eL = eL(1:step:end); eR = eR(1:step:end);
    r = corr(eL,eR); share = mean(abs(log(max(eL,1e-9)./max(eR,1e-9)))>log(3));
    v = [sqrt(mean(mL.^2)) sqrt(mean(mR.^2)) mean(vL) mean(vR) r share cover];
end
function f = local_force(p,a,b,C)
    f = nan(1,6); if ~isfile(p), return; end
    L = load(p,'FORCE'); t = L.FORCE.time_rel(:); w = t>=a&t<=b; if sum(w)<100, return; end
    pre = t>=(a-1)&t<a; if sum(pre)<3, pre = t<(t(1)+1); end
    bias = mean(L.FORCE.data(pre,:),1,'omitnan'); F = (C*(double(L.FORCE.data(w,:))-bias)')';
    fx = F(:,1); fy = F(:,2); fz = F(:,3); cover = t(find(w,1,'last'))-t(find(w,1)); mins = cover/60; dtS = cover/sum(w);
    ez = sum(fz.^2)*dtS; el = sum(fx.^2+fy.^2)*dtS;
    f = [ez/(ez+el) ez/mins el/mins max(abs(fz)) mean(fz) cover];
end
