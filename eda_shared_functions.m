function [t_out, eda_uS, fs] = prepare_eda(t_raw, gsr_raw, gsr_unit, ma_win_sec)
    t_raw   = double(t_raw(:));
    gsr_raw = double(gsr_raw(:));
    bad     = ~isfinite(gsr_raw) | gsr_raw <= 0;
    if mean(bad) > 0.5, t_out=[]; eda_uS=[]; fs=NaN; return; end
    idx = (1:numel(gsr_raw))';
    if any(bad)
        gsr_raw = interp1(idx(~bad), gsr_raw(~bad), idx, 'linear','extrap');
        gsr_raw(gsr_raw <= 0) = min(gsr_raw(~bad));
    end
    dt = diff(t_raw); dt = dt(dt>0);
    if isempty(dt), t_out=[]; eda_uS=[]; fs=NaN; return; end
    fs    = 1/median(dt);
    t_out = t_raw - t_raw(1);
    if strcmp(gsr_unit,'ohm'), eda_uS = 1e6./gsr_raw;
    else,                      eda_uS = 1000./gsr_raw; end
    eda_uS = movmean(eda_uS, max(3, round(fs*ma_win_sec)), 'omitnan');
end

function y = robust_detrend(x)
    x     = double(x(:));
    t     = (1:numel(x))';
    med_t = median(t); med_x = median(x);
    slope = median((x-med_x)./(t-med_t+eps));
    y     = x - (slope*t + (med_x - slope*med_t));
end

function [phasic, tonic, method] = decompose_eda(eda_z, fs, use_cvx)
    phasic=[]; tonic=[]; method='';
    if use_cvx
        yn = double(eda_z(:));
        for si = 1:3
            sv_list={'quadprog','sedumi',''}; sv=sv_list{si};
            try
                if isempty(sv), [~,p,tc,~,~,~,~]=cvxEDA(yn,1/fs);
                else,           [~,p,tc,~,~,~,~]=cvxEDA(yn,1/fs,0.7,1.0,1.0,8e-5,1e-2,sv); end
                phasic=p(:); tonic=tc(:); method=sprintf('cvxEDA(%s)',sv); return
            catch, end
        end
    end
    try
        [phasic,tonic]=nndeconv_eda(eda_z,fs); method='NNDeconv'; return
    catch, end
    [b,a]=butter(2,0.05/(fs/2),'low');
    tonic=filtfilt(b,a,double(eda_z)); phasic=double(eda_z)-tonic; method='HPF';
end

function [phasic, tonic] = nndeconv_eda(y, fs)
    y=double(y(:)); n=numel(y);
    t_kern=(0:round(10*fs))'/fs;
    h=exp(-t_kern/1.5)-exp(-t_kern/0.7); h=h/max(abs(h));
    H=spdiags(repmat(h',n,1),0:numel(h)-1,n,n)'; H=H(1:n,1:n);
    x=zeros(n,1); lr=1/(norm(H'*H,1)+eps);
    for iter=1:500
        grad=H'*(H*x-y)+0.01; x=max(x-lr*grad,0);
        if mod(iter,50)==0 && norm(grad)<1e-6, break; end
    end
    phasic=H*x; tonic=movmean(max(y-phasic,0),max(3,round(fs*4)));
end

function tf = trial_features(t, tonic, phasic, fs, k_mad, min_dist_sec, min_amp)
    tf.scl_mean        = mean(tonic,  'omitnan');
    tf.scl_median      = median(tonic,'omitnan');
    valid              = isfinite(tonic);
    pp                 = polyfit(t(valid), tonic(valid), 1);
    tf.scl_slope       = pp(1);
    tf.scr_driver_mean = mean(phasic, 'omitnan');
    tf.scr_integrated  = trapz(t, max(phasic,0));
    [~,pt,pa]          = detect_scr_peaks(t,phasic,fs,k_mad,min_dist_sec,min_amp);
    tf.scr_n_peaks     = numel(pt);
    tf.scr_mean_amp    = mean(pa,'omitnan');
    tf.scr_max_amp     = max(pa,[],'omitnan');
    thresh             = median(phasic,'omitnan')+k_mad*mad(phasic,1);
    tf.scr_active_frac = mean(phasic>thresh,'omitnan');
    tf.duration_s      = t(end)-t(1);
    tf.fs_hz           = fs;
end

function [peaks, peak_times, peak_amps] = detect_scr_peaks(t, phasic, fs, k_mad, min_dist_sec, min_amp)
    thresh=median(phasic,'omitnan')+k_mad*mad(phasic,1);
    min_dist=round(min_dist_sec*fs);
    above=phasic>max(thresh,min_amp);
    d=diff([0;above(:);0]); starts=find(d==1); ends_=find(d==-1)-1;
    if isempty(starts), peaks=[]; peak_times=[]; peak_amps=[]; return; end
    ci=zeros(numel(starts),1); ca=zeros(numel(starts),1);
    for i=1:numel(starts)
        [mx,li]=max(phasic(starts(i):ends_(i)));
        ci(i)=starts(i)+li-1; ca(i)=mx;
    end
    keep=true(size(ci));
    for i=1:numel(ci)
        if ~keep(i), continue; end
        for j=i+1:numel(ci)
            if ~keep(j), continue; end
            if ci(j)-ci(i)<min_dist
                if ca(j)>=ca(i), keep(i)=false; else, keep(j)=false; end
            else, break; end
        end
    end
    peaks=ci(keep); peak_times=t(peaks); peak_amps=ca(keep);
end

function [t_gsr, gsr_vals] = load_gsr(folder)
    t_gsr=[]; gsr_vals=[];
    f=fullfile(folder,'gsr.csv');
    if ~isfile(f), return; end
    try
        T=readtable(f);
        if height(T)>5, T(1:5,:)=[]; end
        if ismember('pc_time',T.Properties.VariableNames)
            t_gsr=T.pc_time;
        elseif ismember('recording_time',T.Properties.VariableNames)
            t_gsr=T.recording_time;
        else, return; end
        if ismember('GSR_ohm',T.Properties.VariableNames)
            gsr_vals=T.GSR_ohm;
        elseif ismember('GSR_Skin_Resistance_CAL',T.Properties.VariableNames)
            gsr_vals=T.GSR_Skin_Resistance_CAL;
        end
    catch, end
end

function subj_folders = scan_subjects(base_folder)
    d=dir(fullfile(base_folder,'subject_s*'));
    d=d([d.isdir]);
    subj_folders={d.name};
end

function plot_eda_panel(t, eda_uS, tonic, phasic, panel_title)
    hold on;
    plot(t,eda_uS,'Color',[0.75 0.75 0.75],'LineWidth',0.6,'DisplayName','µS');
    plot(t,tonic,'b','LineWidth',1.4,'DisplayName','SCL');
    plot(t,phasic,'r','LineWidth',0.9,'DisplayName','SCR');
    ylabel('µS/z'); title(panel_title,'FontSize',8,'Interpreter','none');
    legend('Location','northeast','FontSize',6); grid on;
end

function plot_group_summary(results, phase_label, save_path)
    feats  = {'scl_mean','scl_slope','scr_n_peaks','scr_integrated','scr_active_frac'};
    titles = {'SCL mean','SCL slope','N peaks','Integrated AUC','Active fraction'};
    mods   = unique(results.subj_mod);
    clrs   = lines(numel(mods));

    fig=figure('Name',sprintf('GROUP — %s',phase_label),'Position',[50 50 1600 800]);
    sgtitle(sprintf('Group EDA  |  %s',phase_label),'FontWeight','bold','FontSize',12);

    for f=1:numel(feats)
        subplot(2,ceil(numel(feats)/2),f); hold on;
        if ~ismember(feats{f},results.Properties.VariableNames), continue; end
        for m=1:numel(mods)
            mask=strcmp(results.subj_mod,mods{m});
            vals=results.(feats{f})(mask); vals=vals(isfinite(vals));
            if isempty(vals), continue; end
            boxplot(vals,'Positions',m,'Width',0.5,'Colors',clrs(m,:));
            jit=(rand(numel(vals),1)-0.5)*0.15;
            scatter(m+jit,vals,25,clrs(m,:),'filled','MarkerFaceAlpha',0.5);
        end
        set(gca,'XTick',1:numel(mods),'XTickLabel',mods);
        ylabel(titles{f}); title(titles{f},'FontSize',9); grid on;
    end
    saveas(fig,fullfile(save_path,sprintf('GROUP_%s.png',phase_label)));
end

function plot_level_profile(results, save_path)
    feats  = {'scl_mean','scl_slope','scr_n_peaks','scr_integrated','scr_active_frac'};
    titles = {'SCL mean','SCL slope','N peaks','Integrated AUC','Active fraction'};
    levels = unique(results.level(isfinite(results.level)));
    mods   = unique(results.subj_mod);
    clrs   = lines(numel(mods));

    fig=figure('Name','BASELINE level profile','Position',[50 50 1600 800]);
    sgtitle('Baseline EDA across Levels','FontWeight','bold','FontSize',12);

    for f=1:numel(feats)
        subplot(2,ceil(numel(feats)/2),f); hold on;
        if ~ismember(feats{f},results.Properties.VariableNames), continue; end
        for m=1:numel(mods)
            mu=nan(numel(levels),1); sem=nan(numel(levels),1);
            for li=1:numel(levels)
                mask=strcmp(results.subj_mod,mods{m}) & results.level==levels(li);
                vals=results.(feats{f})(mask); vals=vals(isfinite(vals));
                if numel(vals)<2, continue; end
                mu(li)=mean(vals); sem(li)=std(vals)/sqrt(numel(vals));
            end
            errorbar(levels,mu,sem,'-o','Color',clrs(m,:),'LineWidth',1.4,...
                'MarkerFaceColor',clrs(m,:),'DisplayName',mods{m});
        end
        xlabel('Level'); ylabel(titles{f}); title(titles{f},'FontSize',9);
        legend('Location','best','FontSize',7); grid on;
    end
    saveas(fig,fullfile(save_path,'BASELINE_level_profile.png'));
end