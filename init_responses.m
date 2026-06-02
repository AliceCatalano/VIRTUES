function r = init_responses(n)
    r = struct('has_scr',false,'scr_latency',NaN,'scr_amplitude',NaN,...
               'has_scl',false,'scl_change',NaN,'baseline',NaN);
    if n > 0, r = repmat(r,n,1); end
end