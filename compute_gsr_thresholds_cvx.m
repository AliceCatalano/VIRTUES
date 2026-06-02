function [scr_thresh,scl_thresh] = compute_gsr_thresholds_cvx(p_cvx,t_cvx,scr_sens,scl_sens)
    abs_p = abs(p_cvx);
    scr_thresh = max(median(abs_p)+scr_sens*mad(abs_p,1),1e-4);
    delta_scl  = abs(diff(t_cvx));
    scl_thresh = max(median(delta_scl)+scl_sens*mad(delta_scl,1),1e-4);
end