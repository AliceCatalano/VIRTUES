function lbl = get_gsr_label(gsr)
    if contains(get_gsr_col(gsr),'CAL'), lbl='GSR (kOhm)'; else, lbl='GSR (Ohm)'; end
end
