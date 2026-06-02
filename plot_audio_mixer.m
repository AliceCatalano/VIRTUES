function plot_audio_mixer(audio,channels,fs_audio,bp_lo,bp_hi,event_times,fig_title)
    nch = numel(channels);  n_panels = nch+2;
    figure('Name',fig_title,'Position',[60 60 1600 min(200*n_panels,1400)]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);
    ax = gobjects(n_panels,1);  clrs = lines(nch);
    sum_bp = zeros(height(audio),1);
    for k = 1:nch
        ch = channels{k};  raw = double(audio.(ch));
        raw = raw - mean(raw,'omitnan');
        if numel(raw) > 10*fs_audio, raw_bp = bandpass(raw,[bp_lo bp_hi],fs_audio);
        else, raw_bp = raw; end
        sum_bp = sum_bp + raw_bp;
        ax(k)=subplot(n_panels,1,k);
        plot(audio.t,raw_bp,'Color',clrs(k,:),'LineWidth',0.5);
        ylabel('V'); title(sprintf('%s (bandpassed %d–%d Hz)',ch,bp_lo,bp_hi));
        grid on; add_event_lines(event_times);
    end
    ax(nch+1)=subplot(n_panels,1,nch+1);
    plot(audio.t,sum_bp,'Color',[0.2 0.2 0.8],'LineWidth',0.8);
    ylabel('V'); title(sprintf('Mixer sum (all %d channels, bandpassed)',nch));
    grid on; add_event_lines(event_times);
    ax(nch+2)=subplot(n_panels,1,nch+2);
    [Sfft,freqs]=positiveFFT(sum_bp,fs_audio);
    plot(freqs,abs(Sfft),'k','LineWidth',0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|'); title('Spectrum of mixer sum');
    xlim([0 min(fs_audio/2,2000)]); grid on;
    linkaxes(ax(1:nch+1),'x');  xlabel(ax(nch+1),'Time (s)');
end