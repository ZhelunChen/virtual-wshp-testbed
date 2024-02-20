clc
clear all

%% Add WSHP to path
% directory
par_dir = pwd;
% add WSHP to path
addpath(strcat(par_dir,'\WSHP'));

%% Load boundary condition
data = load("../real_data/Tucson_Shif_TypSum_RB_2004_TypOcc_TypBehav_NoTES_03252023_112617.mat");
% Check and truncate excess data
if length(data.Measurements) > 1441
    data.Measurements = data.Measurements(1:1441,:);
    data.SupvCtrlSig = data.SupvCtrlSig(1:1441,:);
    data.SimData = data.SimData(1:1441,:);
    if iscell(data.SimData)
        for i = 1:length(data.SimData)
            temp(i,1) = data.SimData{i,1};
        end
        data.SimData = temp;
    end
end
% Process hardware data
hdata_name = fieldnames(data.HardwareData);
hdata = eval(['data.HardwareData.' hdata_name{1}]);
[hdata_sim,~] = hwdata_sent(hdata,data.Measurements);
% Inlet water temperature
inlet_water_temp_b = hdata_sim.("Inlet Water Temp [°C]");
% inlet_water_temp_b = [data.Measurements.T_out_emulated]';
% Zone air temperature
zone_temp_b = [data.SimData.T_z]';
% Zone air humidity ratio
zone_humd_ratio_b = [data.SimData.w_z]';
% Thermostat setpoint
tstat_spt_b = [data.SimData.Tz_cspt]';
% Supply flow rate
sup_flow_rate_b = [data.Measurements.m_sup]';
% Supply temperature
sup_temp_b = [data.Measurements.T_sup]';
% Supply humidity ratio
sup_humd_ratio_b = [data.Measurements.w_sup]';
% Sensible load
sen_load_b = [data.SimData.Qsen_z]'/1000;
% Latent load
lat_load_b = [data.SimData.Qlat_z]'/1000;

%% Run simulation
for timestep=0:1440
    % This input has been deprecated, provide any randome number works
    HardwareTime = timestep; 
    % Run virutal wshp to get Meas
    if timestep == 0
        run_sys_sim = 0;
    elseif CtrlSig(2,1) == 0
        run_sys_sim = 0;
    else
        run_sys_sim = 1;
    end
    if run_sys_sim < 1
        sup_flow_rate = 0;
        sup_temp = 18;
        sup_humd_ratio = 0.009;
        zone_temp = 25;
        zone_humd_ratio = 0.009;
        inlet_water_temp = inlet_water_temp_b(timestep+1);
        power = 0;
        sys_stat_p = 0;
    else
        % [DEBUG] 
        debug_bound.sen_load = sen_load_b(timestep+1);
        debug_bound.lat_load = lat_load_b(timestep+1);
        debug_bound.sup_flow_rate = sup_flow_rate_b(timestep+1);
        % Inputs
        zone_temp = ZoneInfo(8);
        tstat_spt = ZoneInfo(6);
        inlet_water_temp = inlet_water_temp_b(timestep);
        zone_humd_ratio = ZoneInfo(10);
        ctrl_step = 12;
        % Run virtual testbed
        [sup_flow_rate, sup_temp, sup_humd_ratio, power, debug] = ...
            virtual_wshp(sys_stat_p, zone_temp, tstat_spt, inlet_water_temp, zone_humd_ratio, ctrl_step, debug_bound);
        inlet_water_temp = inlet_water_temp_b(timestep+1);
        sys_stat_p = 1;
    end
    
    % Assemble Meas
    Meas = [sup_flow_rate, sup_temp, sup_humd_ratio, zone_temp, zone_humd_ratio, inlet_water_temp, power];
    
    % Run building simulation
    [ZoneInfo,CtrlSig]=callSim(HardwareTime,timestep,Meas);
    
    % Store debug data
    if run_sys_sim > 0
        debug_error(timestep+1) = debug.error;
        debug_acc_error(timestep+1) = debug.acc_error;
        debug_sen_load(timestep+1) = debug.sen_load;
        debug_lat_load(timestep+1) = debug.lat_load;
        debug_comp_spd(timestep+1) = debug.comp_spd;
        debug_zone_temp(timestep+1) = zone_temp;
        debug_tstat_spt(timestep+1) = tstat_spt;
        debug_zone_humd_ratio(timestep+1) = zone_humd_ratio;
    end
    
    % Print timestep
    disp(['Completed timestep: ', num2str(timestep)]);
end

% Save debug data
CollName=load('DBLoc.mat').CollName;
save(['../sim_data/DEBUG_' CollName '.mat'],...
      'debug_error',...
      'debug_acc_error',...
      'debug_sen_load',...
      'debug_lat_load',...
      'debug_comp_spd',...
      'debug_zone_temp',...
      'debug_tstat_spt',...
      'debug_zone_humd_ratio');
%% save all data to .mat file
DataDL;