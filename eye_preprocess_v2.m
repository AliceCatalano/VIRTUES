function eye_out = eye_preprocess_v2(eye_mat_path, cfg, t_start, t_end)
% Extended eye preprocessing: fixations, saccade amplitudes, entropy,
% pupil physiological filtering, dilation speed + local MAD outlier removal.
% Mirrors eye_preprocess.m structure exactly; saves eye_preprocessed_v2.mat.

    PUPIL_MIN = 2.0; PUPIL_MAX = 8.0;        % mm, Ong et al. 2025
    DIL_SPEED_THRESH = 3.0;                   % mm/s, surgical simulation standard
    LOCAL_MAD_WIN_S  = 2.0;                   % s, local outlier window
    LOCAL_MAD_K      = 3.0;                   % MAD multiplier
    FIX_MIN_DUR_S    = 0.100;                 % s, minimum fixation duration
    ENTROPY_GRID     = 6;                     % 6x6 spatial grid

    loaded = load(eye_mat_path,'EYE'); EYE = loaded.EYE;
    t_raw = EYE.time_rel(:); D_raw = EYE.data; ch = EYE.channel_names;

    if ~isempty(t_start)&&~isnan(t_start)&&~isempty(t_end)&&~isnan(t_end)
        win = t_raw>=t_start & t_raw<=t_end; t_raw=t_raw(win); D_raw=D_raw(win,:);
    end
    if numel(t_raw)<20, error('eye_preprocess_v2: <20 samples in window for %s',eye_mat_path); end

    n_reordered = sum(diff(t_raw)<0);
    [t,ord] = sort(t_raw); D = D_raw(ord,:);
    col = @(name) D(:,strcmp(ch,name));

    blink = col('blink')==1;
    pdl=col('pupil_diameter_left'); pdr=col('pupil_diameter_right');
    x=col('x'); y=col('y');

    dt = diff(t); max_gap = max(dt);
    if ~isfield(cfg,'eye_max_gap_s')||isempty(cfg.eye_max_gap_s), cfg.eye_max_gap_s=0.2; end
    if max_gap>cfg.eye_max_gap_s
        error('eye_preprocess_v2: dropout gap %.3fs > cfg.eye_max_gap_s (%.3fs) in %s',max_gap,cfg.eye_max_gap_s,eye_mat_path);
    end
    fs_est = 1/median(dt(dt>0));

    % Pupil: mean L/R, NaN blinks
    pupil = mean([pdl,pdr],2,'omitnan'); pupil(blink)=NaN;

    % Physiological range filter
    pupil(pupil<PUPIL_MIN|pupil>PUPIL_MAX) = NaN;

    % Dilation speed outlier removal (3mm/s threshold)
    dil_speed = [0; abs(diff(pupil)./dt)];
    pupil(dil_speed>DIL_SPEED_THRESH) = NaN;

    % Local MAD outlier removal (2s window, 3xMAD)
    win_samp = max(3,round(LOCAL_MAD_WIN_S*fs_est));
    pupil_lm = movmedian(pupil,win_samp,'omitnan');
    pupil_mad = movmad(pupil,win_samp);
    pupil(abs(pupil-pupil_lm)>LOCAL_MAD_K*pupil_mad & ~isnan(pupil_mad)) = NaN;

    n_outlier_speed = sum(dil_speed>DIL_SPEED_THRESH);
    n_outlier_local = sum(abs(pupil-pupil_lm)>LOCAL_MAD_K*pupil_mad & ~isnan(pupil_mad));

    % Gaze: NaN blinks
    xg=x; xg(blink)=NaN; yg=y; yg(blink)=NaN;

    % Valid sample fraction
    n_total = numel(t);
    pct_valid = 100*sum(~blink)/n_total;

    % Saccade detection with onset/offset/amplitude (I-VT)
    if ~isfield(cfg,'eye_saccade_k_mad')||isempty(cfg.eye_saccade_k_mad), cfg.eye_saccade_k_mad=5; end
    valid = ~blink; vi = find(valid);
    sac_times=[]; sac_offsets=[]; sac_amp=[];
    if numel(vi)>2
        dt_v=t(vi(2:end))-t(vi(1:end-1));
        dist_v=hypot(x(vi(2:end))-x(vi(1:end-1)),y(vi(2:end))-y(vi(1:end-1)));
        gate=dt_v<=3*median(dt(dt>0));
        vel=nan(size(dt_v)); vel(gate)=dist_v(gate)./dt_v(gate);
        vel_valid=vel(isfinite(vel));
        thresh=median(vel_valid,'omitnan')+cfg.eye_saccade_k_mad*mad(vel_valid,1);
        above=isfinite(vel)&vel>thresh;
        d=diff([0;above(:);0]);
        starts=find(d==1); ends_=find(d==-1)-1;
        for k=1:numel(starts)
            i0=starts(k); i1=ends_(k);
            t_on=t(vi(i0+1)); t_off=t(vi(min(i1+1,numel(vi))));
            x0=x(vi(i0+1)); y0=y(vi(i0+1));
            x1=x(vi(min(i1+1,numel(vi)))); y1=y(vi(min(i1+1,numel(vi))));
            sac_times(end+1)=t_on; %#ok<AGROW>
            sac_offsets(end+1)=t_off; %#ok<AGROW>
            sac_amp(end+1)=hypot(x1-x0,y1-y0); %#ok<AGROW>
        end
    end
    sac_times=sac_times(:); sac_offsets=sac_offsets(:); sac_amp=sac_amp(:);

    % Fixation detection: periods of low velocity >= FIX_MIN_DUR_S
    fix_times=[]; fix_offsets=[]; fix_dur=[];
    if numel(vi)>2
        not_sac = ~above; d2=diff([0;not_sac(:);0]);
        fstarts=find(d2==1); fends=find(d2==-1)-1;
        for k=1:numel(fstarts)
            i0=fstarts(k); i1=fends(k);
            t_on=t(vi(min(i0+1,numel(vi)))); t_off=t(vi(min(i1+1,numel(vi))));
            dur=t_off-t_on;
            if dur>=FIX_MIN_DUR_S
                fix_times(end+1)=t_on; %#ok<AGROW>
                fix_offsets(end+1)=t_off; %#ok<AGROW>
                fix_dur(end+1)=dur; %#ok<AGROW>
            end
        end
    end
    fix_times=fix_times(:); fix_offsets=fix_offsets(:); fix_dur=fix_dur(:);

    % Gaze entropy (6x6 grid, coordinate-range normalised)
    xv=xg(isfinite(xg)&isfinite(yg)); yv=yg(isfinite(xg)&isfinite(yg));
    gaze_entropy=NaN;
    if numel(xv)>10
        xe=linspace(min(xv),max(xv),ENTROPY_GRID+1);
        ye=linspace(min(yv),max(yv),ENTROPY_GRID+1);
        H_grid=histcounts2(xv,yv,xe,ye); H_grid=H_grid(:)/sum(H_grid(:));
        H_grid=H_grid(H_grid>0);
        gaze_entropy=-sum(H_grid.*log2(H_grid));
    end

    % Valid duration
    valid_dur = sum(dt(~blink(1:end-1)&~blink(2:end)));

    eye_out.time           = t;
    eye_out.pupil          = pupil;
    eye_out.x              = xg;
    eye_out.y              = yg;
    eye_out.blink          = blink;
    eye_out.fs_est         = fs_est;
    eye_out.n_reordered    = n_reordered;
    eye_out.pct_valid      = pct_valid;
    eye_out.n_outlier_speed= n_outlier_speed;
    eye_out.n_outlier_local= n_outlier_local;
    eye_out.saccade_times  = sac_times;
    eye_out.saccade_offsets= sac_offsets;
    eye_out.saccade_amp    = sac_amp;
    eye_out.fixation_times = fix_times;
    eye_out.fixation_offsets=fix_offsets;
    eye_out.fixation_dur   = fix_dur;
    eye_out.gaze_entropy   = gaze_entropy;
    eye_out.valid_duration_s=valid_dur;
    eye_out.source         = eye_mat_path;

    save(fullfile(fileparts(eye_mat_path),'eye_preprocessed_v2.mat'),'eye_out');
end