function gsr_col = get_gsr_col(gsr)
    if     ismember('GSR_ohm',                gsr.Properties.VariableNames), gsr_col='GSR_ohm';
    elseif ismember('GSR_Skin_Resistance_CAL',gsr.Properties.VariableNames), gsr_col='GSR_Skin_Resistance_CAL';
    else,  error('No GSR column found.'); end
end
