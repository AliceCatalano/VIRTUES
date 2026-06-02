function add_events_differentiated(kb_times, start_times, end_times)
% Keyboard events  : dark blue dashed line
% TRIAL_START      : solid green  (thick)
% TRIAL_END        : solid orange (thick)
    for t = kb_times(:)'
        xline(t,'--','Color',[0.15 0.15 0.7],'LineWidth',0.8,'HandleVisibility','off');
    end
    for t = start_times(:)'
        xline(t,'-','Color',[0 0.7 0],'LineWidth',2.0,...
            'Label','START','LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
    for t = end_times(:)'
        xline(t,'-','Color',[0.9 0.5 0],'LineWidth',2.0,...
            'Label','END','LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
end