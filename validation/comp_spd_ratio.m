function y = comp_spd_ratio(vdc)
    % Comp Speed Ratio Coefficients (vdc >= 2.42)
    m1 = (1 - 0.317) / (4.91 - 2.42);
    b1 = 0.317 - 2.42 * m1;
    % Comp Speed Ratio Coefficients (vdc < 2.42)
    m2 = 0.317 / 2.42;
    
    % Initialize y with zeros of the same size as vdc
    y = zeros(size(vdc));
    
    % Conditions for selecting coefficients
    cond = vdc >= 2.42;
    % Initialize m and b arrays
    m = m2 * ones(size(vdc)); % Default to m2 for all
    b = zeros(size(vdc));     % Default to 0 for all
    
    % Update m and b based on condition
    m(cond) = m1;
    b(cond) = b1;
    
    % Calculate compressor speed ratio
    y = m .* vdc + b;
    
end
