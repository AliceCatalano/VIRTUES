function responses = analyze_gsr_raw(t_gsr,gsr_raw,collision_times,...
        baseline_before,scr_window,scr_thresh,scl_start,scl_end,scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0-baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), continue; end
        bl_mean = mean(gsr_raw(bl_mask)); responses(i).baseline = bl_mean;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_window);
        if any(scr_mask)
            seg=gsr_raw(scr_mask); t_rel=t_gsr(scr_mask)-t0;
            [mn,mi]=min(seg); amp=bl_mean-mn;
            if amp > scr_thresh
                responses(i).has_scr=true; responses(i).scr_latency=t_rel(mi);
                responses(i).scr_amplitude=amp; end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg=bl_mean-mean(gsr_raw(scl_mask));
            if abs(chg) > scl_thresh
                responses(i).has_scl=true; responses(i).scl_change=chg; end
        end
    end
end