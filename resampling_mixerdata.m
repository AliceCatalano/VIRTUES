clc;
close all;
clear;

%% 
clear;
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
    close all;

%%% Acceleration 
% when transmitter 0, min box, 0-20-0 mixer

tasknumber = 1;   %%%%%%% from 5 to 30, check Test1022. pptx
s_folderdir = "/home/acatalano/VIRTUES";
info_file = dir(fullfile(s_folderdir, '*re.mat')); 
filepath = fullfile(s_folderdir, info_file(tasknumber).name);
signal1 = load(filepath);   
signal = signal1.datainre;   


Fs = 10000;
x = signal(:,1) ; % acc
y = signal(:,2) ;
z = signal(:,3) ;
ignalsumori = x + y + z;
signalsum = bandpass(signalsumori,[20  1000],Fs);
t1= 0:1/Fs:(length(signal)-1)/Fs;  
dt=1/Fs;
[Sumfft,freq1] = positiveFFT(signalsum,Fs);
figure('Name', 'Mixer Raw data 10g ');

switch tasknumber  

    case 1
        x1limvalue =  7;
        ylimsaudio = [-0.2 0.2];
     case 2
         x1limvalue = 7;
        ylimsaudio = [-0.2 0.2];
    case 3
        x1limvalue =  52.2123;
        ylimsaudio = [-0.15 0.15];
end
subplot(6,1,1)
plot(t1,x);
 title("Mixer X-axis data");
xlabel("Time (s)");
ylabel("Mixer X-axis Audio");
xlim([0 x1limvalue])
ylim(ylimsaudio);
subplot(6,1,2)
plot(t1,y);
 title("Mixer Y-axis data");
xlabel("Time (s)");
ylabel("Mixer Y-axis Audio");
xlim([0 x1limvalue])
ylim(ylimsaudio);
subplot(6,1,3)
plot(t1,z);
title("Mixer Z-axis data");
xlabel("Time (s)");
ylabel("Mixer Z-axis Audio");
xlim([0 x1limvalue])
ylim(ylimsaudio);
subplot(6,1,4)
plot(t1,signalsum);
title("Mixer sum data");
xlabel("Time (s)");
ylabel("Mixer Sum Audio");
xlim([0 x1limvalue])
ylim(ylimsaudio);
subplot(6,1,5)
[S2,F2,T2,P2] = spectrogram(signalsum,200,100,512,Fs);
surf(T2, F2/1000, 10*log10(abs(P2)), 'edgecolor','none');
axis tight
view(0,90)
ylim([00 1])
clim([-80 -30]) %%% -140 -70
ylabel({'Perceived';'Freq. (kHz)'})
colorbar east
xlabel('Time (s)');
box off
cb = colorbar('Location', 'east', 'Color', 'white');
subplot(6,1,6)
plot(freq1,abs(Sumfft));
xlim([0.1,1000]);
xlabel('Frequency (Hz)');
ylabel('Sum Filtered FFT');
set(gcf,'position',[1,1,2048,1152])
% linkaxes([ax1 ax2 ax3 ax4],'xy')
