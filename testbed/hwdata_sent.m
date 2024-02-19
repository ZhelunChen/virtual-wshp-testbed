function [hdata_sim,delay] = hwdata_sent(hdata,Measurements)
%% Note
% hwdata: hardware data to be worked on, in structure format
% hwdata_sim: hardware data with minute-by-minute interval
% Measurements: measurements received by the simulation during the
% communication
% delay: communication delay
%% Main code
% go through data in Measurements one by one
for timestep=0:length(Measurements)-1
    % data received by the simulation
	Tsup = Measurements(timestep+1).T_sup;  % received z1 inlet air temp [C]
	if isfield(Measurements,'w_sup_received')
        wsup = Measurements(timestep+1).w_sup_received; 
    else
        wsup = Measurements(timestep+1).w_sup; 
	end
	received = [Tsup wsup];
    % locate rows of hardware data with the same timestep
    rows = find([hdata.('Current Simulation Step')]==timestep);
    if ~isempty(rows)
        % initialize recorder
        successfully_found = 0;
        % the measuremnts received for this time step, supposely, can be
        % found in the current row or some previous row. therefore, go back
        % at most 30 rows to see if the measurements can be found
        for j=rows(1):-1:max(1,rows(1)-30)
            % hardware data saved on the current row
            Tsup_hard = hdata.('WSHP Avg Supply Air Temp [°C]')(j);
            wsup_hard = hdata.('WSHP Avg Supply HR [kg/kg]')(j);            
            sent = [Tsup_hard wsup_hard];
            % check weather it matches the data saved in Measurements
            if all(abs(received-sent)<=1e-4)
                % if match, record this row and break for loop
                temp = hdata(j,:);    % copy row
                temp.('timestep_sent') = timestep;  % add the current timestep to the structure
                temp.('flag') = 0;  % no flag needed
                hdata_sim(timestep+1,:) = temp; % copy to the new structure
                delay(timestep+1,1) = (rows(1) - j)*5; % record communication delay
                successfully_found = 1; 
                break                              
            end
        end
        % check recorder
        if (successfully_found < 1)
            % if not found, use the current rows
            j = rows(1);
            temp = hdata(j,:);    % copy row
            temp.('timestep_sent') = timestep;  % add the current timestep to the structure
            temp.('flag') = 1;  % flag this time step
            hdata_sim(timestep+1,:) = temp; % copy to the new structure
            delay(timestep+1,1) = -1;    % communication delay set to 999         
        end
    else
        % if no row contain the current time step, it hardware is in the
        % skippoing mode, Measurements is receiving the same data from
        % hardware side. Assuming that the timestep 0 shoud always exist,
        % simply repeat the previous row
        if timestep == 0
            temp = hdata(1,:);    % copy row
            temp.('timestep_sent') = timestep;  % add the current timestep to the structure
            temp.('flag') = 1;  % flag this time step
            hdata_sim(timestep+1,:) = temp; % copy to the new structure
            delay(timestep+1,1) = -1;    % communication delay set to 999 
        else
            hdata_sim(timestep+1,:) = hdata_sim(timestep,:);
        end

    end
end
end

