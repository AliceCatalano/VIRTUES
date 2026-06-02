function responses = analyze_gsr_cvxEDA(t_gsr,scr,scl,collision_times,...
        baseline_before,scr_window,scr_thresh,scl_start,scl_end,scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0-baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), continue; end
        baseline_scl = mean(scl(bl_mask));  responses(i).baseline = baseline_scl;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_window);
        if any(scr_mask)
            [pk,pi] = max(scr(scr_mask));  t_rel = t_gsr(scr_mask)-t0;
            if pk > scr_thresh
                responses(i).has_scr=true; responses(i).scr_latency=t_rel(pi);
                responses(i).scr_amplitude=pk; end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg = mean(scl(scl_mask))-baseline_scl;
            if abs(chg) > scl_thresh
                responses(i).has_scl=true; responses(i).scl_change=chg; end
        end
    end
end