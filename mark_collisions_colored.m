function mark_collisions_colored(times,sources)
    src_colors = {[0.2 0.4 0.9],[0.6 0.1 0.6],[0.1 0.6 0.1]};
    for i = 1:numel(times)
        col = src_colors{min(sources(i),3)};
        xline(times(i),'-','Color',col,'LineWidth',1.5,'HandleVisibility','off'); 
    end
end