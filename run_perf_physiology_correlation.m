%% performance_physiology_correlation.m
clear; clc; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV=FV.T;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); Eb=EDA.T;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); Yb=EYE.T;
PERF= load(fullfile(cfg.output_root,'perf_features.mat'),'T'); Tp=PERF.T;
CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI=CI.T_impact;
CM  = load(fullfile(cfg.output_root,'h2_eda_accel_bins_results.mat'),'lme_c3'); 

% also load per-subject C3 rho if saved
% if not, recompute from EDA join

subj_list = unique(Tp.subject);
n_subj    = numel(subj_list);

%% Build subject-level summary table
D = table();
D.subject  = subj_list;
D.haptic   = false(n_subj,1);
D.group    = repmat({'N'},n_subj,1);

% Performance deltas
D.dur_bl1  = nan(n_subj,1);   % BL1 mean completion time
D.dur_bl2  = nan(n_subj,1);   % BL2 mean completion time
D.dur_t1   = nan(n_subj,1);
D.dur_t2   = nan(n_subj,1);
D.coll_bl1 = nan(n_subj,1);
D.coll_bl2 = nan(n_subj,1);

% EDA training mean
D.scl_train   = nan(n_subj,1);   % mean tonic SCL during training
D.erscr_train = nan(n_subj,1);   % mean ER-SCR amplitude during training

% Pupil training mean
D.pupil_train = nan(n_subj,1);

% TSSV/TSSF training mean
D.tssv_train  = nan(n_subj,1);
D.tssf_train  = nan(n_subj,1);

for si = 1:n_subj
    s  = subj_list{si};
    Ts_perf = Tp(strcmp(Tp.subject,s),:);
    Ts_eda  = Eb(strcmp(Eb.subject,s),:);
    Ts_eye  = Yb(strcmp(Yb.subject,s),:);
    Ts_fv   = FV(strcmp(FV.subject,s),:);

    D.haptic(si) = any(Ts_perf.haptic);
    D.group{si}  = Tp.group{find(strcmp(Tp.subject,s),1)};

    % performance
    for ph_pair = {{'Baseline1','dur_bl1'},{'Baseline2','dur_bl2'},{'Test1','dur_t1'},{'Test2','dur_t2'}}
        v=Ts_perf.duration_s(strcmp(Ts_perf.phase,ph_pair{1}{1})&isfinite(Ts_perf.duration_s));
        if ~isempty(v), D.(ph_pair{1}{2})(si)=mean(v,'omitnan'); end
    end
    for ph_pair = {{'Baseline1','coll_bl1'},{'Baseline2','coll_bl2'}}
        v=Ts_perf.n_collisions(strcmp(Ts_perf.phase,ph_pair{1}{1})&isfinite(Ts_perf.n_collisions));
        if ~isempty(v), D.(ph_pair{1}{2})(si)=mean(v,'omitnan'); end
    end

    % EDA training
    Te=Ts_eda(strcmp(Ts_eda.phase_type,'training'),:);
    D.scl_train(si)  =mean(Te.scl_mean_bc(isfinite(Te.scl_mean_bc)),'omitnan');
    D.erscr_train(si)=mean(Te.collision_scr_amp_mean_bc(isfinite(Te.collision_scr_amp_mean_bc)),'omitnan');

    % pupil training
    Ty=Ts_eye(strcmp(Ts_eye.phase_type,'training'),:);
    D.pupil_train(si)=mean(Ty.pupil_mean_norm(isfinite(Ty.pupil_mean_norm)),'omitnan');

    % TSSV/TSSF training
    Tf=Ts_fv(strcmp(Ts_fv.phase_type,'training')&isfinite(Ts_fv.tssv)&Ts_fv.tssv>0,:);
    D.tssv_train(si)=mean(log(Tf.tssv),'omitnan');
    Tf2=Ts_fv(strcmp(Ts_fv.phase_type,'training')&isfinite(Ts_fv.tssf)&Ts_fv.tssf>0,:);
    D.tssf_train(si)=mean(log(Ts_fv.tssf(strcmp(Ts_fv.phase_type,'training')&isfinite(Ts_fv.tssf)&Ts_fv.tssf>0)),'omitnan');
end

% performance deltas
D.delta_dur_bl  = D.dur_bl2  - D.dur_bl1;   % negative = faster
D.delta_coll_bl = D.coll_bl2 - D.coll_bl1;  % negative = fewer collisions
D.delta_dur_te  = D.dur_t2   - D.dur_t1;
D.haptic_num    = double(D.haptic);

%% P1: training physiology -> performance improvement
fprintf('\n=== P1: Training physiology -> BL1→BL2 performance improvement ===\n');
fprintf('(negative delta = improvement; negative rho = higher physiology = more improvement)\n\n');

predictors = {'scl_train','erscr_train','pupil_train','tssv_train','tssf_train'};
pred_labels = {'Tonic SCL (train)','ER-SCR amp (train)','Pupil dilation (train)','log-TSSV (train)','log-TSSF (train)'};
outcomes_p  = {'delta_dur_bl','delta_coll_bl','delta_dur_te'};
out_labels  = {'Δ duration BL1→BL2','Δ collisions BL1→BL2','Δ duration T1→T2'};

fprintf('%-25s %-22s %8s %8s %8s %8s %8s %8s\n','Predictor','Outcome','rho_all','p_all','rho_N','p_N','rho_H','p_H');
all_p1 = struct();
for pi = 1:numel(predictors)
    pred = predictors{pi};
    for oi = 1:numel(outcomes_p)
        oc = outcomes_p{oi};
        x_all = D.(pred); y_all = D.(oc);
        keep = isfinite(x_all)&isfinite(y_all);
        [rho_all,p_all] = corr(x_all(keep),y_all(keep),'Type','Spearman');
        xN=D.(pred)(~D.haptic&keep); yN=D.(oc)(~D.haptic&keep);
        xH=D.(pred)( D.haptic&keep); yH=D.(oc)( D.haptic&keep);
        rho_N=NaN; p_N=NaN; rho_H=NaN; p_H=NaN;
        if numel(xN)>4, [rho_N,p_N]=corr(xN,yN,'Type','Spearman'); end
        if numel(xH)>4, [rho_H,p_H]=corr(xH,yH,'Type','Spearman'); end
        fprintf('%-25s %-22s %8.3f %8.4f %8.3f %8.4f %8.3f %8.4f\n',...
            pred_labels{pi},out_labels{oi},rho_all,p_all,rho_N,p_N,rho_H,p_H);
        all_p1.(pred).(oc) = struct('rho_all',rho_all,'p_all',p_all,'rho_N',rho_N,'p_N',p_N,'rho_H',rho_H,'p_H',p_H);
    end
end

%% P2: per-subject C3 rho -> performance improvement
% recompute per-subject peak_accel_g -> log_scr Spearman rho from training
fprintf('\n=== P2: EDA-intensity coupling (C3 rho) -> performance improvement ===\n');
EDA_coll = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec=EDA_coll.T_coll;
T_CI_tr = T_CI(strcmp(T_CI.phase_type,'training'),:);
Ec_tr   = Ec(strcmp(Ec.phase_type,'training'),:);
J_c3 = innerjoin(T_CI_tr, Ec_tr,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'scr_amp_local_bc'});
hap_c3=local_find_haptic(J_c3);
bad=J_c3.scr_amp_local_bc<-0.5|J_c3.scr_amp_local_bc>5.0;
J_c3=J_c3(~bad&isfinite(J_c3.scr_amp_local_bc)&isfinite(J_c3.peak_accel_g),:);
offset_scr=abs(min(J_c3.scr_amp_local_bc))+0.01;
J_c3.log_scr=log(J_c3.scr_amp_local_bc+offset_scr);

D.c3_rho = nan(n_subj,1);
for si=1:n_subj
    s=subj_list{si}; Js=J_c3(strcmp(J_c3.subject,s),:);
    if height(Js)<5, continue; end
    v=Js.peak_accel_g; v_z=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
    D.c3_rho(si)=corr(v_z,Js.log_scr,'Type','Spearman','Rows','complete');
end

fprintf('%-22s %-22s %8s %8s %8s %8s %8s %8s\n','Predictor','Outcome','rho_all','p_all','rho_N','p_N','rho_H','p_H');
for oi=1:numel(outcomes_p)
    oc=outcomes_p{oi};
    x_all=D.c3_rho; y_all=D.(oc);
    keep=isfinite(x_all)&isfinite(y_all);
    [rho_all,p_all]=corr(x_all(keep),y_all(keep),'Type','Spearman');
    xN=D.c3_rho(~D.haptic&keep); yN=D.(oc)(~D.haptic&keep);
    xH=D.c3_rho( D.haptic&keep); yH=D.(oc)( D.haptic&keep);
    rho_N=NaN; p_N=NaN; rho_H=NaN; p_H=NaN;
    if numel(xN)>4,[rho_N,p_N]=corr(xN,yN,'Type','Spearman'); end
    if numel(xH)>4,[rho_H,p_H]=corr(xH,yH,'Type','Spearman'); end
    fprintf('%-22s %-22s %8.3f %8.4f %8.3f %8.4f %8.3f %8.4f\n',...
        'C3 rho (accel→SCR)',out_labels{oi},rho_all,p_all,rho_N,p_N,rho_H,p_H);
end

%% P3: within-level pupil habituation rate -> performance
fprintf('\n=== P3: Pupil within-level habituation rate -> performance improvement ===\n');
Yb_tr = Yb(strcmp(Yb.phase_type,'training')&isfinite(Yb.pupil_mean_norm),:);
D.pupil_habit_rho = nan(n_subj,1);
for si=1:n_subj
    s=subj_list{si}; Ts=Yb_tr(strcmp(Yb_tr.subject,s),:);
    if height(Ts)<5, continue; end
    subj_by_rep=nan(1,10);
    for ri=1:10
        v=Ts.pupil_mean_norm(Ts.repetition==ri);
        if ~isempty(v), subj_by_rep(ri)=mean(v,'omitnan'); end
    end
    valid=isfinite(subj_by_rep);
    if sum(valid)>4
        D.pupil_habit_rho(si)=corr((1:10)',(subj_by_rep)','Type','Spearman','Rows','complete');
    end
end

for oi=1:numel(outcomes_p)
    oc=outcomes_p{oi};
    x_all=D.pupil_habit_rho; y_all=D.(oc);
    keep=isfinite(x_all)&isfinite(y_all);
    [rho_all,p_all]=corr(x_all(keep),y_all(keep),'Type','Spearman');
    fprintf('Pupil habit rho -> %s: rho=%.3f p=%.4f (n=%d)\n',out_labels{oi},rho_all,p_all,sum(keep));
end

%% Figures
CN2=[64 96 179]/255; CH2=[139 82 168]/255;

% Figure: key scatter plots
fig=figure('Position',[50 50 1400 900]);
tl=tiledlayout(3,4,'TileSpacing','compact','Padding','compact');
title(tl,'Performance-physiology correlations (Spearman, training phase → BL1→BL2 improvement)', ...
    'FontWeight','bold','FontSize',11);

plot_pairs = {
    'scl_train',   'delta_dur_bl',  'Tonic SCL (train)','Δ duration BL1→BL2 (s)'
    'erscr_train', 'delta_dur_bl',  'ER-SCR amp (train)','Δ duration BL1→BL2 (s)'
    'tssf_train',  'delta_dur_bl',  'log-TSSF (train)','Δ duration BL1→BL2 (s)'
    'c3_rho',      'delta_dur_bl',  'EDA-intensity rho (C3)','Δ duration BL1→BL2 (s)'
    'scl_train',   'delta_coll_bl', 'Tonic SCL (train)','Δ collisions BL1→BL2'
    'erscr_train', 'delta_coll_bl', 'ER-SCR amp (train)','Δ collisions BL1→BL2'
    'tssf_train',  'delta_coll_bl', 'log-TSSF (train)','Δ collisions BL1→BL2'
    'c3_rho',      'delta_coll_bl', 'EDA-intensity rho (C3)','Δ collisions BL1→BL2'
    'scl_train',   'delta_dur_te',  'Tonic SCL (train)','Δ duration T1→T2 (s)'
    'erscr_train', 'delta_dur_te',  'ER-SCR amp (train)','Δ duration T1→T2 (s)'
    'tssf_train',  'delta_dur_te',  'log-TSSF (train)','Δ duration T1→T2 (s)'
    'c3_rho',      'delta_dur_te',  'EDA-intensity rho (C3)','Δ duration T1→T2 (s)'
};

for pp=1:size(plot_pairs,1)
    pred=plot_pairs{pp,1}; oc=plot_pairs{pp,2};
    xl=plot_pairs{pp,3}; yl=plot_pairs{pp,4};
    x_all=D.(pred); y_all=D.(oc);
    keep=isfinite(x_all)&isfinite(y_all);
    [rho_all,p_all]=corr(x_all(keep),y_all(keep),'Type','Spearman');
    nexttile; hold on;
    scatter(x_all(~D.haptic&keep),y_all(~D.haptic&keep),35,CN2,'filled','MarkerFaceAlpha',0.6,'DisplayName','NHF');
    scatter(x_all( D.haptic&keep),y_all( D.haptic&keep),35,CH2,'filled','MarkerFaceAlpha',0.6,'DisplayName','HF');
    % OLS line
    pf=polyfit(x_all(keep),y_all(keep),1);
    xl_range=[min(x_all(keep)) max(x_all(keep))];
    plot(xl_range,polyval(pf,xl_range),'k--','LineWidth',1.2,'HandleVisibility','off');
    yline(0,'k:','LineWidth',0.8,'HandleVisibility','off');
    xlabel(xl,'FontSize',8,'Interpreter','none'); ylabel(yl,'FontSize',8,'Interpreter','none');
    title(sprintf('rho=%.3f  p=%.4f',rho_all,p_all),'FontSize',8);
    if pp==1, legend('Location','best','FontSize',7); end
    grid on; box on;
end
exportgraphics(fig,fullfile(fig_dir,'performance_physiology_correlations.png'),'Resolution',180);

save(fullfile(cfg.output_root,'performance_physiology_results.mat'),'D','all_p1');
fprintf('\nSaved performance_physiology_results.mat\n');

function hap_col=local_find_haptic(T)
    for k={'haptic','haptic_x','haptic_y'}
        if ismember(k{1},T.Properties.VariableNames)&&islogical(T.(k{1})), hap_col=k{1}; return; end
    end
    error('No logical haptic column. Available: %s',strjoin(T.Properties.VariableNames,', '));
end