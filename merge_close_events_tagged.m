function [merged_times,merged_source] = merge_close_events_tagged(tagged,window)
    if isempty(tagged), merged_times=[]; merged_source=[]; return; end
    merged_times=tagged(1,1); merged_source=tagged(1,2);
    for i = 2:size(tagged,1)
        if tagged(i,1)-merged_times(end) <= window
            if merged_source(end) ~= tagged(i,2), merged_source(end)=3; end
        else
            merged_times  = [merged_times;  tagged(i,1)]; %#ok<AGROW>
            merged_source = [merged_source; tagged(i,2)]; %#ok<AGROW>
        end
    end
end
