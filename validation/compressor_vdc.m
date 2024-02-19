function vdc = compressor_vdc(fan_speed, power, power_low)
    % Initialize the vdc array with zeros of the same size as fan_speed
    vdc = zeros(size(fan_speed));
    
    % Conditions for calculating vdc
    condition = (fan_speed >= 49) & (power > power_low);
    vdc(condition) = (fan_speed(condition) / 100 + 0.0179) / 0.2073;
    
    % Apply maximum limit for vdc
    vdc(vdc > 4.91) = 4.91;
    
    % Ensure vdc does not go below 0
    vdc(vdc < 0) = 0;
    
end