%% claude_pooled_questions_02_stats.m
% Tests the questions in claude_pooled_questions_plan.md, with subjects as the unit of inference. Groups pooled; group difference is a check.
% Writes ONLY to <output_root>/Claude_outputs/pooled_questions.
clear; clc; close all; cfg = config(); rng(20261106);
r = cfg.output_root; out = fullfile(r,'Claude_outputs','pooled_questions'); L = load(fullfile(out,'trial_measures.mat')); M = L.T;
P = load(fullfile(r,'perf_features.mat'),'T'); P = P.T; F = load(fullfile(r,'force_vibration_features_clean.mat'),'T'); F = F.T;
EX = load(fullfile(r,'accel_exclusion_lists.mat')); CI = load(fullfile(r,'collision_impact_features.mat'),'T_impact'); CI = CI.T_impact;
D = readtable(fullfile(cfg.data_root,'demographics.csv'),'TextType','string'); D = D(ismember(D.subject,string(cfg.all_subjects)),:);
subs = string(cfg.all_subjects)'; hS = endsWith(subs,'H');

% Apply the existing sensor exclusions
key = @(T) string(T.subject)+"|"+string(T.phase)+"|"+string(T.acquisition);
badA = EX.tssv_acq_excl; kA = string(badA(:,1))+"|"+string(badA(:,2))+"|"+string(badA(:,3)); badF = EX.tssf_acq_excl; kF = string(badF(:,1))+"|"+string(badF(:,2))+"|"+string(badF(:,3));
xA = ismember(string(M.subject),string(EX.tssv_subj_excl))|ismember(key(M),kA); xF = ismember(string(M.subject),string(EX.tssf_subj_excl))|ismember(key(M),kF);
for v = {'move_L','move_R','vib_L','vib_R','env_corr','one_hand_share'}, M.(v{1})(xA) = NaN; end
for v = {'fz_share','fz_rate','lat_rate','fz_peak','fz_mean'}, M.(v{1})(xF) = NaN; end
M.ai_move = (M.move_R-M.move_L)./(M.move_R+M.move_L); M.ai_vib = (M.vib_R-M.vib_L)./(M.vib_R+M.vib_L);
[~,loc] = ismember(string(M.subject),D.subject); lq = D.handedness_LQ(loc); mixed = D.handedness(loc)=="Mixed"|lq==0;
sg = sign(lq); sg(mixed) = NaN; M.ai_move_dom = M.ai_move.*sg; M.ai_vib_dom = M.ai_vib.*sg; M.abs_ai_move = abs(M.ai_move);
M.log_fz_rate = local_log(M.fz_rate); M.log_lat_rate = local_log(M.lat_rate); M.log_fz_peak = local_log(M.fz_peak);
F.tssf(F.tssf<=0) = NaN; F.tssv(F.tssv<=0) = NaN; F.log_tssf = log(F.tssf); F.log_tssv = log(F.tssv);
kk = {'subject','phase','acquisition'}; Fj = outerjoin(F(:,[kk {'tssf','tssv','log_tssf','log_tssv'}]),P(:,[kk {'duration_s','n_collisions','level','repetition','phase_type'}]),'Keys',kk,'MergeKeys',true);
Fj.coll_per_min = Fj.n_collisions./(Fj.duration_s/60); Fj.log_tssf_rate = local_log(Fj.tssf./(Fj.duration_s/60)); Fj.log_tssv_rate = local_log(Fj.tssv./(Fj.duration_s/60));
CIt = CI(isfinite(CI.peak_accel_g_nidaq)&CI.peak_accel_g_nidaq>0&~strcmp(CI.subject,'subject_s16N'),:); CIt.log_peak = log(CIt.peak_accel_g_nidaq);

rows = {};
addp = @(q,name,Tb,oc,p1,p2) local_prepost(q,name,Tb,oc,p1,p2,subs,hS);
for t = {{'Elastic','Baseline1','Baseline2'},{'Peg Transfer','Test1','Test2'}}
    n = t{1}{1}; a = t{1}{2}; b = t{1}{3};
    rows = [rows; addp('Q1',[n ': completion time (s)'],Fj,'duration_s',a,b); addp('Q1',[n ': collisions per trial'],Fj,'n_collisions',a,b); addp('Q1',[n ': log TSSF'],Fj,'log_tssf',a,b); addp('Q1',[n ': log TSSV'],Fj,'log_tssv',a,b)]; %#ok<AGROW>
    rows = [rows; addp('Q2',[n ': collisions per minute'],Fj,'coll_per_min',a,b); addp('Q2',[n ': log peak impact (g)'],CIt,'log_peak',a,b); addp('Q2',[n ': log force rate'],Fj,'log_tssf_rate',a,b); addp('Q2',[n ': log vibration rate'],Fj,'log_tssv_rate',a,b)]; %#ok<AGROW>
    rows = [rows; addp('Q3',[n ': Fz share of force energy'],M,'fz_share',a,b); addp('Q3',[n ': log Fz rate'],M,'log_fz_rate',a,b); addp('Q3',[n ': log lateral rate'],M,'log_lat_rate',a,b); addp('Q3',[n ': log peak |Fz|'],M,'log_fz_peak',a,b)]; %#ok<AGROW>
    rows = [rows; addp('Q4',[n ': dominant-referenced movement AI'],M,'ai_move_dom',a,b); addp('Q4',[n ': |movement AI|'],M,'abs_ai_move',a,b); addp('Q4',[n ': left-right envelope correlation'],M,'env_corr',a,b); addp('Q4',[n ': one-hand share'],M,'one_hand_share',a,b)]; %#ok<AGROW>
end
% Elastic time per level
for lv = 1:5, X = Fj(Fj.level==lv,:); rows = [rows; addp('Q1',sprintf('Elastic L%d: completion time (s)',lv),X,'duration_s','Baseline1','Baseline2')]; end %#ok<AGROW>
% Within training
for x = {{'Q1',Fj,'duration_s','Training: time (s)'},{'Q1',Fj,'n_collisions','Training: collisions'},{'Q1',Fj,'log_tssf','Training: log TSSF'},{'Q1',Fj,'log_tssv','Training: log TSSV'},{'Q3',M,'fz_share','Training: Fz share'},{'Q4',M,'ai_move_dom','Training: dominant-referenced movement AI'},{'Q4',M,'abs_ai_move','Training: |movement AI|'},{'Q4',M,'env_corr','Training: left-right envelope correlation'},{'Q4',M,'one_hand_share','Training: one-hand share'}}
    rows = [rows; local_firstlast(x{1}{1},x{1}{4},x{1}{2},x{1}{3},subs,hS)]; %#ok<AGROW>
end
R = cell2table(rows,'VariableNames',{'question','test','n','pre','post','change','lo','hi','p','dz','group_diff','p_group'});
R.p_fdr = nan(height(R),1); for q = {'Q1','Q2','Q3','Q4'}, i = strcmp(R.question,q{1}); R.p_fdr(i) = local_bh(R.p(i)); end
writetable(R,fullfile(out,'prepost_results.csv'));

%% Depth proxy across level
Tr = M(startsWith(string(M.phase),'level_'),:); Z = nan(numel(subs),5);
for i = 1:numel(subs), for lv = 1:5, Z(i,lv) = mean(Tr.fz_share(string(Tr.subject)==subs(i)&Tr.level==lv),'omitnan'); end; end
c = all(isfinite(Z),2); pf = friedman(Z(c,:),1,'off'); fprintf('Fz share by level: %s; Friedman p=%.3g n=%d\n',mat2str(mean(Z(c,:)),3),pf,sum(c));
writetable(array2table([mean(Z(c,:));std(Z(c,:))],'VariableNames',{'L1','L2','L3','L4','L5'},'RowNames',{'mean','sd'}),fullfile(out,'fz_share_by_level.csv'),'WriteRowNames',true);

%% Hand preference
[~,lc] = ismember(subs,D.subject); LQ = D.handedness_LQ(lc); mix = D.handedness(lc)=="Mixed"|LQ==0; aiM = nan(size(subs)); aiV = aiM; ph = {};
sm = string(M.subject); isT3 = false(height(M),1);
for i = 1:numel(subs), j = sm==subs(i)&~isT3; aiM(i) = mean(M.ai_move(j),'omitnan'); aiV(i) = mean(M.ai_vib(j),'omitnan'); end
rowsH = {};
for m = {{'Movement',aiM},{'Vibration',aiV}}
    a = m{1}{2}; v = isfinite(a); [e,lo,hi,p,dz] = local_one(a(v)); rowsH(end+1,:) = {[m{1}{1} ': mean AI (right minus left)'],sum(v),e,lo,hi,p,dz}; %#ok<AGROW>
    [rs,ps] = corr(a(v),LQ(v),'Type','Spearman'); z = atanh(rs); se = 1.06/sqrt(sum(v)-3); rowsH(end+1,:) = {[m{1}{1} ': Spearman with LQ'],sum(v),rs,tanh(z-1.96*se),tanh(z+1.96*se),ps,NaN}; %#ok<AGROW>
    w = v&~mix; match = sign(a(w))==sign(LQ(w)); pb = myBinom(sum(match),sum(w)); rowsH(end+1,:) = {[m{1}{1} ': more active tool = questionnaire hand'],sum(w),mean(match),NaN,NaN,pb,NaN}; %#ok<AGROW>
    rg = v&LQ>0&~mix; rowsH(end+1,:) = {[m{1}{1} ': share of right-handers more active on the right'],sum(rg),mean(a(rg)>0),NaN,NaN,myBinom(sum(a(rg)>0),sum(rg)),NaN}; %#ok<AGROW>
end
TH = cell2table(rowsH,'VariableNames',{'test','n','estimate','lo','hi','p','dz'}); TH.p_fdr = local_bh(TH.p); writetable(TH,fullfile(out,'hand_preference.csv'));
Sb = table(subs,D.handedness(lc),LQ,aiM,aiV,'VariableNames',{'subject','handedness','LQ','ai_move','ai_vib'}); writetable(Sb,fullfile(out,'subject_handedness.csv'));
disp(Sb(LQ<40,:));

%% Figures
GREY = [122 127 135]/255; BLUE = [31 111 209]/255; INK = [.15 .15 .15]; WARN = [194 84 45]/255;
fig = figure('Position',[50 50 1250 460]); tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
nexttile; hold on; local_paired(Fj,'duration_s','Baseline1','Baseline2',subs,GREY,BLUE); ylabel('Completion time (s)'); title('Elastic task');
nexttile; hold on; local_paired(Fj,'duration_s','Test1','Test2',subs,GREY,BLUE); ylabel('Completion time (s)'); title('Peg Transfer');
nexttile; hold on; local_paired(Fj,'coll_per_min','Baseline1','Baseline2',subs,GREY,BLUE); ylabel('Collisions per minute'); title('Elastic task, per minute');
sgtitle('Practice: each line is one person, the thick line is the mean','FontWeight','bold'); exportgraphics(fig,fullfile(out,'practice_prepost.png'),'Resolution',200);
fig = figure('Position',[50 50 1150 470]); tiledlayout(1,2,'TileSpacing','loose','Padding','compact');
nexttile; hold on; xline(0,'-','Color',[.8 .8 .8],'HandleVisibility','off'); yline(0,'-','Color',[.8 .8 .8],'HandleVisibility','off'); v = isfinite(aiM); scatter(LQ(v&~mix),aiM(v&~mix),55,GREY,'filled','DisplayName','Right or left handed'); scatter(LQ(v&mix),aiM(v&mix),65,WARN,'filled','DisplayName','Mixed'); xlabel('Handedness LQ (negative = left)'); ylabel('Movement AI (positive = right tool moves more)'); legend('Location','best','Box','off'); grid on; [rs,ps] = corr(aiM(v),LQ(v),'Type','Spearman'); title(sprintf('Tool use vs questionnaire: Spearman r = %.2f, p = %.2f',rs,ps),'FontSize',11);
nexttile; hold on; local_paired(M,'ai_move_dom','Baseline1','Baseline2',subs,GREY,BLUE); yline(0,'-','Color',INK); ylabel('Movement AI (positive = dominant hand)'); title('Elastic task: before and after training');
sgtitle('Hand use from tool movement (0.5-5 Hz)','FontWeight','bold'); exportgraphics(fig,fullfile(out,'hand_use.png'),'Resolution',200);
fprintf('POOLED_STATS_DONE\n');

function y = local_log(x), x(x<=0) = NaN; y = log(x); end
function rows = local_prepost(q,name,T,oc,p1,p2,subs,hS)
    s = string(T.subject); pre = nan(numel(subs),1); post = pre; isCol = ~ismember('acquisition',T.Properties.VariableNames);
    for i = 1:numel(subs)
        a = s==subs(i)&strcmp(T.phase,p1)&isfinite(T.(oc)); b = s==subs(i)&strcmp(T.phase,p2)&isfinite(T.(oc));
        sh = intersect(T.acquisition(a),T.acquisition(b)); if isempty(sh), continue; end
        pre(i) = mean(T.(oc)(a&ismember(T.acquisition,sh))); post(i) = mean(T.(oc)(b&ismember(T.acquisition,sh)));
    end
    rows = local_row(q,name,pre,post,hS);
end
function rows = local_firstlast(q,name,T,oc,subs,hS)
    isTr = startsWith(string(T.phase),'level_'); s = string(T.subject); pre = nan(numel(subs),1); post = pre;
    for i = 1:numel(subs)
        a = nan(5,1); b = a;
        for lv = 1:5
            j = s==subs(i)&isTr&T.level==lv&isfinite(T.(oc)); f = j&T.repetition<=3; g = j&T.repetition>=8;
            if any(f)&&any(g), a(lv) = mean(T.(oc)(f)); b(lv) = mean(T.(oc)(g)); end
        end
        pre(i) = mean(a,'omitnan'); post(i) = mean(b,'omitnan');
    end
    rows = local_row(q,name,pre,post,hS);
end
function row = local_row(q,name,pre,post,hS)
    k = isfinite(pre)&isfinite(post); d = post(k)-pre(k); [e,lo,hi,p,dz] = local_one(d); h = hS(k); pg = NaN; dg = NaN;
    if sum(h)>2&&sum(~h)>2, [~,pg] = ttest2(d(h),d(~h),'Vartype','unequal'); dg = mean(d(h))-mean(d(~h)); end
    row = {q,name,sum(k),mean(pre(k)),mean(post(k)),e,lo,hi,p,dz,dg,pg};
end
function [e,lo,hi,p,dz] = local_one(d)
    n = numel(d); e = mean(d); se = std(d)/sqrt(n); t = tinv(.975,n-1); lo = e-t*se; hi = e+t*se; dz = e/std(d); [~,p] = ttest(d);
end
function p = myBinom(k,n)
    p = 2*min(binocdf(k,n,.5),1-binocdf(k-1,n,.5)); p = min(p,1);
end
function local_paired(T,oc,p1,p2,subs,G,B)
    s = string(T.subject); pre = nan(numel(subs),1); post = pre;
    for i = 1:numel(subs)
        a = s==subs(i)&strcmp(T.phase,p1)&isfinite(T.(oc)); b = s==subs(i)&strcmp(T.phase,p2)&isfinite(T.(oc)); sh = intersect(T.acquisition(a),T.acquisition(b)); if isempty(sh), continue; end
        pre(i) = mean(T.(oc)(a&ismember(T.acquisition,sh))); post(i) = mean(T.(oc)(b&ismember(T.acquisition,sh)));
    end
    k = isfinite(pre)&isfinite(post); plot([1 2],[pre(k) post(k)]','-','Color',[.8 .8 .8]); plot([1 2],[mean(pre(k)) mean(post(k))],'-o','Color',B,'MarkerFaceColor',B,'LineWidth',3,'MarkerSize',8); xticks([1 2]); xticklabels({'Before','After'}); xlim([.75 2.25]); grid on;
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps); a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
