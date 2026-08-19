%% frequencyFeaturesExtraction.m
%  Reads EXISTING collision_results.mat files for a list of subjects,
%  across all phases/acquisitions. For each collision timestamp, goes
%  back into the FULL nominal-rate accel.mat / audio.mat data (or the
%  cached processed_signals.mat, if available) and computes frequency-
%  domain / impulsiveness features — plus saves diagnostic plots.
%
%  OUTPUT per acquisition (only if collision_results.mat exists with
%  n_collisions > 0):
%    frequency_features.mat        - feature table (does NOT touch
%                                     collision_results.mat)
%    freq_plots/overview.png       - full-trial waveform + spectrogram,
%                                     both pipelines, collisions marked
%    freq_plots/gallery_niq*.png   - grid of per-collision spectrograms
%                                     (NIDAQ pipeline)
%    freq_plots/gallery_aud*.png   - same, audio-mixer pipeline (optional)
%    freq_plots/feature_trends.png - hf_ratio/crest/kurtosis/centroid
%                                     plotted across all collisions

clear; clc; close all;

%% SECTION 0 — SUBJECTS TO PROCESS
SUBJECTS_TO_RUN = {'subject_s40H'};   % edit as needed

%% SECTION 1 — FIXED PARAMETERS
BASE_FOLDER = '~/Desktop/Virtues_Data';

FREQ_WIN_SEC = 0.15;   % ± half-window around each collision (s)
HF_CUTOFF    = 20;     % Hz — approx. upper bound of voluntary-movement bandwidth

% ---- Plotting controls ----
SAVE_PLOTS           = true;    % master switch — set false to skip all plotting
PLOT_OVERVIEW        = true;    % full-trial waveform + spectrogram
PLOT_GALLERY_NIQ     = true;    % per-collision spectrogram grid, NIDAQ pipeline
PLOT_GALLERY_AUD     = false;   % same, audio-mixer pipeline (slower, more files)
PLOT_FEATURE_TRENDS  = true;    % per-collision feature line plots

GALLERY_MAX_PER_FIG  = 25;      % split into multiple pages if more collisions than this
SPEC_FMAX_NIQ        = 500;     % Hz — display ceiling for NIDAQ spectrograms
SPEC_FMAX_AUD        = 2000;    % Hz — display ceiling for audio-pipeline spectrograms
OVERVIEW_SPEC_WIN_SEC = 0.05;   % spectrogram window length for the full-trial overview
PLOT_DPI             = 130;

allPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};

base = expanduser(BASE_FOLDER);

fprintf('\n=== frequencyFeaturesExtraction — BATCH MODE ===\n');
fprintf('Subjects to process (%d): %s\n\n', numel(SUBJECTS_TO_RUN), strjoin(SUBJECTS_TO_RUN, ', '));

%% SECTION 2 — LOOP OVER SUBJECTS
for subjIdx = 1:numel(SUBJECTS_TO_RUN)

    subjFolderName = SUBJECTS_TO_RUN{subjIdx};
    SUBJECT = erase(subjFolderName, 'subject_');
    subj_folder = fullfile(base, subjFolderName);

    if ~isfolder(subj_folder)
        fprintf('# SUBJECT: %s — FOLDER NOT FOUND, SKIPPING\n', SUBJECT);
        continue;
    end

    report_file = fullfile(subj_folder, sprintf('FreqFeaturesReport_%s.txt', SUBJECT));
    if strcmp(get(0,'Diary'), 'on'), diary off; end
    if isfile(report_file), delete(report_file); end
    diary(report_file);
    diary on;

    fprintf('# SUBJECT: %s\n', SUBJECT);

    subjTotalColl    = 0;
    subjTotalAcqDone = 0;
    subjTotalSkipped = 0;

    try
        for pIdx = 1:numel(allPhases)

            PHASE = allPhases{pIdx};
            phase_folder = fullfile(subj_folder, PHASE);

            if ~isfolder(phase_folder)
                fprintf('--- Skipping phase "%s" (folder not found) ---\n\n', PHASE);
                continue;
            end

            fprintf(' PHASE: %s\n', PHASE);

            if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
                acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
            else
                acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
            end

            for aIdx = 1:numel(acquisitions)

                ACQUISITION = acquisitions{aIdx};
                acq_folder  = fullfile(phase_folder, ACQUISITION);

                if ~isfolder(acq_folder)
                    continue;   % acquisition doesn't exist — nothing to process
                end

                collision_file = fullfile(acq_folder, 'collision_results.mat');
                accel_file     = fullfile(acq_folder, 'accel.mat');
                audio_file     = fullfile(acq_folder, 'audio.mat');
                proc_file      = fullfile(acq_folder, 'processed_signals.mat');

                if ~isfile(collision_file)
                    continue;   % no detection results yet — nothing to do
                end

                try
                    %% ---- LOAD EXISTING COLLISION RESULTS ----
                    R = load(collision_file, 'results');
                    coll_t = R.results.collision_rel(:);
                    t_ws   = R.results.t_win_start;
                    t_we   = R.results.t_win_end;

                    if isempty(coll_t)
                        fprintf('  [skip] %s — 0 collisions in saved results\n', ACQUISITION);
                        subjTotalSkipped = subjTotalSkipped + 1;
                        continue;
                    end

                    %% ---- LOAD SIGNALS (cached if available, else compute) ----
                    if isfile(proc_file)
                        P = load(proc_file, 'proc'); proc = P.proc;
                        t_niq    = proc.t_niq;
                        ACCEL_FS = proc.ACCEL_FS;
                        mag_nat  = proc.mag_nat;
                        t_aud    = proc.t_aud;
                        fs_audio = proc.fs_audio;
                        audio_bb = proc.audio_bb;
                    else
                        if ~isfile(accel_file) || ~isfile(audio_file)
                            fprintf('  [skip] %s — no cache and accel/audio.mat missing\n', ACQUISITION);
                            subjTotalSkipped = subjTotalSkipped + 1;
                            continue;
                        end

                        A = load(accel_file); ACCEL = A.ACCEL;
                        U = load(audio_file); AUDIO = U.AUDIO;

                        t_niq    = ACCEL.time_rel;
                        ACCEL_FS = ACCEL.fs_nominal;

                        N_BASELINE = 50;
                        V2G        = 1 / 0.4;
                        accel_raw  = ACCEL.data;

                        xL = baseline_and_scale(accel_raw(:,1), N_BASELINE, V2G);
                        yL = baseline_and_scale(accel_raw(:,2), N_BASELINE, V2G);
                        zL = baseline_and_scale(accel_raw(:,3), N_BASELINE, V2G);
                        xR = baseline_and_scale(accel_raw(:,4), N_BASELINE, V2G);
                        yR = baseline_and_scale(accel_raw(:,5), N_BASELINE, V2G);
                        zR = baseline_and_scale(accel_raw(:,6), N_BASELINE, V2G);

                        mag_nat = max(sqrt(xL.^2+yL.^2+zL.^2), sqrt(xR.^2+yR.^2+zR.^2));

                        t_aud    = AUDIO.time_rel;
                        fs_audio = AUDIO.fs_estimated;
                        ch_names = AUDIO.channel_names;

                        known_new = {'ch11','ch12','ch13','ch14','ch16','ch17'};
                        known_old = {'ch12','ch13','ch14','ch16','ch17','ch18'};
                        idx_new   = find(ismember(ch_names, known_new));
                        idx_old   = find(ismember(ch_names, known_old));
                        if numel(idx_new) >= numel(idx_old)
                            audio_ch_idx = idx_new;
                        else
                            audio_ch_idx = idx_old;
                        end
                        if isempty(audio_ch_idx)
                            audio_ch_idx = 1:size(AUDIO.data, 2);
                        end

                        audio_raw = double(AUDIO.data(:, audio_ch_idx));
                        audio_bb  = max(abs(audio_raw - mean(audio_raw, 1, 'omitnan')), [], 2);
                    end

                    %% ---- PER-COLLISION FREQUENCY FEATURES (inline) ----
                    half_win_niq = round(FREQ_WIN_SEC * ACCEL_FS);
                    half_win_aud = round(FREQ_WIN_SEC * fs_audio);

                    n_coll = numel(coll_t);

                    niq_centroid  = nan(n_coll,1); niq_hf_ratio  = nan(n_coll,1);
                    niq_peak_freq = nan(n_coll,1); niq_flatness  = nan(n_coll,1);
                    niq_kurt      = nan(n_coll,1); niq_crest     = nan(n_coll,1);

                    aud_centroid  = nan(n_coll,1); aud_hf_ratio  = nan(n_coll,1);
                    aud_peak_freq = nan(n_coll,1); aud_flatness  = nan(n_coll,1);
                    aud_kurt      = nan(n_coll,1); aud_crest     = nan(n_coll,1);

                    % Keep raw (unwindowed) segments for plotting later
                    segN_all = cell(n_coll,1);
                    segA_all = cell(n_coll,1);

                    for ci = 1:n_coll

                        %  NIDAQ segment (full nominal rate) ---
                        [~, iN] = min(abs(t_niq - coll_t(ci)));
                        rangeN  = max(1, iN-half_win_niq) : min(numel(mag_nat), iN+half_win_niq);
                        segN    = double(mag_nat(rangeN));
                        segN    = segN(:) - mean(segN, 'omitnan');
                        nN      = numel(segN);
                        segN_all{ci} = segN;

                        if nN >= 8 && ~all(segN==0) && ~any(isnan(segN))
                            wN     = hann(nN);
                            segN_w = segN .* wN;

                            kN   = 0:nN-1;
                            TN   = nN/ACCEL_FS;
                            fN   = (kN/TN)';
                            XN   = fft(segN_w)/nN*2;
                            cutN = ceil(nN/2);
                            XN   = XN(1:cutN);
                            fN   = fN(1:cutN);

                            PxxN = abs(XN).^2;
                            PxxN(PxxN<=0) = eps;

                            niq_centroid(ci)  = sum(fN .* PxxN) / sum(PxxN);
                            niq_hf_ratio(ci)  = sum(PxxN(fN >= HF_CUTOFF)) / sum(PxxN);
                            [~, ipkN]         = max(PxxN);
                            niq_peak_freq(ci) = fN(ipkN);
                            niq_flatness(ci)  = exp(mean(log(PxxN))) / mean(PxxN);
                            niq_kurt(ci)      = kurtosis(segN);
                            niq_crest(ci)     = max(abs(segN)) / (rms(segN) + eps);
                        end

                        %% --- Audio-pipeline segment (full native rate) ---
                        [~, iA] = min(abs(t_aud - coll_t(ci)));
                        rangeA  = max(1, iA-half_win_aud) : min(numel(audio_bb), iA+half_win_aud);
                        segA    = double(audio_bb(rangeA));
                        segA    = segA(:) - mean(segA, 'omitnan');
                        nA      = numel(segA);
                        segA_all{ci} = segA;

                        if nA >= 8 && ~all(segA==0) && ~any(isnan(segA))
                            wA     = hann(nA);
                            segA_w = segA .* wA;

                            kA   = 0:nA-1;
                            TA   = nA/fs_audio;
                            fA   = (kA/TA)';
                            XA   = fft(segA_w)/nA*2;
                            cutA = ceil(nA/2);
                            XA   = XA(1:cutA);
                            fA   = fA(1:cutA);

                            PxxA = abs(XA).^2;
                            PxxA(PxxA<=0) = eps;

                            aud_centroid(ci)  = sum(fA .* PxxA) / sum(PxxA);
                            aud_hf_ratio(ci)  = sum(PxxA(fA >= HF_CUTOFF)) / sum(PxxA);
                            [~, ipkA]         = max(PxxA);
                            aud_peak_freq(ci) = fA(ipkA);
                            aud_flatness(ci)  = exp(mean(log(PxxA))) / mean(PxxA);
                            aud_kurt(ci)      = kurtosis(segA);
                            aud_crest(ci)     = max(abs(segA)) / (rms(segA) + eps);
                        end
                    end

                    freqTable = table(coll_t, ...
                        niq_centroid, niq_hf_ratio, niq_peak_freq, niq_flatness, niq_kurt, niq_crest, ...
                        aud_centroid, aud_hf_ratio, aud_peak_freq, aud_flatness, aud_kurt, aud_crest, ...
                        'VariableNames', {'t', ...
                            'niq_spectral_centroid','niq_hf_power_ratio','niq_peak_freq', ...
                            'niq_spectral_flatness','niq_kurtosis','niq_crest_factor', ...
                            'aud_spectral_centroid','aud_hf_power_ratio','aud_peak_freq', ...
                            'aud_spectral_flatness','aud_kurtosis','aud_crest_factor'});

                    %% ---- SAVE FEATURES (new file — collision_results.mat untouched) ----
                    freq_out.subject      = SUBJECT;
                    freq_out.phase        = PHASE;
                    freq_out.acquisition  = ACQUISITION;
                    freq_out.acq_folder   = acq_folder;
                    freq_out.n_collisions = n_coll;
                    freq_out.freq_win_sec = FREQ_WIN_SEC;
                    freq_out.hf_cutoff_hz = HF_CUTOFF;
                    freq_out.accel_fs     = ACCEL_FS;
                    freq_out.audio_fs     = fs_audio;
                    freq_out.features     = freqTable;
                    freq_out.save_time    = datetime('now');

                    out_file = fullfile(acq_folder, 'frequency_features.mat');
                    save(out_file, 'freq_out');

                    %% ---- PLOTS ----
                    if SAVE_PLOTS
                        plots_folder = fullfile(acq_folder, 'freq_plots');
                        if ~isfolder(plots_folder), mkdir(plots_folder); end

                        if PLOT_OVERVIEW
                            in_trial_niq = t_niq >= t_ws & t_niq <= t_we;
                            in_trial_aud = t_aud >= t_ws & t_aud <= t_we;
                            build_overview_figure( ...
                                fullfile(plots_folder, 'overview.png'), ...
                                SUBJECT, PHASE, ACQUISITION, ...
                                t_niq(in_trial_niq), mag_nat(in_trial_niq), ...
                                t_aud(in_trial_aud), audio_bb(in_trial_aud), ...
                                coll_t, ACCEL_FS, fs_audio, ...
                                SPEC_FMAX_NIQ, SPEC_FMAX_AUD, OVERVIEW_SPEC_WIN_SEC, PLOT_DPI);
                        end

                        if PLOT_GALLERY_NIQ
                            build_collision_gallery( ...
                                fullfile(plots_folder, 'gallery_niq.png'), ...
                                SUBJECT, PHASE, ACQUISITION, ...
                                segN_all, ACCEL_FS, coll_t, SPEC_FMAX_NIQ, ...
                                GALLERY_MAX_PER_FIG, 'NIDAQ', PLOT_DPI);
                        end

                        if PLOT_GALLERY_AUD
                            build_collision_gallery(fullfile(plots_folder, 'gallery_aud.png'), ...
                                SUBJECT, PHASE, ACQUISITION, ...
                                segA_all, fs_audio, coll_t, SPEC_FMAX_AUD, ...
                                GALLERY_MAX_PER_FIG, 'Audio-pipeline', PLOT_DPI);
                        end

                        if PLOT_FEATURE_TRENDS
                            build_feature_trends_figure(fullfile(plots_folder, 'feature_trends.png'), ...
                                SUBJECT, PHASE, ACQUISITION, freqTable, PLOT_DPI);
                        end
                    end

                    fprintf('  %-10s : n=%2d collisions  |  niq_hf[min/max]=%.2f/%.2f  |  aud_hf[min/max]=%.2f/%.2f  →  saved\n', ...
                        ACQUISITION, n_coll, ...
                        min(niq_hf_ratio), max(niq_hf_ratio), ...
                        min(aud_hf_ratio), max(aud_hf_ratio));

                    subjTotalColl    = subjTotalColl + n_coll;
                    subjTotalAcqDone = subjTotalAcqDone + 1;

                catch ME
                    fprintf('  [ERROR] %s — %s (skipping this acquisition)\n', ACQUISITION, ME.message);
                    subjTotalSkipped = subjTotalSkipped + 1;
                    continue;
                end

            end % acquisition loop

            fprintf('\n');

        end % phase loop

        fprintf(' SUBJECT SUMMARY — %s\n', SUBJECT);
        fprintf('   Acquisitions processed : %d\n', subjTotalAcqDone);
        fprintf('   Acquisitions skipped   : %d\n', subjTotalSkipped);
        fprintf('   Total collisions       : %d\n', subjTotalColl);

    catch ME
        fprintf('\n[ERROR] Subject %s stopped early: %s\n', SUBJECT, ME.message);
        for kk = 1:numel(ME.stack)
            fprintf('    at %s (line %d)\n', ME.stack(kk).name, ME.stack(kk).line);
        end
    end

    diary off;
    fprintf('[REPORT SAVED] → %s\n\n', report_file);

end % subject loop

fprintf('# BATCH COMPLETE — %d subject(s) processed\n', numel(SUBJECTS_TO_RUN));


%% LOCAL FUNCTIONS 

function p = expanduser(p)
    if startsWith(p,'~')
        home = char(java.lang.System.getProperty('user.home'));
        p    = [home, p(2:end)];
    end
end

function ch = baseline_and_scale(raw, n_base, V2G)
    n_bl = min(n_base, numel(raw));
    ch   = (raw - mean(raw(1:n_bl))) * V2G;
end

%% ---------------- PLOTTING ----------------

function build_overview_figure(save_path, SUBJECT, PHASE, ACQUISITION, ...
        t_niq_trial, mag_trial, t_aud_trial, audio_trial, ...
        coll_t, ACCEL_FS, fs_audio, SPEC_FMAX_NIQ, SPEC_FMAX_AUD, ...
        spec_win_sec, PLOT_DPI)

    if numel(t_niq_trial) < 8 || numel(t_aud_trial) < 8
        return;   % trial window too short/invalid — skip plotting
    end

    fig = figure('Visible','off','Units','normalized','Position',[0 0 1 1]);

    % ---- NIDAQ time series ----
    ax1 = subplot(2,2,1);
    plot(ax1, t_niq_trial, mag_trial, 'Color',[0.2 0.45 0.8]); hold(ax1,'on');
    for ci = 1:numel(coll_t)
        xline(ax1, coll_t(ci), 'r--', 'HandleVisibility','off');
    end
    title(ax1, 'NIDAQ accel magnitude (full nominal rate)');
    xlabel(ax1,'time (s)'); ylabel(ax1,'g'); grid(ax1,'on');

    % ---- NIDAQ spectrogram ----
    ax2 = subplot(2,2,2);
    winN = max(16, round(spec_win_sec * ACCEL_FS));
    novN = round(winN * 0.5);
    nfftN = max(512, 2^nextpow2(winN*4));
    sigN = mag_trial - mean(mag_trial,'omitnan');
    [S,F,T] = spectrogram(sigN, winN, novN, nfftN, ACCEL_FS);
    imagesc(ax2, T + t_niq_trial(1), F, 20*log10(abs(S)+eps));
    set(ax2,'YDir','normal'); ylim(ax2, [0, min(SPEC_FMAX_NIQ, ACCEL_FS/2)]);
    colormap(ax2,'jet'); colorbar(ax2); hold(ax2,'on');
    for ci = 1:numel(coll_t)
        xline(ax2, coll_t(ci), 'w--', 'LineWidth',1, 'HandleVisibility','off');
    end
    title(ax2, sprintf('NIDAQ spectrogram (fs=%.0f Hz)', ACCEL_FS));
    xlabel(ax2,'time (s)'); ylabel(ax2,'Hz');

    % ---- Audio-pipeline time series ----
    ax3 = subplot(2,2,3);
    plot(ax3, t_aud_trial, audio_trial, 'Color',[0.6 0.2 0.6]); hold(ax3,'on');
    for ci = 1:numel(coll_t)
        xline(ax3, coll_t(ci), 'r--', 'HandleVisibility','off');
    end
    title(ax3, 'Audio-pipeline broadband signal (full native rate)');
    xlabel(ax3,'time (s)'); ylabel(ax3,'a.u.'); grid(ax3,'on');

    % ---- Audio-pipeline spectrogram ----
    ax4 = subplot(2,2,4);
    winA = max(16, round(spec_win_sec * fs_audio));
    novA = round(winA * 0.5);
    nfftA = max(1024, 2^nextpow2(winA*4));
    sigA = audio_trial - mean(audio_trial,'omitnan');
    [SA,FA,TA] = spectrogram(sigA, winA, novA, nfftA, fs_audio);
    imagesc(ax4, TA + t_aud_trial(1), FA, 20*log10(abs(SA)+eps));
    set(ax4,'YDir','normal'); ylim(ax4, [0, min(SPEC_FMAX_AUD, fs_audio/2)]);
    colormap(ax4,'jet'); colorbar(ax4); hold(ax4,'on');
    for ci = 1:numel(coll_t)
        xline(ax4, coll_t(ci), 'w--', 'LineWidth',1, 'HandleVisibility','off');
    end
    title(ax4, sprintf('Audio-pipeline spectrogram (fs=%.0f Hz)', fs_audio));
    xlabel(ax4,'time (s)'); ylabel(ax4,'Hz');

    linkaxes([ax1 ax2 ax3 ax4], 'x');

    sgtitle(fig, sprintf('%s | %s | %s — trial overview (%d collisions)', ...
        SUBJECT, PHASE, ACQUISITION, numel(coll_t)), 'FontWeight','bold');

    exportgraphics(fig, save_path, 'Resolution', PLOT_DPI);
    close(fig);
end

function build_collision_gallery(save_path, SUBJECT, PHASE, ACQUISITION, ...
        seg_all, fs, coll_t, fmax, max_per_fig, pipeline_label, PLOT_DPI)

    n = numel(seg_all);
    if n == 0, return; end

    n_per_fig = min(max_per_fig, n);
    n_figs = ceil(n / n_per_fig);

    for pgIdx = 1:n_figs
        idxStart = (pgIdx-1)*n_per_fig + 1;
        idxEnd   = min(n, pgIdx*n_per_fig);
        idxRange = idxStart:idxEnd;
        nThis = numel(idxRange);

        ncols = min(5, nThis);
        nrows = ceil(nThis / ncols);

        fig = figure('Visible','off','Units','normalized','Position',[0 0 1 1]);
        for kk = 1:nThis
            ci = idxRange(kk);
            ax = subplot(nrows, ncols, kk);
            titleStr = sprintf('#%d  t=%.2fs', ci, coll_t(ci));
            plot_spectrogram_tile(ax, seg_all{ci}, fs, fmax, titleStr);
        end

        sgtitle(fig, sprintf('%s | %s | %s — %s collision spectrograms (page %d/%d)', ...
            SUBJECT, PHASE, ACQUISITION, pipeline_label, pgIdx, n_figs), ...
            'FontWeight','bold','FontSize',10);

        if n_figs > 1
            this_save = strrep(save_path, '.png', sprintf('_page%02d.png', pgIdx));
        else
            this_save = save_path;
        end
        exportgraphics(fig, this_save, 'Resolution', PLOT_DPI);
        close(fig);
    end
end

function plot_spectrogram_tile(ax, seg, fs, fmax, titleStr)
    seg = seg(:);
    n = numel(seg);

    if n < 8 || all(seg==0) || any(isnan(seg))
        text(ax, 0.5, 0.5, 'N/A', 'HorizontalAlignment','center');
        axis(ax,'off'); title(ax, titleStr, 'FontSize',7);
        return;
    end

    win = max(8, min(64, floor(n/4)));
    nov = round(win * 0.75);
    nfft = max(256, 2^nextpow2(win*4));

    try
        [S,F,T] = spectrogram(seg, win, nov, nfft, fs);
    catch
        text(ax, 0.5, 0.5, 'N/A', 'HorizontalAlignment','center');
        axis(ax,'off'); title(ax, titleStr, 'FontSize',7);
        return;
    end

    imagesc(ax, T, F, 20*log10(abs(S)+eps));
    set(ax,'YDir','normal');
    ylim(ax, [0, min(fmax, fs/2)]);
    colormap(ax, 'jet');
    title(ax, titleStr, 'FontSize', 7);
    set(ax, 'FontSize', 6);
end

function build_feature_trends_figure(save_path, SUBJECT, PHASE, ACQUISITION, freqTable, PLOT_DPI)

    fig = figure('Visible','off','Units','normalized','Position',[0.1 0.1 0.8 0.8]);

    subplot(2,2,1);
    plot(freqTable.t, freqTable.niq_hf_power_ratio, '-o','Color',[0.85 0.18 0.08]); hold on;
    plot(freqTable.t, freqTable.aud_hf_power_ratio, '-s','Color',[0.2 0.45 0.8]);
    legend('NIDAQ','Audio-pipeline','Location','best');
    title('High-frequency power ratio (>20Hz)'); xlabel('time (s)'); ylabel('ratio'); grid on;

    subplot(2,2,2);
    plot(freqTable.t, freqTable.niq_crest_factor, '-o','Color',[0.85 0.18 0.08]); hold on;
    plot(freqTable.t, freqTable.aud_crest_factor, '-s','Color',[0.2 0.45 0.8]);
    legend('NIDAQ','Audio-pipeline','Location','best');
    title('Crest factor (peak/RMS)'); xlabel('time (s)'); ylabel('crest'); grid on;

    subplot(2,2,3);
    plot(freqTable.t, freqTable.niq_kurtosis, '-o','Color',[0.85 0.18 0.08]); hold on;
    plot(freqTable.t, freqTable.aud_kurtosis, '-s','Color',[0.2 0.45 0.8]);
    legend('NIDAQ','Audio-pipeline','Location','best');
    title('Kurtosis (impulsiveness)'); xlabel('time (s)'); ylabel('kurtosis'); grid on;

    subplot(2,2,4);
    plot(freqTable.t, freqTable.niq_spectral_centroid, '-o','Color',[0.85 0.18 0.08]); hold on;
    plot(freqTable.t, freqTable.aud_spectral_centroid, '-s','Color',[0.2 0.45 0.8]);
    legend('NIDAQ','Audio-pipeline','Location','best');
    title('Spectral centroid'); xlabel('time (s)'); ylabel('Hz'); grid on;

    sgtitle(fig, sprintf('%s | %s | %s — per-collision feature trends', ...
        SUBJECT, PHASE, ACQUISITION), 'FontWeight','bold');

    exportgraphics(fig, save_path, 'Resolution', PLOT_DPI);
    close(fig);
end