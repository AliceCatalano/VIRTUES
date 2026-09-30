function [F_cal, bias] = apply_force_calibration(raw_V, t_rel, C, bias_dur_s)
% Applies ATI calibration matrix to 6-channel raw voltage data.
%
% Inputs:
%   raw_V      : [n_samples x 6] raw voltages from force.mat
%   t_rel      : [n_samples x 1] time vector (s), relative to trial start
%   C          : [6 x 6] calibration matrix from load_ati_cal()
%   bias_dur_s : duration (s) of quiet period at start used for bias estimate
%                (default 0.5 s — use pre-trial window if available)
%
% Outputs:
%   F_cal : [n_samples x 6]  [Fx Fy Fz Tx Ty Tz]  in N and N·m
%   bias  : [1 x 6] bias voltage vector

    if nargin < 4 || isempty(bias_dur_s), bias_dur_s = 0.5; end

    bias_mask = t_rel >= t_rel(1) & t_rel <= t_rel(1) + bias_dur_s;
    if sum(bias_mask) < 3
        warning('apply_force_calibration: fewer than 3 samples in bias window — using first sample.');
        bias = raw_V(1,:);
    else
        bias = mean(raw_V(bias_mask,:), 1, 'omitnan');
    end

    V_biased = raw_V - bias;          % remove DC offset / gravity / preload
    F_cal    = (C * V_biased')';      % [n x 6]
end