%% plot_before_after_cleaning.m
clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','before_after');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T_raw=FV_raw.T;
FV_cln = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_cln=FV_cln.T;

C_force = load_ati_cal(cfg.force_cal_path);

excl_tssv = {'subject_s02N','subject_s05N','subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N'};
excl_tssf = {'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};

metrics = {'tssv','tssf'};
ylabels = {'log-TSSV [(m/s²)²·s]','log-TSSF [N²]'};
titles  = {'TSSV','TSSF'};

for mi = 1:2
    oc   = metrics{mi};
    yl   = ylabels{mi};
    ttl  = titles{mi};
    excl = local_ternary(mi==1, excl_tssv, excl_tssf);

    T_tr_all  = T_raw(strcmp(T_raw.phase_type,'training') & isfinite(T_raw.(oc)) & T_raw.(oc)>0,:);
    T_tr_excl = T_tr_all(~ismember(T_tr_all.subject,excl),:);
    T_tr_cln  = T_cln(strcmp(T_cln.phase_type,'training') & isfinite(T_cln.(oc)) & T_cln.(oc)>0,:);

    datasets  = {T_tr_all, T_tr_excl, T_tr_cln};
    dslabels  = {
        'RAW — all subjects including excluded (what supervisor saw)'
        sprintf('After whole-subject exclusions (%s)',strjoin(strrep(excl,'subject_',''),', '))
        'After level-dependent p1/p99 cleaning (final)'
    };

    %% ── Figure 1: per-level scatter ──────────────────────────────────────
    fig = figure('Position',[50 50 1800 900]);
    tl  = tiledlayout(3,5,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s: before and after cleaning — per-level scatter + mean±95%%CI',ttl),...
        'FontWeight','bold','FontSize',12);

    for di = 1:3
        T_d = datasets{di};
        for lv = 1:5
            Tlv = T_d(T_d.level==lv,:);
            subj_u = unique(Tlv.subject);
            xs_N=[]; xs_H=[];
            for si=1:numel(subj_u)
                s=subj_u{si};
                v=Tlv.(oc)(strcmp(Tlv.subject,s)&Tlv.(oc)>0);
                if isempty(v), continue; end
                lv_mean=mean(log(v),'omitnan');
                if any(T_d.haptic(strcmp(T_d.subject,s))), xs_H(end+1)=lv_mean;
                else, xs_N(end+1)=lv_mean; end
            end
            % nexttile; hold on;
            % jN=lv-0.15+(rand(numel(xs_N),1)-0.5)*0.08;
            % jH=lv+0.15+(rand(numel(xs_H),1)-0.5)*0.08;
            % scatter(jN,xs_N,20,CN,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
            % scatter(jH,xs_H,20,CH,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
            % if numel(xs_N)>=2
            %     errorbar(lv-0.15,mean(xs_N),std(xs_N)/sqrt(numel(xs_N))*1.96,...
            %         'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,...
            %         'DisplayName',sprintf('NHF n=%d',numel(xs_N)));
            % end
            % if numel(xs_H)>=2
            %     errorbar(lv+0.15,mean(xs_H),std(xs_H)/sqrt(numel(xs_H))*1.96,...
            %         'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,...
            %         'DisplayName',sprintf('HF n=%d',numel(xs_H)));
            % end
            if di==1
                for si=1:numel(subj_u)
                    s=subj_u{si};
                    if ~ismember(s,excl), continue; end
                    v=Tlv.(oc)(strcmp(Tlv.subject,s)&Tlv.(oc)>0);
                    if isempty(v), continue; end
                    text(lv,mean(log(v),'omitnan'),strrep(s,'subject_',''),...
                        'FontSize',5,'Color',[0.6 0 0],'HorizontalAlignment','center',...
                        'VerticalAlignment','bottom');
                end
            end
            set(gca,'XTick',lv,'XTickLabel',sprintf('L%d',lv),'FontSize',8);
            ylabel(yl,'FontSize',7);
            if lv==1, title(dslabels{di},'FontSize',7,'Interpreter','none'); end
            if lv==1&&di==1, legend('FontSize',7,'Location','best'); end
            grid on; box on;
        end
    end
    exportgraphics(fig,fullfile(fig_dir,sprintf('%s_before_after_per_level.png',oc)),'Resolution',150);
    fprintf('Saved %s_before_after_per_level.png\n',oc);

    %% ── Figure 2: full timeline ──────────────────────────────────────────
    phases_ord={'Baseline1','Test1','level_L1','level_L2','level_L3','level_L4','level_L5','Baseline2','Test2'};
    xlabels_t ={'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
    n_ph=numel(phases_ord);

    % fig2=figure('Position',[50 50 1800 700]);
    % tl2=tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    % title(tl2,sprintf('%s: full timeline — RAW (top) vs CLEAN (bottom)',ttl),'FontWeight','bold','FontSize',12);

    for row_i=1:2
        T_d=local_ternary(row_i==1,T_raw,T_cln);
        row_lbl=local_ternary(row_i==1,'RAW — includes broken sensors','CLEAN — after all exclusions and outlier removal');
        mu_N=nan(1,n_ph); mu_H=nan(1,n_ph); se_N=nan(1,n_ph); se_H=nan(1,n_ph);
        % nexttile; hold on;
        for pi=1:n_ph
            ph=phases_ord{pi};
            if startsWith(ph,'level_')
                lv2=str2double(regexp(ph,'\d+','match','once'));
                Tph=T_d(strcmp(T_d.phase_type,'training')&T_d.level==lv2&isfinite(T_d.(oc))&T_d.(oc)>0,:);
            else
                Tph=T_d(strcmp(T_d.phase,ph)&isfinite(T_d.(oc))&T_d.(oc)>0,:);
            end
            if isempty(Tph), continue; end
            subj=unique(Tph.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
            for si=1:numel(subj)
                s=subj{si};
                v=Tph.(oc)(strcmp(Tph.subject,s)&Tph.(oc)>0);
                if ~isempty(v), xs(si)=mean(log(v),'omitnan'); end
                ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s)));
            end
            xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
            mu_N(pi)=mean(xN,'omitnan'); mu_H(pi)=mean(xH,'omitnan');
            se_N(pi)=std(xN,'omitnan')/sqrt(numel(xN)); se_H(pi)=std(xH,'omitnan')/sqrt(numel(xH));
            % scatter(repmat(pi-0.15,numel(xN),1)+(rand(numel(xN),1)-0.5)*0.05,...
            %     xN,10,CN,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
            % scatter(repmat(pi+0.15,numel(xH),1)+(rand(numel(xH),1)-0.5)*0.05,...
            %     xH,10,CH,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
            % if row_i==1
            %     for si=1:numel(subj)
            %         s=subj{si};
            %         if ~ismember(s,excl)||~isfinite(xs(si)), continue; end
            %         text(pi,xs(si),strrep(s,'subject_',''),'FontSize',5,'Color',[0.7 0 0],...
            %             'HorizontalAlignment','center','VerticalAlignment','bottom','FontWeight','bold');
            %     end
            % end
        end
        % x=1:n_ph;
        % fill([x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        % fill([x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        % plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',8,'DisplayName','NHF');
        % plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',8,'DisplayName','HF');
        % xline(1.5,'k:','LineWidth',1,'HandleVisibility','off'); xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
        % yall=max([mu_N+1.96*se_N mu_H+1.96*se_H],[],'omitnan');
        % text(1,yall*1.03,'Pre','FontSize',8,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
        % text(4,yall*1.03,'Training','FontSize',8,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
        % text(8,yall*1.03,'Post','FontSize',8,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
        % set(gca,'XTick',1:n_ph,'XTickLabel',xlabels_t,'FontSize',9);
        % xlabel('Phase'); ylabel(yl,'FontSize',10); legend('Location','best','FontSize',9);
        % grid on; box on; title(row_lbl,'FontSize',10,'Interpreter','none');
    end
    % exportgraphics(fig2,fullfile(fig_dir,sprintf('%s_timeline_before_after.png',oc)),'Resolution',150);
    fprintf('Saved %s_timeline_before_after.png\n',oc);

    %% ── Track shifted points: find and plot removed repetitions ──────────
    fprintf('\n=== %s: repetitions removed by p1/p99 that shift subject mean ===\n',upper(oc));

    subj_list = unique(T_tr_excl.subject);
    shifted   = {};

    for si = 1:numel(subj_list)
        s = subj_list{si};
        for lv = 1:5
            v_s2  = log(T_tr_excl.(oc)(strcmp(T_tr_excl.subject,s) & T_tr_excl.level==lv));
            v_cln = log(T_tr_cln.(oc)(strcmp(T_tr_cln.subject,s)   & T_tr_cln.level==lv));
            if isempty(v_s2), continue; end
            if abs(mean(v_s2,'omitnan')-mean(v_cln,'omitnan')) < 0.05, continue; end

            reps_s2  = T_tr_excl.repetition(strcmp(T_tr_excl.subject,s) & T_tr_excl.level==lv);
            vals_s2  = log(T_tr_excl.(oc)(strcmp(T_tr_excl.subject,s)   & T_tr_excl.level==lv));
            reps_cln = T_tr_cln.repetition(strcmp(T_tr_cln.subject,s)   & T_tr_cln.level==lv);

            rmvd_reps = reps_s2(~ismember(reps_s2, reps_cln));
            rmvd_vals = vals_s2(~ismember(reps_s2, reps_cln));

            fprintf('  %-18s L%d: mean %.3f→%.3f  removed reps: ',...
                strrep(s,'subject_',''), lv, mean(v_s2,'omitnan'), mean(v_cln,'omitnan'));
            for ri=1:numel(rmvd_reps)
                fprintf('rep%02d(log=%.2f) ', rmvd_reps(ri), rmvd_vals(ri));
            end
            fprintf('\n');
            shifted(end+1,:) = {s, lv, reps_s2, vals_s2, reps_cln, rmvd_reps, rmvd_vals}; %#ok<AGROW>
        end
    end

    if isempty(shifted)
        fprintf('  No subjects shifted by >0.05 log-units.\n'); continue;
    end

    %% Figure 3: for each shifted case show all reps with removed ones highlighted
    for ci = 1:size(shifted,1)
        s          = shifted{ci,1};
        lv         = shifted{ci,2};
        reps_s2    = shifted{ci,3};
        vals_s2    = shifted{ci,4};
        reps_cln   = shifted{ci,5};
        rmvd_reps  = shifted{ci,6};
        rmvd_vals  = shifted{ci,7};

        T_lv = T_tr_excl(strcmp(T_tr_excl.subject,s) & T_tr_excl.level==lv,:);
        T_lv = sortrows(T_lv,'repetition','ascend');
        n_reps = height(T_lv);

        fig3 = figure('Position',[50 50 1600 max(300,250*n_reps)]);
        tl3  = tiledlayout(n_reps,3,'TileSpacing','compact','Padding','compact');
        title(tl3,sprintf('%s — %s L%d: all reps (red=removed by p1/p99, blue=kept)',...
            upper(oc), strrep(s,'subject_',''), lv),'FontWeight','bold','FontSize',11);

        for ri = 1:n_reps
            row     = T_lv(ri,:);
            rmvd    = ismember(row.repetition, rmvd_reps);
            col     = local_ternary(rmvd,[0.8 0.2 0.2],[0.2 0.5 0.8]);
            rmv_str = local_ternary(rmvd,'REMOVED','kept');

            acq_dir = fullfile(cfg.data_root,s,row.phase{1},row.acquisition{1});
            if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end
            ev_path = fullfile(acq_dir,'events.mat');

            if strcmp(oc,'tssf')
                sig_path = fullfile(acq_dir,'force.mat');
            else
                sig_path = fullfile(acq_dir,'accel.mat');
            end

            title_str = sprintf('rep%02d [%s]  log=%.3f  raw=%.2e', row.repetition, rmv_str, log(row.(oc)), row.(oc));

            % if ~isfile(ev_path)||~isfile(sig_path)
            %     for k=1:3, nexttile; title(sprintf('%s — missing files',title_str),'FontSize',7,'Interpreter','none'); end
            %     continue
            % end

            [t_start,t_end] = safe_trial_window(ev_path);

            if strcmp(oc,'tssf')
                LF=load(sig_path,'FORCE'); t_f=LF.FORCE.time_rel(:); rv=LF.FORCE.data;
                bm=t_f>=(t_start-1)&t_f<t_start; if sum(bm)<3, bm=t_f<(t_f(1)+1); end
                bias=mean(rv(bm,:),1,'omitnan');
                F_cal=(C_force*(rv-bias)')';
                tm=t_f>=t_start&t_f<=t_end; t_win=t_f(tm)-t_start;
                F_trial=F_cal(tm,:);
                Fmag=sqrt(sum(F_trial(:,1:3).^2,2));
                nf=median(Fmag)+cfg.force_noise_k_mad*mad(Fmag,1);
                Fm=Fmag; Fm(Fm<nf)=0;

                % nexttile; hold on;
                % plot(t_win,F_trial(:,1),'r-','LineWidth',0.5,'DisplayName','Fx');
                % plot(t_win,F_trial(:,2),'g-','LineWidth',0.5,'DisplayName','Fy');
                % plot(t_win,F_trial(:,3),'b-','LineWidth',0.5,'DisplayName','Fz');
                % yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
                % xlabel('t(s)'); ylabel('N');
                % title(sprintf('%s\nmax_F=%.1fN mean_F=%.2fN',title_str,max(Fmag),mean(Fmag(Fmag>nf))),...
                %     'FontSize',6.5,'Interpreter','none','Color',col);
                % legend('FontSize',6,'Location','best'); grid on;
                % 
                % nexttile; hold on;
                % plot(t_win,Fmag,'Color',col,'LineWidth',0.7);
                % yline(nf,'r--','LineWidth',1.2,'DisplayName',sprintf('nf=%.2fN',nf));
                % area(t_win,Fm,'FaceColor',col,'FaceAlpha',0.2,'EdgeColor','none');
                % xlabel('t(s)'); ylabel('N');
                % title(sprintf('|F| magnitude  tssf=%.2eN²',sum(Fm.^2)),'FontSize',8);
                % legend('FontSize',6); grid on;

            else  % tssv
                LA=load(sig_path,'ACCEL'); t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal; dt=1/fs;
                rv=LA.ACCEL.data;
                bm=t_a>=(t_start-1)&t_a<t_start; if sum(bm)<3, bm=t_a<(t_a(1)+1); end
                bias=mean(rv(bm,:),1,'omitnan');
                raw_ms2=(rv-bias)*cfg.accel_sensitivity_ms2_per_V;
                tm=t_a>=t_start&t_a<=t_end; t_win=t_a(tm)-t_start;
                seg=raw_ms2(tm,:); seg_bp=seg;
                if fs/2>1000
                    [b,a_f]=butter(4,[80 1000]/(fs/2),'bandpass');
                    for c=1:6, seg_bp(:,c)=filtfilt(b,a_f,double(seg(:,c))); end
                end
                AL=sum(seg_bp(:,1:3),2); AR=sum(seg_bp(:,4:6),2);
                AL_t=AL; AR_t=AR;
                AL_t(abs(AL_t)<cfg.tssv_noise_threshold_ms2)=0;
                AR_t(abs(AR_t)<cfg.tssv_noise_threshold_ms2)=0;

                % nexttile; hold on;
                % plot(t_win,seg(:,1),'Color',[0.6 0.6 0.6],'LineWidth',0.5,'DisplayName','Lx raw');
                % xlabel('t(s)'); ylabel('m/s²');
                % title(title_str,'FontSize',6.5,'Interpreter','none','Color',col);
                % legend('FontSize',6); grid on;
                % 
                % nexttile; hold on;
                % plot(t_win,AL,'Color',col,'LineWidth',0.7,'DisplayName','Left signed sum');
                % plot(t_win,AR,'Color',col*0.6,'LineWidth',0.7,'DisplayName','Right signed sum');
                % yline( cfg.tssv_noise_threshold_ms2,'r--','LineWidth',1,'HandleVisibility','off');
                % yline(-cfg.tssv_noise_threshold_ms2,'r--','LineWidth',1,'HandleVisibility','off');
                % xlabel('t(s)'); ylabel('m/s²');
                % title(sprintf('Signed sums  tssv=%.4f',sum((AL_t+AR_t).^2)*dt),'FontSize',8);
                % legend('FontSize',6); grid on;
            end

            % Panel 3 (same for both metrics): bar chart of all reps at this level
            % nexttile; hold on;
            % bar_cols=repmat([0.75 0.75 0.75],n_reps,1);
            % for rj=1:n_reps
            %     if ismember(T_lv.repetition(rj),rmvd_reps), bar_cols(rj,:)=[0.8 0.2 0.2];
            %     elseif T_lv.repetition(rj)==row.repetition,  bar_cols(rj,:)=[0.2 0.5 0.8]; end
            % end
            % bh=bar(T_lv.repetition,log(T_lv.(oc)),0.6);
            % bh.FaceColor='flat'; bh.CData=bar_cols; bh.EdgeColor='none';
            % yline(mean(vals_s2,'omitnan'),'b--','LineWidth',1.5,...
            %     'DisplayName',sprintf('stage2 mean=%.3f',mean(vals_s2,'omitnan')));
            % yline(mean(log(T_tr_cln.(oc)(strcmp(T_tr_cln.subject,s)&T_tr_cln.level==lv)),'omitnan'),...
            %     'k--','LineWidth',1.5,'DisplayName',sprintf('clean mean=%.3f',...
            %     mean(log(T_tr_cln.(oc)(strcmp(T_tr_cln.subject,s)&T_tr_cln.level==lv)),'omitnan')));
            % xlabel('Repetition'); ylabel(sprintf('log-%s',upper(oc)));
            % title('All reps — red=removed  blue=current','FontSize',8);
            % set(gca,'XTick',T_lv.repetition); legend('FontSize',6); grid on;
        end

        fname3=sprintf('%s_shifted_%s_L%d.png',oc,strrep(s,'subject_',''),lv);
        exportgraphics(fig3,fullfile(fig_dir,fname3),'Resolution',120);
        fprintf('  Saved %s\n',fname3); close(fig3);
    end
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end