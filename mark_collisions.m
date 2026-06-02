function mark_collisions(times)
    for i = 1:numel(times)
        xline(times(i),'r-','LineWidth',1,'HandleVisibility','off'); end
end