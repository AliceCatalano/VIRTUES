gsr = readtable('/home/acatalano/VIRTUES/test_session/session_2025-11-11_14-31-24/gsr.csv');
neon = readtable('/home/acatalano/VIRTUES/test_session/session_2025-11-11_14-31-24/eye.csv');
%%
left_raw = neon.pupil_diameter_left;
right_raw = neon.pupil_diameter_right;
filteredSignRight = movmean(right_raw, 100);
filteredSignLeft = movmean(left_raw, 100);
plot(filteredSignRight); hold on;
plot(filteredSignLeft);
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