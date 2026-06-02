function [sig_ds,t_ds] = antialias_downsample(sig,t,fs_in,fs_out,order,ds_factor)
    Wn = min(fs_out/2*0.9/(fs_in/2),0.99);
    [b,a] = butter(order,Wn,'low');
    sig_filt = filtfilt(b,a,double(sig));
    n_ds = floor(numel(sig_filt)/ds_factor);
    sig_ds = zeros(n_ds,1);  t_ds = zeros(n_ds,1);
    for k = 1:n_ds
        idx = (k-1)*ds_factor+1:k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx));  t_ds(k) = t(idx(1));
    end
end