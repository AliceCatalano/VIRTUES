function [scr_thresh,scl_thresh] = compute_gsr_thresholds_raw(gsr_raw,scr_sens,scl_sens)
    delta_fast = abs(diff(gsr_raw));
    scr_thresh = max(median(delta_fast)+scr_sens*mad(delta_fast,1),1.0);
    gsr_smooth = movmean(gsr_raw,max(3,round(numel(gsr_raw)*0.01)));
    delta_slow = abs(diff(gsr_smooth));
    scl_thresh = max(median(delta_slow)+scl_sens*mad(delta_slow,1),0.5);
end