%gsr = readtable('/home/acatalano/VIRTUES/test_session/session_2025-11-11_14-31-24/gsr.csv');
neon = readtable('/home/acatalano/VIRTUES/test_session/session_2025-11-27_17-01-35/eye.csv');
events = readtable('/home/acatalano/VIRTUES/test_session/session_2025-11-27_17-01-35/events.csv');
%%
left_raw = neon.pupil_diameter_left;
right_raw = neon.pupil_diameter_right;
filteredSignRight = movmean(right_raw, 100);
filteredSignLeft = movmean(left_raw, 100);

plot(neon.pc_timestamp, filteredSignRight); hold on;
plot(neon.pc_timestamp,filteredSignLeft); 
xline(events.recording_time, 'r')
%%
t0 = neon.recording_time(1);

plot(neon.recording_time - t0, filteredSignRight); hold on;
plot(neon.recording_time - t0, filteredSignLeft); hold on;

event_times_norm = events- t0;

for t = event_times_norm'
    xline(t, 'r', 'LineWidth', 1.5);
end
%%
time = diff(neon.timestamp_unix_seconds);
figure;
plot(time);
%%
timepc = diff(neon.pc_timestamp);
figure;
plot(timepc);
%%

timegsr = diff(gsr.timestamp);
figure;
plot(timegsr);

%%

timegsrpc = diff(gsr.pc_time);
figure;
plot(timegsrpc);