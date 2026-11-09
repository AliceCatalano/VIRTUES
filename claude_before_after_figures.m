%% claude_before_after_figures.m
% Before and after comparison figures, for showing what changed and what did not.
% Reads saved results, feature tables and one raw gaze trial. Changes no existing file.
% Writes ONLY to <output_root>/Claude_outputs/before_after.
% Grey = original analysis. Blue = corrected analysis. All titles with numbers are filled in from the data.

clear; clc; close all; cfg = config(); rng(20261106);
r = cfg.output_root; c = fullfile(r,'Claude_outputs'); out = fullfile(c,'before_after'); if ~exist(out,'dir'), mkdir(out); end
GREY = [122 127 135]/255; BLUE = [31 111 209]/255; CN = [64 96 179]/255; CH = [139 82 168]/255; INK = [.15 .15 .15]; MUTE = [.45 .45 .45]; WARN = [194 84 45]/255;
set(groot,'defaultAxesFontSize',11,'defaultAxesTickDir','out','defaultAxesBox','off','defaultAxesXColor',MUTE,'defaultAxesYColor',MUTE,'defaultAxesTitleFontWeight','bold','defaultTextColor',INK,'defaultFigureColor','w');
ROB = load(fullfile(c,'robust_lmm','robust_lmm_results.mat')); TR = ROB.TR; TT = ROB.TT;
eda = load(fullfile(r,'training_lmm_results.mat')); eye_ = load(fullfile(r,'eye_lmm_results.mat')); perf = load(fullfile(r,'performance_lmm_results.mat'));
E = load(fullfile(r,'eda_features_v2.mat'),'T'); E = E.T; Y = load(fullfile(r,'eye_features_v2.mat'),'T'); Y = Y.T;
P = load(fullfile(r,'perf_features.mat'),'T'); P = P.T; F = load(fullfile(r,'force_vibration_features_clean.mat'),'T'); F = F.T;
V = load(fullfile(c,'eye','eye_features_claude.mat'),'T'); V = V.T;
F.tssf(F.tssf<=0)=NaN; F.tssv(F.tssv<=0)=NaN; F.tssf_log=log(F.tssf); F.tssv_log=log(F.tssv);
QC = readtable(fullfile(c,'test3_collision','detection_qc.csv'),'TextType','string');

%% F01. Same data, same code: the original results reproduce
fig = figure('Position',[50 50 1150 470]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
nexttile; hold on; zS = []; zR = []; red = false(0,1);
for S = {eda,eye_,perf}
    s = S{1}; for i = 1:numel(s.lh_p)
        k = strcmp(TR.outcome,s.lh_outcome{i})&strcmp(TR.term,s.lh_term{i}); if ~any(k), continue; end
        zS(end+1,1) = s.lh_beta(i)/s.lh_se(i); zR(end+1,1) = TR.beta_orig(k)/TR.se_orig(k); %#ok<AGROW>
        ix = find(strcmp(s.outcomes,s.lh_outcome{i}),1); red(end+1,1) = contains(string(s.results{ix}.re_structure),'reduced'); %#ok<AGROW>
    end
end
lim = [min([zS;zR])-.5 max([zS;zR])+.5]; plot(lim,lim,'-','Color',[.8 .8 .8],'LineWidth',1.5,'HandleVisibility','off');
scatter(zS(~red),zR(~red),55,GREY,'filled','DisplayName','Same model form'); scatter(zS(red),zR(red),55,GREY,'DisplayName','Saved run used reduced random effects');
xlabel('Saved result (\beta / SE)'); ylabel('Re-fitted with original formula (\beta / SE)'); axis square; xlim(lim); ylim(lim); legend('Location','northwest','Box','off');
title(sprintf('%d Haptic \\times Level terms reproduce',numel(zS))); grid on;
nexttile; hold on; q = QC(QC.phase=="Test2",:); mx = max(q.n_saved)+3; plot([0 mx],[0 mx],'-','Color',[.8 .8 .8],'LineWidth',1.5);
scatter(q.n_saved,q.n,55,GREY,'filled'); xlabel('Saved collisions per subject, Test2'); ylabel('Re-detected collisions per subject'); axis square; xlim([0 mx]); ylim([0 mx]); grid on;
title(sprintf('%d of %d collisions matched',sum(q.n_matched),sum(q.n_saved)));
local_save(fig,out,'F01_original_results_reproduce','Same data, original model formula: the saved results reproduce');

%% F02. Estimates stay, uncertainty grows
eff = {'Tonic SCL (\muS), elastic transfer',TT,'elastic','scl_mean'; 'SCR frequency (/min), elastic transfer',TT,'elastic','scr_freq'; 'Completion time (s), elastic transfer',TT,'elastic','duration_s'; ...
       'Tonic SCL (\muS), H\timesL3',TR,'level_cat_3:haptic_num','scl_mean_bc'; 'Tonic SCL (\muS), H\timesL5',TR,'level_cat_5:haptic_num','scl_mean_bc'; 'SCR frequency (/min), H\timesL5',TR,'level_cat_5:haptic_num','scr_freq'; ...
       'Gaze entropy (bits), H\timesL4',TR,'level_cat_4:haptic_num','gaze_entropy'; 'Gaze entropy (bits), H\timesL5',TR,'level_cat_5:haptic_num','gaze_entropy'; 'Completion time (s), H\timesL4',TR,'level_cat_4:haptic_num','duration_s'};
fig = figure('Position',[50 50 1250 680]); tiledlayout(3,3,'TileSpacing','compact','Padding','compact');
for i = 1:size(eff,1)
    Tt = eff{i,2}; if istable(Tt)&&ismember('task',Tt.Properties.VariableNames), x = Tt(strcmp(Tt.task,eff{i,3})&strcmp(Tt.outcome,eff{i,4}),:); else, x = Tt(strcmp(Tt.term,eff{i,3})&strcmp(Tt.outcome,eff{i,4}),:); end
    nexttile; hold on; ci0 = x.beta_orig+[-1.96 1.96]*x.se_orig; ci1 = x.beta_robust+[-1.96 1.96]*x.se_robust;
    plot(ci0,[2 2],'-','Color',GREY,'LineWidth',3); plot(x.beta_orig,2,'o','MarkerFaceColor',GREY,'MarkerEdgeColor','w','MarkerSize',10);
    plot(ci1,[1 1],'-','Color',BLUE,'LineWidth',3); plot(x.beta_robust,1,'o','MarkerFaceColor',BLUE,'MarkerEdgeColor','w','MarkerSize',10);
    xline(0,'-','Color',INK,'LineWidth',1); ylim([.3 2.7]); yticks([1 2]); yticklabels({'Corrected','Original'}); xw = max(abs([ci0 ci1]))*1.1; xlim([-xw xw]); grid on; ax = gca; ax.YGrid = 'off';
    title(eff{i,1},'FontSize',11,'FontWeight','normal');
end
local_save(fig,out,'F02_estimates_stay_uncertainty_grows','The effect estimates stay close. The main change is the uncertainty around them (95% CI).');

%% F03. p values before and after
items = {'Elastic SCL',TT,'elastic','scl_mean';'Elastic SCR frequency',TT,'elastic','scr_freq';'SCL H\timesL3',TR,'level_cat_3:haptic_num','scl_mean_bc';'SCL H\timesL5',TR,'level_cat_5:haptic_num','scl_mean_bc';'SCR frequency H\timesL5',TR,'level_cat_5:haptic_num','scr_freq'; ...
         'Entropy H\timesL4',TR,'level_cat_4:haptic_num','gaze_entropy';'Entropy H\timesL5',TR,'level_cat_5:haptic_num','gaze_entropy';'Collision pupil H\timesL2',TR,'level_cat_2:haptic_num','collision_pupil_response_mean'; ...
         'Time H\timesRepetition',TR,'repetition:haptic_num','duration_s';'Collisions H\timesRepetition',TR,'repetition:haptic_num','n_collisions';'Time H\timesL4',TR,'level_cat_4:haptic_num','duration_s';'Elastic time',TT,'elastic','duration_s';'Elastic collisions',TT,'elastic','n_collisions'};
n = size(items,1); p0 = nan(n,1); p1 = p0;
for i = 1:n
    Tt = items{i,2}; if ismember('task',Tt.Properties.VariableNames), x = Tt(strcmp(Tt.task,items{i,3})&strcmp(Tt.outcome,items{i,4}),:); else, x = Tt(strcmp(Tt.term,items{i,3})&strcmp(Tt.outcome,items{i,4}),:); end
    p0(i) = x.p_fdr_orig; p1(i) = x.p_fdr_robust;
end
fig = figure('Position',[50 50 900 560]); hold on; ypos = n:-1:1;
for i = 1:n, plot(-log10([p0(i) p1(i)]),ypos([i i]),'-','Color',[.82 .82 .82],'LineWidth',2.5,'HandleVisibility','off'); end
scatter(-log10(p0),ypos,80,GREY,'filled','DisplayName','Original'); scatter(-log10(p1),ypos,80,BLUE,'filled','DisplayName','Corrected');
xline(-log10(.05),'--','Color',INK,'LineWidth',1,'Label','p_{FDR} = .05','LabelHorizontalAlignment','right','HandleVisibility','off');
yticks(1:n); yticklabels(flip(items(:,1))); xlabel('Strength of evidence, -log_{10}(p_{FDR})'); legend('Location','southeast','Box','off'); grid on; ax = gca; ax.YGrid = 'off'; ylim([.3 n+.7]);
local_save(fig,out,'F03_evidence_before_after',sprintf('%d of the listed effects passed FDR before, %d pass after',sum(p0<.05),sum(p1<.05)));

%% F04. Why: 47 people, not 420 observations
fig = figure('Position',[50 50 1500 500]); tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
[dS,hS] = local_change(E,'scl_mean','Baseline1','Baseline2');
nexttile; hold on; jit = @(k) (rand(k,1)-.5)*.35;
scatter(1+jit(sum(~hS)),dS(~hS),45,CN,'filled','MarkerFaceAlpha',.7); scatter(2+jit(sum(hS)),dS(hS),45,CH,'filled','MarkerFaceAlpha',.7);
plot([.72 1.28],mean(dS(~hS),'omitnan')*[1 1],'-','Color',INK,'LineWidth',2.5); plot([1.72 2.28],mean(dS(hS),'omitnan')*[1 1],'-','Color',INK,'LineWidth',2.5); yline(0,'-','Color',[.7 .7 .7]);
xticks([1 2]); xticklabels({'NHF','HF'}); xlim([.4 2.6]); ylabel('Each person''s SCL change, BL1 to BL2 (\muS)'); title('People differ a lot in how they change');
x = TT(strcmp(TT.task,'elastic')&strcmp(TT.outcome,'scl_mean'),:); a = dS(~hS&isfinite(dS)); b = dS(hS&isfinite(dS)); dd = mean(b)-mean(a); se = sqrt(var(a)/numel(a)+var(b)/numel(b)); df = se^4/((var(a)/numel(a))^2/(numel(a)-1)+(var(b)/numel(b))^2/(numel(b)-1));
nexttile; hold on; rowsY = [3 2 1]; vals = {x.beta_orig,x.se_orig*1.96,GREY,sprintf('Original (1 | subject), df = %d',x.n_obs-8); x.beta_robust,x.se_robust*1.96,BLUE,sprintf('Corrected (1 + phase | subject), df = %.0f',x.df_robust); dd,se*tinv(.975,df),INK,sprintf('t-test on people, df = %.0f',df)};
for i = 1:3, plot(vals{i,1}+[-1 1]*vals{i,2},rowsY([i i]),'-','Color',vals{i,3},'LineWidth',3); plot(vals{i,1},rowsY(i),'o','MarkerFaceColor',vals{i,3},'MarkerEdgeColor','w','MarkerSize',11); end
xline(0,'-','Color',INK); yticks([1 2 3]); yticklabels(flip(vals(:,4))); ylim([.3 3.7]); xlabel('HF minus NHF, change in SCL (\muS), 95% CI'); title('Corrected model matches the direct test'); grid on; ax = gca; ax.YGrid = 'off';
oc = {'scl_mean',E;'scr_freq',E;'scr_mean_amp_bc',E;'pupil_mean_norm',Y;'gaze_entropy',Y;'fixation_rate',Y;'fixation_mean_dur',Y;'duration_s',P;'n_collisions',P;'tssf_log',F;'tssv_log',F};
ps = nan(size(oc,1),3);
for i = 1:size(oc,1)
    [d2,h2] = local_change(oc{i,2},oc{i,1},'Baseline1','Baseline2'); a = d2(~h2&isfinite(d2)); b = d2(h2&isfinite(d2)); [~,ps(i,1)] = ttest2(b,a,'Vartype','unequal');
    k = strcmp(TT.task,'elastic')&strcmp(TT.outcome,oc{i,1}); ps(i,2) = TT.p_orig(k); ps(i,3) = TT.p_robust(k);
end
nexttile; hold on; mx = max(-log10(ps(:)))*1.08; plot([0 mx],[0 mx],'-','Color',[.8 .8 .8],'LineWidth',1.5,'HandleVisibility','off');
scatter(-log10(ps(:,1)),-log10(ps(:,2)),60,GREY,'filled','DisplayName','Original model'); scatter(-log10(ps(:,1)),-log10(ps(:,3)),60,BLUE,'filled','DisplayName','Corrected model');
xlabel('-log_{10} p, direct test on people'); ylabel('-log_{10} p, mixed model'); xlim([0 mx]); ylim([0 mx]); legend('Location','southeast','Box','off'); grid on; title(sprintf('Across %d elastic-task outcomes',size(oc,1)));
local_save(fig,out,'F04_why_people_not_observations','Why the p-values changed: each person has one pre-to-post change, and people differ');

%% F05. Duplicated gaze samples
fig = figure('Position',[50 50 1300 800]); tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
for k = 1:2
    sb = {'subject_s07N','subject_s30N'}; d = fullfile(cfg.data_root,sb{k},'level_L1','rep_05'); L = load(fullfile(d,'eye.mat'),'EYE'); e = L.EYE; [t,o] = sort(e.time_rel(:)); D = e.data(o,:); x_ = D(:,strcmp(e.channel_names,'x')); [a0,~] = safe_trial_window(fullfile(d,'events.mat'));
    i0 = find(t>=a0+5,1); ix = i0:i0+39; nexttile; hold on; stairs((t(ix)-t(i0))*1000,x_(ix),'-','Color',[.8 .8 .8]); plot((t(ix)-t(i0))*1000,x_(ix),'o','MarkerFaceColor',local_pick(k,WARN,GREY),'MarkerEdgeColor','w','MarkerSize',8);
    xlabel('Time (ms)'); ylabel('Gaze x (px)'); grid on; dupF = mean(diff(x_)==0&diff(D(:,strcmp(e.channel_names,'y')))==0);
    title(sprintf('%s, raw samples: %.0f%% are exact repeats',strrep(sb{k}(9:end),'_',' '),100*dupF));
end
u = unique(string(V.subject)); X = V(strcmp(V.phase_type,'training'),:); sx = string(X.subject); M = nan(numel(u),5);
for i = 1:numel(u), j = sx==u(i); M(i,:) = [median(X.saccade_rate_orig(j),'omitnan') median(X.saccade_rate(j),'omitnan') median(X.fixation_rate_orig(j),'omitnan') median(X.fixation_rate(j),'omitnan') mean(X.dup_frac(j),'omitnan')]; end
af = M(:,5)>.1;
nexttile; hold on; local_ba(M(:,1),M(:,2),af,WARN,GREY,BLUE); set(gca,'YScale','log'); ylabel('Saccades per min, subject median (log; 0 drawn at 0.5)'); title(sprintf('Saccade rate: affected %.0f vs others %.0f, then %.0f vs %.0f',median(M(af,1)),median(M(~af,1)),median(M(af,2)),median(M(~af,2))));
nexttile; hold on; local_ba(M(:,3),M(:,4),af,WARN,GREY,BLUE); ylabel('Fixations per min, subject median'); title(sprintf('Fixation rate: affected %.0f vs others %.0f, then %.0f vs %.0f',median(M(af,3)),median(M(~af,3)),median(M(af,4)),median(M(~af,4))));
local_save(fig,out,'F05_duplicate_gaze_samples',sprintf('%d subjects have every gaze sample logged twice, which broke saccade and fixation detection',sum(af)));

%% F06. Fixation "reversal"
se = local_model(eye_,'fixation_rate').simple_effects; [mN0,sN0,mH0,sH0] = local_simple(se); [mN1,sN1,mH1,sH1] = local_levels(V,'fixation_rate');
fig = figure('Position',[50 50 1150 450]); tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile; local_lines(mN0,sN0,mH0,sH0,CN,CH); title('Before: broken detector and original model'); ylabel('Fixations per min, change from L1'); ylim0 = ylim;
nexttile; local_lines(mN1,sN1,mH1,sH1,CN,CH); title('After: corrected detector, subject-level CI'); yl1 = ylim;
yy = [min(ylim0(1),yl1(1)) max(ylim0(2),yl1(2))]; for ax = tl.Children', if isa(ax,'matlab.graphics.axis.Axes'), ax.YLim = yy; end; end
local_save(fig,out,'F06_fixation_reversal','The fixation "reversal" disappears: fixation rate rises in both groups');

%% F07. s16N
CI = load(fullfile(r,'collision_impact_features.mat'),'T_impact'); CI = CI.T_impact; Ct = CI(strcmp(CI.phase_type,'training'),:);
[g,us] = findgroups(string(Ct.subject)); cnt = splitapply(@numel,Ct.collision_idx,g); [cs,o] = sort(cnt,'descend'); us = us(o);
fig = figure('Position',[50 50 1300 430]); tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
nexttile; hold on; b_ = bar(cs,'FaceColor','flat','EdgeColor','none','BarWidth',.8); b_.CData = repmat([.72 .74 .77],numel(cs),1); b_.CData(us=="subject_s16N",:) = WARN; xlabel('Subjects, sorted'); ylabel('Training collisions detected'); xlim([0 numel(cs)+1]);
sh = cnt(string(splitapply(@(a) a(1),string(Ct.subject),g))=="subject_s16N")/sum(Ct.haptic==0&true); text(2.5,cs(1)*.93,sprintf('s16N: %d, %.0f%% of all NHF collisions',cs(1),100*sh),'FontSize',11); title('One subject dominates the NHF group');
for k = 1:2
    Dd = Ct(isfinite(Ct.peak_accel_g_nidaq)&Ct.peak_accel_g_nidaq>0,:); if k==2, Dd = Dd(~strcmp(Dd.subject,'subject_s16N'),:); end
    aN = Dd.peak_accel_g_nidaq(~Dd.haptic); aH = Dd.peak_accel_g_nidaq(Dd.haptic); [~,pk] = kstest2(aN,aH);
    nexttile; hold on; [fN,xN] = ecdf(aN); [fH,xH] = ecdf(aH); plot(xN,fN,'-','Color',CN,'LineWidth',2,'DisplayName',sprintf('NHF, median %.2f g',median(aN))); plot(xH,fH,'-','Color',CH,'LineWidth',2,'DisplayName',sprintf('HF, median %.2f g',median(aH)));
    set(gca,'XScale','log'); xlim([.02 10]); xlabel('Peak impact (g, log)'); ylabel('Share of collisions'); legend('Location','northwest','Box','off'); grid on;
    if k==1, title(sprintf('With s16N: KS p = %.1e',pk)); else, title(sprintf('Without s16N: KS p = %.2f',pk)); end
end
local_save(fig,out,'F07_s16N_artifact','The "different impact intensity" finding came entirely from one artifact subject');

%% F08. Collisions are not independent
TL = readtable(fullfile(c,'collision_coupling','collision_group_by_level.csv'),'TextType','string');
Ec = load(fullfile(r,'eda_features_v2.mat'),'T_coll'); Ec = Ec.T_coll; J = innerjoin(Ct,Ec(strcmp(Ec.phase_type,'training'),:),'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'scr_amp_local_bc'});
J = J(isfinite(J.scr_amp_local_bc)&J.scr_amp_local_bc>=-.5&J.scr_amp_local_bc<=5&isfinite(J.peak_accel_g_nidaq)&J.peak_accel_g_nidaq>0&~strcmp(J.subject,'subject_s16N'),:); J.y = log(J.scr_amp_local_bc+abs(min(J.scr_amp_local_bc))+.01);
L2 = J(J.level==2,:); [g,uu] = findgroups(string(L2.subject)); my = splitapply(@mean,L2.y,g); nc = splitapply(@numel,L2.y,g); hh = endsWith(uu,'H');
fig = figure('Position',[50 50 1250 470]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
nexttile; hold on; scatter(1+(rand(sum(~hh),1)-.5)*.35,my(~hh),nc(~hh)*1.2+15,CN,'filled','MarkerFaceAlpha',.6); scatter(2+(rand(sum(hh),1)-.5)*.35,my(hh),nc(hh)*1.2+15,CH,'filled','MarkerFaceAlpha',.6);
plot([.72 1.28],mean(my(~hh))*[1 1],'-','Color',INK,'LineWidth',2.5); plot([1.72 2.28],mean(my(hh))*[1 1],'-','Color',INK,'LineWidth',2.5); xticks([1 2]); xticklabels({'NHF','HF'}); xlim([.4 2.6]); ylabel('Subject mean collision response, log SCR, L2');
x2 = TL(TL.signal=="EDA"&TL.s16N_excluded==1&TL.level==2,:); title(sprintf('L2: %d collisions, but %d people. p = %.0e by collision, p = %.2f by person',height(L2),numel(uu),x2.p_collision_level,x2.p_subject_welch),'FontSize',11); grid on; ax = gca; ax.XGrid = 'off';
x = TL(TL.signal=="EDA"&TL.s16N_excluded==1,:); nexttile; hold on; for i = 1:5, plot(-log10([x.p_fdr_collision(i) x.p_fdr_model(i)]),[6-i 6-i],'-','Color',[.82 .82 .82],'LineWidth',2.5,'HandleVisibility','off'); end
scatter(-log10(x.p_fdr_collision),6-(1:5),80,GREY,'filled','DisplayName','Treating each collision as independent'); scatter(-log10(x.p_fdr_model),6-(1:5),80,BLUE,'filled','DisplayName','Collisions nested in people'); xline(-log10(.05),'--','Color',INK,'HandleVisibility','off');
yticks(1:5); yticklabels({'L5','L4','L3','L2','L1'}); ylim([.3 5.7]); xlabel('-log_{10}(p_{FDR})'); legend('Location','southeast','Box','off'); title('Collision-locked EDA, HF vs NHF'); grid on; ax = gca; ax.YGrid = 'off';
local_save(fig,out,'F08_collisions_nested_in_people','Collision-level tests count each event as new evidence. By person, the group difference is not there.');

%% F09. Difficulty confound
FR = readtable(fullfile(c,'collision_coupling','force_coupling_robustness.csv'),'TextType','string'); x = FR(FR.predictor=="log_tssf",:); m = height(x);
fig = figure('Position',[50 50 1300 470]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
nexttile; hold on; plot(1:m,-log10(x.p_within),'o-','Color',GREY,'MarkerFaceColor',GREY,'LineWidth',2,'DisplayName','Force predicts SCL'); plot(1:m,-log10(x.p_interaction),'o-','Color',BLUE,'MarkerFaceColor',BLUE,'LineWidth',2,'DisplayName','HF vs NHF difference');
yline(-log10(.05),'--','Color',INK,'HandleVisibility','off'); xticks(1:m); xticklabels(x.model); xtickangle(25); ylabel('-log_{10} p'); legend('Location','northeast','Box','off'); title('Force and SCL: effects fade as controls are added'); grid on;
K = {'subject','level','repetition'}; Yt = Y(strcmp(Y.phase_type,'training'),[K {'gaze_entropy'}]); Pt = P(strcmp(P.phase_type,'training'),[K {'duration_s'}]); Z = innerjoin(Yt,Pt,'Keys',K); Z = Z(isfinite(Z.gaze_entropy)&isfinite(Z.duration_s),:);
[g,~] = findgroups(string(Z.subject)); me = splitapply(@mean,Z.gaze_entropy,g); mt = splitapply(@mean,Z.duration_s,g); Z.e = Z.gaze_entropy-me(g); Z.t = Z.duration_s-mt(g); shade = [.75 .62 .48 .34 .2];
nexttile; hold on; bAll = polyfit(Z.e,Z.t,1); slopes = nan(5,1);
for lv = 1:5
    i = Z.level==lv; col = BLUE*(1-shade(lv))+shade(lv)*[1 1 1]; scatter(Z.e(i),Z.t(i),8,col,'filled','MarkerFaceAlpha',.25,'HandleVisibility','off'); bb = polyfit(Z.e(i),Z.t(i),1); slopes(lv) = bb(1); xr = prctile(Z.e(i),[5 95]); plot(xr,polyval(bb,xr),'-','Color',col,'LineWidth',2.5,'DisplayName',sprintf('L%d',lv));
end
xr = prctile(Z.e,[2 98]); plot(xr,polyval(bAll,xr),'--','Color',INK,'LineWidth',2.5,'DisplayName','All levels pooled'); ylim(prctile(Z.t,[1 99])); xlabel('Gaze entropy, relative to own mean (bits)'); ylabel('Completion time, relative to own mean (s)'); legend('Location','eastoutside','Box','off'); grid on;
title(sprintf('Pooled slope %+.1f s per bit, mean slope within level %+.1f',bAll(1),mean(slopes)));
local_save(fig,out,'F09_difficulty_confound','Harder levels raise everything at once, so ignoring level creates or reverses relationships');

%% F10. Figures that plotted the wrong model
fig = figure('Position',[50 50 1150 720]); tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
[a1,a2,a3,a4] = local_simple(eye_.results{1}.simple_effects); nexttile; local_lines(a1,a2,a3,a4,CN,CH); title('Fig 9 as printed, labelled "Gaze entropy"'); ylabel('Actually pupil, change from L1');
[a1,a2,a3,a4] = local_simple(local_model(eye_,'gaze_entropy').simple_effects); nexttile; local_lines(a1,a2,a3,a4,CN,CH); title('Real gaze entropy'); ylabel('Bits, change from L1');
[a1,a2,a3,a4] = local_simple(eye_.results{3}.simple_effects); nexttile; local_lines(a1,a2,a3,a4,CN,CH); title('Fig 10 as printed, labelled "Fixation rate"'); ylabel('Actually saccade rate, per min');
[a1,a2,a3,a4] = local_simple(local_model(eye_,'fixation_rate').simple_effects); nexttile; local_lines(a1,a2,a3,a4,CN,CH); title('Real fixation rate, same saved model'); ylabel('Fixations per min, change from L1');
local_save(fig,out,'F10_wrong_model_plotted','A plotting error: two paper figures drew a different model from their label (same saved results)');

%% F11. Mismatched baseline levels
[dU,hU,nP,nQ] = local_change(F,'tssv_log','Baseline1','Baseline2',false); [dM,~] = local_change(F,'tssv_log','Baseline1','Baseline2',true); mis = nP~=nQ;
fig = figure('Position',[50 50 1150 450]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
nexttile; hold on; X_ = [nP nQ]; k = all(X_>0,2); h_ = histcounts2(X_(k,1),X_(k,2),.5:1:5.5,.5:1:5.5); [i1,i2] = find(h_>0); scatter(i1,i2,h_(sub2ind(size(h_),i1,i2))*40+25,GREY,'filled','MarkerFaceAlpha',.8); plot([.5 5.5],[.5 5.5],'-','Color',[.8 .8 .8]); xlim([.5 5.5]); ylim([.5 5.5]); xticks(1:5); yticks(1:5); axis square; xlabel('Valid TSSV levels at Baseline1'); ylabel('Valid TSSV levels at Baseline2'); title(sprintf('%d subjects have different levels pre and post (dot size = subjects)',sum(mis&k)),'FontSize',11); grid on;
nexttile; hold on; v = isfinite(dU)&isfinite(dM); lim = [min([dU(v);dM(v)])-.2 max([dU(v);dM(v)])+.2]; plot(lim,lim,'-','Color',[.8 .8 .8],'HandleVisibility','off'); scatter(dU(v&~mis),dM(v&~mis),55,GREY,'filled','DisplayName','Same levels'); scatter(dU(v&mis),dM(v&mis),70,WARN,'filled','DisplayName','Different levels');
xlabel('Change using all available levels (log TSSV)'); ylabel('Change using matched levels'); axis square; xlim(lim); ylim(lim); legend('Location','northwest','Box','off'); title('Only mismatched subjects move'); grid on;
local_save(fig,out,'F11_mismatched_baseline_levels','Pre and post averages sometimes used different difficulty levels');

%% F12. What did not change
o = fullfile(r); nw = fullfile(c,'layer1'); rows = {'Time, NHF','duration_s','within_N';'Time, HF','duration_s','within_H';'Collisions, NHF','n_collisions','within_N';'Collisions, HF','n_collisions','within_H'};
R0 = nan(4,1); R1 = R0;
for i = 1:4
    A0 = readtable(fullfile(o,sprintf('layer1_baseline_elastic_%s.csv',rows{i,3})),'TextType','string'); A1 = readtable(fullfile(nw,sprintf('layer1_baseline_elastic_%s.csv',rows{i,3})),'TextType','string');
    R0(i) = A0.mean_diff(A0.outcome==rows{i,2}); R1(i) = A1.mean_diff(A1.outcome==rows{i,2});
end
pT = perf.results{1}; rT = TR(strcmp(TR.outcome,'duration_s')&strcmp(TR.term,'repetition:haptic_num'),:); rC = TR(strcmp(TR.outcome,'n_collisions')&strcmp(TR.term,'repetition:haptic_num'),:);
fig = figure('Position',[50 50 1150 420]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
for t = 1:2
    nexttile; hold on; ii = (t-1)*2+(1:2); xx = [1 2]; wid = .34; bar(xx-wid/2,R0(ii),wid,'FaceColor',GREY,'EdgeColor','none','DisplayName','Original'); bar(xx+wid/2,R1(ii),wid,'FaceColor',BLUE,'EdgeColor','none','DisplayName','Corrected');
    xticks(xx); xticklabels({'NHF','HF'}); yline(0,'-','Color',INK,'HandleVisibility','off');
    if t==1, ylabel('Change, BL1 to BL2 (s)'); title(sprintf('Completion time. Haptic \\times Repetition p = %.3f then %.3f',pT.interaction_p,rT.p_robust),'FontSize',11); else, ylabel('Change, BL1 to BL2 (per trial)'); title(sprintf('Collisions. Haptic \\times Repetition p = %.3f then %.3f',rC.p_orig,rC.p_robust),'FontSize',11); end
    legend('Location','southoutside','Orientation','horizontal','Box','off'); grid on; ax = gca; ax.XGrid = 'off';
end
local_save(fig,out,'F12_what_did_not_change','What did not change: both groups learned, and performance shows no group difference');
fprintf('FIGURES_DONE\n');

function local_save(fig,out,name,ttl)
    sgtitle(ttl,'FontWeight','bold','FontSize',14,'Color',[.15 .15 .15]);
    ax = findall(fig,'Type','axes'); for i = 1:numel(ax), ax(i).Toolbar.Visible = 'off'; end
    exportgraphics(fig,fullfile(out,[name '.png']),'Resolution',200,'BackgroundColor','w');
end
function c = local_pick(k,a,b), if k==1, c = a; else, c = b; end, end
function [d,h,nP,nQ] = local_change(T,oc,p1,p2,matched)
    if nargin<5, matched = true; end
    T = T(ismember(T.phase,{p1,p2})&isfinite(T.(oc)),:); s = string(T.subject); u = unique(s); d = nan(numel(u),1); nP = zeros(numel(u),1); nQ = nP;
    for i = 1:numel(u)
        ix = s==u(i); a = T.acquisition(ix&strcmp(T.phase,p1)); b = T.acquisition(ix&strcmp(T.phase,p2)); nP(i) = numel(a); nQ(i) = numel(b);
        if matched, sh = intersect(a,b); else, sh = union(a,b); end
        if isempty(sh)||isempty(a)||isempty(b), continue; end
        in = ismember(T.acquisition,sh); d(i) = mean(T.(oc)(ix&strcmp(T.phase,p2)&in))-mean(T.(oc)(ix&strcmp(T.phase,p1)&in));
    end
    h = endsWith(u,'H');
end
function r = local_model(S,name)
    ix = find(strcmp(S.outcomes,name),1); r = S.results{ix};
end
function [mN,sN,mH,sH] = local_simple(se)
    mN = zeros(1,5); sN = mN; mH = mN; sH = mN;
    for lv = 2:5
        k = strcmp(se.effect,sprintf('level %d vs level 1',lv)); n = strcmp(se.group,'N'); h = strcmp(se.group,'H');
        mN(lv) = se.beta(k&n); sN(lv) = se.se(k&n); mH(lv) = se.beta(k&h); sH(lv) = se.se(k&h);
    end
end
function [mN,sN,mH,sH] = local_levels(T,oc)
    D = T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:); s = string(D.subject); u = unique(s); M = nan(numel(u),5); h = endsWith(u,'H');
    for i = 1:numel(u), for l = 1:5, M(i,l) = mean(D.(oc)(s==u(i)&D.level==l),'omitnan'); end; end
    d = M-M(:,1); mN = mean(d(~h,:),'omitnan'); sN = std(d(~h,:),'omitnan')./sqrt(sum(isfinite(d(~h,:)))); mH = mean(d(h,:),'omitnan'); sH = std(d(h,:),'omitnan')./sqrt(sum(isfinite(d(h,:))));
end
function local_lines(mN,sN,mH,sH,CN,CH)
    hold on; x = 1:5;
    fill([x fliplr(x)],[mN+1.96*sN fliplr(mN-1.96*sN)],CN,'FaceAlpha',.13,'EdgeColor','none','HandleVisibility','off'); fill([x fliplr(x)],[mH+1.96*sH fliplr(mH-1.96*sH)],CH,'FaceAlpha',.13,'EdgeColor','none','HandleVisibility','off');
    plot(x,mN,'o-','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'DisplayName','NHF'); plot(x,mH,'o-','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'DisplayName','HF');
    yline(0,'-','Color',[.6 .6 .6],'HandleVisibility','off'); xticks(x); xticklabels({'L1','L2','L3','L4','L5'}); xlim([.8 5.2]); legend('Location','southoutside','Orientation','horizontal','Box','off'); grid on;
end
function local_ba(a,b,af,W,G,B)
    % Before and after for each subject. Affected subjects are in the warning colour.
    n = numel(a);
    for i = 1:n, plot([1 2],[max(a(i),.5) max(b(i),.5)],'-','Color',[.85 .85 .85],'HandleVisibility','off'); end
    scatter(1+(rand(sum(~af),1)-.5)*.12,max(a(~af),.5),45,G,'filled','MarkerFaceAlpha',.7,'DisplayName','Other subjects, before');
    scatter(1+(rand(sum(af),1)-.5)*.12,max(a(af),.5),60,W,'filled','DisplayName','Subjects with duplicates, before');
    scatter(2+(rand(sum(~af),1)-.5)*.12,max(b(~af),.5),45,B,'filled','MarkerFaceAlpha',.7,'DisplayName','Other subjects, after');
    scatter(2+(rand(sum(af),1)-.5)*.12,max(b(af),.5),60,W,'filled','HandleVisibility','off');
    xticks([1 2]); xticklabels({'Original detector','Corrected detector'}); xlim([.6 2.4]); legend('Location','southoutside','Orientation','horizontal','Box','off'); grid on; ax = gca; ax.XGrid = 'off';
end
