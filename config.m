function cfg = config()
    cfg.data_root   = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
    cfg.output_root = fullfile(expanduser('~'), 'Desktop/Virtues_Data', 'GSR_Analysis');
    
    raw_list = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H','s16N','s18N','s20N','s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N', ...
                's42N','s43N','s44N','s46N','s48N', 's03H','s04H','s06H','s08H','s10H','s12H','s13H','s17H','s19H','s21H', ...
                's23H','s25H','s26H','s29H','s31H','s33H','s35H','s38H','s40H','s41H', 's45H','s47H'};
    
    cfg.all_subjects = cellfun(@(s) ['subject_' s], raw_list, 'UniformOutput', false);
    
    cfg.subjects_H = cfg.all_subjects(cellfun(@(s) s(end) == 'H', cfg.all_subjects));
    cfg.subjects_N = cfg.all_subjects(cellfun(@(s) s(end) == 'N', cfg.all_subjects));
    
    cfg.fs_target        = 10;
    cfg.scr_min_amp      = 0.01;
    cfg.scr_min_dist     = 10;
    
    cfg.baseline_phases  = {'Baseline1','Baseline2'};
    cfg.test_phases      = {'Test1','Test2'};
    cfg.training_levels  = {'level_L1','level_L2','level_L3','level_L4','level_L5'};
    cfg.level_names      = {'Level1','Level2','Level3','Level4','Level5'};
    cfg.n_training_reps  = 10;
    cfg.resting_duration = 180;
    
    cfg.amplitude_features = {'scl_mean','scl_range','scr_mean_amp','scr_max_amp', 'scr_auc','gsr_mean','gsr_std','gsr_rms'};
end

function p = expanduser(p)
    if strncmp(p,'~',1)
        home = getenv('HOME');
        if isempty(home), home = getenv('USERPROFILE'); end
        p = [home, p(2:end)];
    end
end