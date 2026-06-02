function mark_trial(t_start,t_end)
    if ~isnan(t_start)
        xline(t_start,'-','Color',[0 0.7 0],'LineWidth',2.5,...
            'Label','TRIAL START','LabelVerticalAlignment','bottom','HandleVisibility','off'); 
    end
    if ~isnan(t_end)
        xline(t_end,'-','Color',[0.9 0.5 0],'LineWidth',2.5,...
            'Label','TRIAL END','LabelVerticalAlignment','bottom','HandleVisibility','off'); 
    end
end