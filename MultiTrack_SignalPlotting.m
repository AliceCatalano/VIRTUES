clear;
%%

s_folderdir = './';
info_folders = dir(fullfile(s_folderdir, '00*.')); 
num_folders = length(info_folders);

    for j = 1: num_folders
   % for j = 12: 15
        matfiles = dir([s_folderdir info_folders(j).name '/*.flac']);
        nfiles = length(matfiles);
        data  = cell(1,nfiles);

        for i = 1 : nfiles
            signal = audioread([s_folderdir info_folders(j).name '/' matfiles(i).name]);
            data{i} = signal; 
        end
        datain = cell2mat(data);
        datainre = resample(datain,10,48);
        formatSpec = 'T%d_inre.mat';
        fileID = sprintf(formatSpec,j);
        outputpath = s_folderdir;
        save(fullfile(outputpath,fileID), 'datainre','-v7.3');

        
    end
%%
clear;


 %% SingleEnded
keepGoing = true;
while keepGoing
clear;
close all;
tasknumber = input("Enter the tasknumber to run ");
switch(tasknumber)
      case 1
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T1_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0001_static.mat";
       disp("Action: Static");
      case 2
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T2_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0002_static.mat";
       disp("Action: Static");
      case 3
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T3_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0003_square.mat";
       disp("Action: Tracing a Square");
      case 4
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T4_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0004_tracing.mat";
       disp("Action: Tracing a square and free hand ");
      case 5
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T5_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0005_tracing.mat";
        disp("Action: Tracing a square and free hand ");
      case 6
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T6_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0006_contact.mat";
        disp("Action: Contact");
      case 7
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T7_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0007_contact.mat";
        disp("Action: Contact");
      case 8
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T8_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0008_contact.mat";
        disp("Action: Contact");
      case 9
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T9_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0009_contact.mat";
        disp("Action: Contact");
      case 10
       signal = load("C:\Users\hkumar\NI_DAQ\Multitrack_0903\T10_inre.mat");
       filename ="C:\Users\hkumar\NI_DAQ\Multitrack_0903\DAQ_DATA0903\test0010_contact.mat";
        disp("Action: Contact");

end

mixer_signal = signal.datainre;      
load( filename, 'data', 'timestamps');
Fs=10000; fs=Fs;
daq_data=data;
x1 =  mixer_signal(:,1);
y1=  mixer_signal(:,2);
z1 =  mixer_signal(:,3);
x2 =  mixer_signal(:,4);
y2 =  mixer_signal(:,5);
z2 =  mixer_signal(:,6);
% g conversion

sum1_mixer= x1+y1+z1;
sum2_mixer= x2+y2+z2;

sum1_mixer = sum1_mixer - sum1_mixer(1); 
sum2_mixer = sum2_mixer - sum2_mixer(1);

%t1= 0:1/Fs:(length( mixer_signal)-1)/Fs;

filtereddata1_mixer = [bandpass(sum1_mixer ,[20  1000],Fs)] /0.4;
filtereddata2_mixer = [bandpass(sum2_mixer ,[20  1000],Fs)]/0.4;
[sum1_mixerfft,freq1] = positiveFFT(filtereddata1_mixer,Fs);
[sum2_mixerfft,freq2] = positiveFFT(filtereddata2_mixer,Fs);


% raw data of DAQ

%t2=0:1/Fs:(length(data)-1)/Fs;
X1 = daq_data(:,1); % upper acc
Y1 = daq_data(:,2); % upper acc
Z1 = daq_data(:,3); % upper acc
X2 = daq_data(:,4); % lower acc m1 x
Y2 = daq_data(:,5); % lower acc m2 y
Z2 = daq_data(:,6); % lower acc m3  z

Sum1_daq= X1+Y1+Z1;
Sum2_daq= X2+Y2+Z2;

Sum1_daq = Sum1_daq - Sum1_daq(1);
Sum2_daq= Sum2_daq- Sum2_daq(1);

FilteredData1_daq = [bandpass(Sum1_daq ,[20  1000],Fs)]/0.4 ;
FilteredData2_daq = [bandpass(Sum2_daq ,[20  1000],Fs)]/0.4;

[Sum1_daqfft,Freq1] = positiveFFT(FilteredData1_daq,Fs);
[Sum2_daqfft,Freq2] = positiveFFT(FilteredData2_daq,Fs);


% Extracting common segments
min_length = min(length(mixer_signal), length(daq_data));
t1= (0:min_length-1) / Fs;
t2= (0:min_length-1) / Fs;
mixer_common = mixer_signal(1:min_length, :);
sum1_mixer_common = sum1_mixer(1:min_length);
sum2_mixer_common = sum2_mixer(1:min_length);
filtereddata1_mixer_common = filtereddata1_mixer(1:min_length);
filtereddata2_mixer_common = filtereddata2_mixer(1:min_length);

daq_common = daq_data(1:min_length, :);
Sum1_daq_common = Sum1_daq(1:min_length);
Sum2_daq_common = Sum2_daq(1:min_length);
FilteredData1_daq_common = FilteredData1_daq(1:min_length);
FilteredData2_daq_common = FilteredData2_daq(1:min_length);
  


% Aligning the collected data between the mixer and DAQ

 switch tasknumber
        
     case 3
        m=t2>0.4; 
        t2=t2(m)- t2(find(m,1));
        Sum1_daq_common  = Sum1_daq_common  (m);
        Sum2_daq_common  = Sum2_daq_common  (m);
        FilteredData1_daq_common  = FilteredData1_daq_common  (m);
        FilteredData2_daq_common  =FilteredData2_daq_common  (m);
      case 4
        m=t1>0.13;
        t1=t1(m)- t1(find(m,1));
        sum1_mixer_common= sum1_mixer_common(m);
        sum2_mixer_common= sum2_mixer_common(m);
        filtereddata1_mixer_common= filtereddata1_mixer_common(m);
        filtereddata2_mixer_common=filtereddata2_mixer_common(m);
        t2_new = t2;
        t2_new(t2 > 40.05) = t2_new(t2 > 40.05) - 0.05;
        m1 = (t2 < 40) | (t2 > 40.05);
        t2=t2_new(m1);
        Sum1_daq_common  = Sum1_daq_common  (m1);
        Sum2_daq_common  = Sum2_daq_common  (m1);
        FilteredData1_daq_common  = FilteredData1_daq_common  (m1);
        FilteredData2_daq_common  =FilteredData2_daq_common  (m1);
     case 5
        m=t2>0.7138; 
        t2=t2(m)- t2(find(m,1));
        Sum1_daq_common  = Sum1_daq_common  (m);
        Sum2_daq_common = Sum2_daq_common (m);
        FilteredData1_daq_common = FilteredData1_daq_common (m);
        FilteredData2_daq_common =FilteredData2_daq_common (m);
     case 6
         m=t1>0.14;
        t1=t1(m)- t1(find(m,1));
        sum1_mixer_common= sum1_mixer_common(m);
        sum2_mixer_common= sum2_mixer_common(m);
        filtereddata1_mixer_common= filtereddata1_mixer_common(m);
        filtereddata2_mixer_common=filtereddata2_mixer_common(m);
     case 7
         m=t1>0.1;
        t1=t1(m)- t1(find(m,1));
        sum1_mixer_common= sum1_mixer_common(m);
        sum2_mixer_common= sum2_mixer_common(m);
        filtereddata1_mixer_common= filtereddata1_mixer_common(m);
        filtereddata2_mixer_common=filtereddata2_mixer_common(m);
     case 8
           m=t1>0.3223;
        t1=t1(m)- t1(find(m,1));
        sum1_mixer_common= sum1_mixer_common(m);
        sum2_mixer_common= sum2_mixer_common(m);
        filtereddata1_mixer_common= filtereddata1_mixer_common(m);
        filtereddata2_mixer_common=filtereddata2_mixer_common(m);
      case 9
         m=t1>0.2564;
        t1=t1(m)- t1(find(m,1));
        sum1_mixer_common= sum1_mixer_common(m);
        sum2_mixer_common= sum2_mixer_common(m);
        filtereddata1_mixer_common= filtereddata1_mixer_common(m);
        filtereddata2_mixer_common=filtereddata2_mixer_common(m);
       
 end


% plotting of signals


figure(2);
subplot(6,1,1)
grid on;
plot( t1,sum1_mixer_common);
ylim([-1,1]);
title(" sum  data upper connector MIXEER");
xlabel("Time (s)");
ylabel("Voltage (V)");

subplot(6,1,2)
plot(t1,filtereddata1_mixer_common);
%xlim([0,xlimvalue]);
title("Filtered data of  X1, Y1, Z1(upper connector) MIXER");
ylim([-1.4,1.4]);
xlabel("Time (s)");
ylabel("Acc (g)");

subplot(6,1,3)
plot(freq1,abs(sum1_mixerfft))
title("FFT of  X1, Y1, Z1") ;
xlim([0.0,1000]);
ylim([0.0,0.0015]);
xlabel('Frequency(Hz)');
ylabel('Sum FFT');

subplot(6,1,4)
plot( t2,Sum1_daq_common );
%xlim([0,xlimvalue]);
ylim([-1,1]);
title(" sum  data upper connector DAQ");
xlabel("Time (s)");
ylabel("Voltage (V)");

subplot(6,1,5)
plot(t2,FilteredData1_daq_common );
title("Filtered data of  X1, Y1, Z1(upper connector) DAQ");
ylim([-1.4,1.4]);
% xlim([0,xlimvalue]);
xlabel("Time (s)");
ylabel("Acc (g)");

subplot(6,1,6)
plot(Freq1,abs(Sum1_daqfft));
ylim([0.0,0.0015]);
xlim([0.0,1000]);
title("FFT of  X1, Y1, Z1 DAQ")
xlabel('Frequency(Hz)');
ylabel('Sum FFT');

figure(4);
subplot(6,1,1)
plot( t1,sum2_mixer_common);
title("sum data lower connector MIXER");
% xlim([0,xlimvalue]);
ylim([-1,1]);
xlabel("Time (s)");
ylabel("Voltage (V)");

subplot(6,1,2)
plot(t1, filtereddata2_mixer_common);
title("Filtered data of   X2, Y2, Z2  MIXER");
%xlim([0,xlimvalue]);
ylim([-1.4,1.4]);
xlabel("Time (s)");
ylabel("Acc (g)");

subplot(6,1,3)
plot(freq2,abs(sum2_mixerfft))
title("FFT of  X2, Y2, Z2 MIXER")
xlim([0.0,1000]);
ylim([0.0,0.0015]);
xlabel('Frequency(Hz)');
ylabel('Sum FFT');

subplot(6,1,4)
plot( t2,Sum2_daq_common );
title("sum data lower connector DAQ");
% xlim([0,xlimvalue]);
ylim([-1,1]);
xlabel("Time (s)");
ylabel("Voltage (V)");

subplot(6,1,5)
plot(t2, FilteredData2_daq_common );
title("Filtered data of   X2, Y2, Z2 DAQ");
% xlim([0,xlimvalue]);
ylim([-1.4,1.4]);
xlabel("Time (s)");
ylabel("Acc (g)");

subplot(6,1,6)
plot(Freq2,abs(Sum2_daqfft))
title("FFT of  X2, Y2, Z2 DAQ")
xlim([0.0,1000]);
ylim([0.0,0.0015]);
xlabel('Frequency(Hz)');
ylabel('Sum FFT');

 answ = input("Do you want to display a new set again? (y/n): ", 's');
    if lower(answ) ~= 'y'
        keepGoing = false;
    end
end  