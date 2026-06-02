function plot_accel_6panel(t,x,y,z,t_force,force_mag,event_times,Fs,bp_lo,bp_hi,fig_title)
    xbp = bandpass(x,[bp_lo bp_hi],Fs);  ybp = bandpass(y,[bp_lo bp_hi],Fs);
    zbp = bandpass(z,[bp_lo bp_hi],Fs);  sumbp = xbp+ybp+zbp;
    [SPEC_f,freq] = positiveFFT(sumbp,Fs);
    figure('Name',fig_title,'Position',[50 50 1400 1100]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);
    ax1=subplot(6,1,1); plot(t,xbp,'Color',[0.8 0.1 0.1],'LineWidth',0.6);
    ylabel('X (g)'); title('X axis (bandpassed)'); grid on; add_event_lines(event_times);
    ax2=subplot(6,1,2); plot(t,ybp,'Color',[0.1 0.6 0.1],'LineWidth',0.6);
    ylabel('Y (g)'); title('Y axis (bandpassed)'); grid on; add_event_lines(event_times);
    ax3=subplot(6,1,3); plot(t,zbp,'Color',[0.1 0.2 0.8],'LineWidth',0.6);
    ylabel('Z (g)'); title('Z axis (bandpassed)'); grid on; add_event_lines(event_times);
    ax4=subplot(6,1,4); plot(t,sumbp,'Color',[0.5 0 0.7],'LineWidth',0.6);
    ylabel('Sum (g)'); title('Sum X+Y+Z (bandpassed)'); grid on; add_event_lines(event_times);
    ax5=subplot(6,1,5); plot(freq,abs(SPEC_f),'k','LineWidth',0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|'); title('Spectrum of Sum'); grid on; xlim([0 Fs/2]);
    ax6=subplot(6,1,6); plot(t_force,force_mag,'Color',[0.5 0 0.5],'LineWidth',0.8);
    ylabel('|Force| (V)'); title('Force magnitude (downsampled)'); grid on; add_event_lines(event_times);
    linkaxes([ax1 ax2 ax3 ax4 ax6],'x');  xlabel(ax6,'Time (s)');
end