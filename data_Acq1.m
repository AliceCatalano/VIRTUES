clear;
%% Record data


clearvars;  
d = daq("ni");
ch1=addinput(d,"cDAQ1Mod1","ai1","Voltage");% right arm X signal
ch2=addinput(d,"cDAQ1Mod1","ai2","Voltage");% right arm Y signal
ch3=addinput(d,"cDAQ1Mod1","ai3","Voltage");% right arm Z signal
ch4=addinput(d,"cDAQ1Mod1","ai4","Voltage");% left arm X signal
ch5=addinput(d,"cDAQ1Mod1","ai5","Voltage");% left arm Y signal
ch6=addinput(d,"cDAQ1Mod1","ai6","Voltage");% left arm Z signal
ch1.TerminalConfig = 'SingleEnded';
ch2.TerminalConfig = 'SingleEnded';
ch3.TerminalConfig = 'SingleEnded';
ch4.TerminalConfig = 'SingleEnded';
ch5.TerminalConfig = 'SingleEnded';
ch6.TerminalConfig = 'SingleEnded';


d.Rate = 10000;
global data timestamps
data = [];
timestamps = [];

d.ScansAvailableFcnCount = 1000;       % Callback every 1000 scans
d.ScansAvailableFcn = @(src, evt) collectData(src,evt);    % Function to call when triggered

keepGoing = true;
while keepGoing
    data=[];
    timestamps=[];
    
    input("Press Enter to START recording...", 's');
    disp("Recording...");
    start(d, 'continuous');  % Start DAQ
    input("Press Enter to STOP recording...", 's');
    stop(d);
    disp("Recording stopped.");
     
    filename = input("Enter filename to save (without extension): ", 's');
    
      % default timestamped name 
    save(['C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test' num2str(filename) '.mat'],'data','timestamps');
    disp(" Recording saved");
       x1 = data(:,1);
       y1 = data(:,2);
       z1 = data(:,3);
      
       x2 = data(:,4);
       y2 = data(:,5);
       z2 = data(:,6);
       sum1= x1+y1+z1;
       sum2= x2+y2+z2;
       fprintf("Length of data: %d samples\n", length(data));

       dt = mean(diff(timestamps));      % average sample spacing
       Fs_est = 1/dt;           % estimated sampling frequency
       t2= 0:1/Fs_est:(length(data)-1)/Fs_est;
       fprintf("Estimated Fs: %.2f Hz\n", Fs_est);

       figure(1);
       plot(t2, data);
       title("Raw data");
       xlabel("Time (s)");
       ylabel("Normalized Audio Amplitude (V)");
       legend("AI1", "AI2", "AI3","AI4", "AI5", "AI6");

        figure(2);
        subplot(2,1,1)
        plot(t2, sum1);
        title(" sum  data upper connector");
        xlabel("Time (s)");
        ylabel("Normalized Audio Amplitude (V)");
        figure(2);
        subplot(2,1,2)
        plot(t2, sum2);
        title(" sum  data lower connector");
        xlabel("Time (s)");
        ylabel("Normalized Audio Amplitude (V)");

    answ = input("Do you want to record again? (y/n): ", 's');
    if lower(answ) ~= 'y'
        keepGoing = false;
    end
end   
 function collectData(src, ~)
    global data timestamps
    [dataChunk, timestampsChunk] = read(src, src.ScansAvailableFcnCount, "OutputFormat", "Matrix");
    % Append to global variables
    data = [data; dataChunk];
    timestamps = [timestamps; timestampsChunk];
end

 
    

%% sum and plot data 
Fs=10000;
x1 = data(:,1);
y1 = data(:,2);
z1 = data(:,3);
x2 = data(:,4);
y2 = data(:,5);
z2 = data(:,6);
sum1= x1+y1+z1;
sum2= x2+y2+z2;

FilteredData1 = bandpass(sum1 ,[20  1000],Fs);
FilteredData2 = bandpass(sum2 ,[20  1000],Fs);
[Sum1fft,freq1] = positiveFFT(sum1,Fs);
[Sum2fft,freq2] = positiveFFT(sum2,Fs);



figure(1);

plot(t2, data);
title("Raw data");
xlabel("Time (s)");
ylabel("Normalized Audio Amplitude (V)");
legend("AI1", "AI2", "AI3","AI4", "AI5", "AI6");

figure(2);
subplot(6,1,1)
plot(t2, sum1);
title(" sum  data upper connector");
xlabel("Time (s)");
ylabel("Normalized Audio Amplitude (V)");

subplot(6,1,2)
plot(t2, FilteredData1);
title("Filtered data of  X1, Y1, Z1(upper connector");
xlabel("Time (s)");
ylabel("Normalized Audio Amplitude (V)");

subplot(6,1,3)
plot(freq1,abs(Sum1fft))
title("FFT of  X1, Y1, Z1")
xlim([0.1,1000]);
xlabel('Frequency(Hz)');
ylabel('Sum FFT');

subplot(6,1,4)
plot(t2, sum2);
title("sum data lower connector");
xlabel("Time (s)");
ylabel("Normalized Audio Amplitude (V)");

subplot(6,1,5)
plot(t2, FilteredData2);
title("Filtered data of   X2, Y2, Z2");
xlabel("Time (s)");
ylabel("Normalized Audio Amplitude (V)");

subplot(6,1,6)
plot(freq2,abs(Sum2fft))
title("FFT of  X2, Y2, Z2")
xlim([0.1,1000]);
xlabel('Frequency(Hz)');
ylabel('Sum FFT');





%% reload data
clc
%batch_to_load = 6; 
filename ="C:\Users\hkumar\NI_DAQ\testtest0004_square.mat";
load( filename, 'data', 'timestamps');
% Load raw data

