function add_event_lines(event_times)
    for i = 1:numel(event_times)
        xline(event_times(i),'k--','LineWidth',0.8,'HandleVisibility','off'); end
end