function times = detect_peaks(drv,t,threshold,min_dist_smp)
    above = drv > threshold;
    edges = find(diff([0;above])==1);
    if isempty(edges), times=[]; return; end
    keep = true(size(edges));
    for i = 1:numel(edges)
        if ~keep(i), continue; end
        for j = i+1:numel(edges)
            if ~keep(j), continue; end
            if edges(j)-edges(i) < min_dist_smp
                if drv(edges(j)) > drv(edges(i)), keep(i)=false; else, keep(j)=false; end
            else, break; end
        end
    end
    times = t(edges(keep));
end