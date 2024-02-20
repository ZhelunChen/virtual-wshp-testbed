function acc_errors = accumulated_errors(pv, spt, criteria_series, reset_threshold)
    % Calculate accumulated errors based on a process variable (pv),
    % setpoint (spt), and a criteria series that determines when to reset
    % the accumulated error based on the reset threshold.
    
    % Initialize the accumulated error vector
    acc_errors = zeros(size(pv));
    
    % Initialize a variable to keep track of the current accumulated error
    
    current_acc_error = 0;
    % Determine system off state using a rolling window approach
    windowSize = 15*12; % Assuming this is the window length
    system_off = movmean(criteria_series, [windowSize-1, 0]) < reset_threshold;
    
    % Iterate through the series
    for i = 1:length(pv)
        if system_off(i)
            % Reset accumulated error to 0 if power is below the threshold
            current_acc_error = 0;
        else
            % Calculate the error as the difference between temperature and setpoint
            error = pv(i) - spt(i);
            % Constraint the accumulated error
            if current_acc_error + error > 3000
                current_acc_error = 3000;
            elseif current_acc_error + error < 0
                current_acc_error = 0;
            else
                current_acc_error = current_acc_error + error;
            end
        end
        % Assign the current accumulated error to the vector
        acc_errors(i) = current_acc_error;
    end
end
