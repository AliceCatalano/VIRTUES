function C = load_ati_cal(cal_path)
% Returns the 6x6 UserAxis calibration matrix from an ATI .cal XML file.
% Row order: [Fx; Fy; Fz; Tx; Ty; Tz]
% Multiply: F = C * (V - V_bias)  ->  [N N N N·m N·m N·m]

    doc  = xmlread(cal_path);
    axes = doc.getElementsByTagName('UserAxis');
    C    = zeros(6,6);
    expected = {'Fx','Fy','Fz','Tx','Ty','Tz'};

    for k = 0:axes.getLength-1
        node  = axes.item(k);
        name  = char(node.getAttribute('Name'));
        row   = find(strcmp(expected, name), 1);
        if isempty(row), continue; end
        vals  = str2num(char(node.getAttribute('values'))); %#ok<ST2NM>
        C(row,:) = vals;
    end

    if any(C(:) == 0, 'all')
        warning('load_ati_cal: some calibration matrix entries are zero — check the .cal file path.');
    end
    fprintf('ATI calibration matrix loaded (UserAxis, units: N / N-m):\n');
    disp(C);
end