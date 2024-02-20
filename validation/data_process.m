function data = data_process(data)
    
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

if isfield(data, 'HardwareData')
    % Process hardware data file
    hdata_name = fieldnames(data.HardwareData);
    hdata = eval(['data.HardwareData.' hdata_name{1}]);
    [hdata_sim,~] = hwdata_sent(hdata,data.Measurements);
    % Data from hardware data file
    data.time_step_hdata = [hdata_sim.("Simulation Time Step")]/60;
    data.wshp_power_act = [hdata_sim.("WSHP Power [kW]")];
    data.inlet_water_temp_act = [hdata_sim.("Inlet Water Temp [°C]")];
    % Some old datasets do not have CompSpd
    if ismember('CompSpd', hdata_sim.Properties.VariableNames)
        vdc = [hdata_sim.("CompSpd")];
        data.comp_spd = spd_ratio(vdc);
    end
end

% Data from Measurements
data.time_step_sim = [data.Measurements.Timestep]'/60;
data.sup_flow_rate = [data.Measurements.m_sup]';
data.sup_temp = [data.Measurements.T_sup]';
data.sup_humd_ratio = [data.Measurements.w_sup]';
data.zone_temp = [data.SimData.T_z]';
data.tstat_spt = [data.SimData.Tz_cspt]';
data.zone_humd_ratio = [data.Measurements.w_z]';
data.wshp_power = [data.Measurements.Power_HVAC]';
data.inlet_water_temp = [data.Measurements.T_out_emulated]';

% Data from SimData
data.sen_load_sim = [data.SimData.Qsen_z]';
data.lat_load_sim = [data.SimData.Qlat_z]';

% Data from MPC_DebugData
if isfield(data, 'MPC_DebugData')
    data.time_step_mpcdebug = ([data.MPC_DebugData.Timestep]'+15)/60;
    data.wshp_power_pd = [data.MPC_DebugData.p_opt]'*1000;
    data.comp_spd_pd = [data.MPC_DebugData.y_opt]';
    data.inlet_water_temp_pd = [data.MPC_DebugData.T2_opt]';
    data.zone_temp_pd = [data.MPC_DebugData.Tz_opt]';
    data.wshp_power_pd_cal = predict_hp_cool_power_new(data.zone_temp_pd, data.inlet_water_temp_pd, data.comp_spd_pd); 
end

end

