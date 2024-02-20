function [sup_flow_rate, sup_temp, sup_humd_ratio, power, debug] = ...
    virtual_wshp(sys_stat, zone_temp, tstat_spt, inlet_water_temp, zone_humd_ratio, ctrl_step, debug_bound)
% Simulates the operation of a Water Source Heat Pump (WSHP) in a virtual environment.
% This function calculates the power consumption, sensible load, latent load, and air flow rate 
% of a WSHP based on the zone temperature, thermostat setpoint temperature,
% inlet water temperature, and zone humidity ratio.
%
% Inputs:
%   sys_stat: System status (0 - off, 1 - on)
%   zone_temp: Zone temperature [C]
%   tstat_spt: Thermostat setpoint temperature [C]
%   inlet_water_temp: Inlet water temperature [C]
%   zone_humd_ratio: Zone humidity ratio [kg/kg]
%   ctrl_step: Total control step during each call, it affects the error accumulation.
%
% Outputs:
%   sup_flow_rate: Supply air flow rate [kg/s]
%   sup_temp: Supply air temperature [C]
%   sup_humd_ratio: Supply air humidity ratio [kg/kg]
%   power: Power consumption [kW]
%   debug: Data for debug
%
% Developer: Zhelun Chen
% Date: 2024-02-18

% Persistent variable to store accumulated error
persistent acc_error 
% persistent variable to store past values
persistent comp_spd_p fan_spd_p sup_flow_rate_p sup_temp_p sup_humd_ratio_p power_p
% Persistent variable to store models
persistent comp_spd_model compspd2power_model compspd2sen_model compspd2lat_model fan_spd_model fanspd2cfm_model

% Initialize
if isempty(comp_spd_model)
    comp_spd_model = load("wshp_comp_spd_model");
    compspd2power_model = load("wshp_compspd2power_model");
    compspd2sen_model = load("wshp_compspd2sen_model");
    compspd2lat_model = load("wshp_compspd2lat_model");
    fan_spd_model = load("wshp_fan_spd_model");
    fanspd2cfm_model = load("wshp_fanspd2cfm_model");
    comp_spd_p = zeros(15,1);
    fan_spd_p = zeros(15,1);
    sup_flow_rate_p = zeros(15,1) + 380 * 0.0283 * 1.225 / 60; 
    sup_temp_p = zeros(15,1) + zone_temp;
    sup_humd_ratio_p = zeros(15,1) + zone_humd_ratio;
    power_p = zeros(15,1);
end

% Reset accumulated error
if isempty(acc_error) || (sys_stat == 0)
    % Initialize the accumulated error if it's the first call
    acc_error = 0;
end

% Air properties
cpa = 1.006;
cpw = 1.86;
hwe = 2501;

% Active setpoint
active_spt = tstat_spt + 1.5/1.8;

% Error
error = zone_temp - active_spt;

% Accumulate error with control step adjustment
new_accumulated_error = acc_error + error * ctrl_step;
% Anti-windup
if new_accumulated_error > 3000
    acc_error = 3000;
elseif new_accumulated_error < 0
    acc_error = 0;
else
    acc_error = new_accumulated_error;
end

% Compressor speed prediction
X = [error, acc_error, inlet_water_temp, zone_temp];
comp_spd = predict(comp_spd_model.comp_spd_model, X);
comp_spd = min(1, max(0, comp_spd));    % Within [0,1]
fan_spd = predict(fan_spd_model.fan_spd_model, X);

% % Update speed prediction history
% comp_spd_p = [comp_spd_p(2:end);comp_spd];
% fan_spd_p = [fan_spd_p(2:end);fan_spd];
% 
% % Smooth speed prediction
% comp_spd = mean(comp_spd_p);
% fan_spd = mean(fan_spd_p);
% 
% % Store smoothed values
% comp_spd_p(end) = comp_spd;
% fan_spd_p(end) = fan_spd;

% Power prediction
X = [inlet_water_temp, zone_temp, comp_spd];
power = predict(compspd2power_model.compspd2power_model, X);
power = max(0, power);  % Not negative

% Capacity prediction
X = [inlet_water_temp, zone_temp, zone_humd_ratio, comp_spd];
sen_load = predict(compspd2sen_model.compspd2sen_model, X);
lat_load = predict(compspd2lat_model.compspd2lat_model, X);

% Flow rate prediction
X = [fan_spd];
air_cfm = predict(fanspd2cfm_model.fanspd2cfm_model, X);
air_cfm = min(840, max(380, air_cfm));    % Within [380,840]

% Supply air mass flow rate
sup_flow_rate = air_cfm * 0.0283 * 1.225 / 60;

% % [DEBUG] MANUAL OVERRIDE
% sen_load = debug_bound.sen_load;
% lat_load = debug_bound.lat_load;
% sup_flow_rate = debug_bound.sup_flow_rate;

% Supply air temperature (from sensible load and zone condition)
sup_temp = sen_load / (sup_flow_rate * (cpa + cpw * zone_humd_ratio)) + zone_temp;

% Total load
tot_load = sen_load + lat_load;

% Zone air enthalpy (from zone condition)
zone_h = cpa * zone_temp + zone_humd_ratio * ( cpw * zone_temp + hwe);

% Supply air enthalpy (from total load and zone air enthalpy)
sup_h = tot_load / sup_flow_rate + zone_h;

% Supply air humidity
sup_humd_ratio = (sup_h - cpa*sup_temp) / (cpw*sup_temp + hwe);

% To prevent divided by 0 error
if sup_flow_rate < 1e-5
    sup_temp = 18;
    sup_humd_ratio = 0.00;
    power = 0;
end

% % Update history
% sup_flow_rate_p = [sup_flow_rate_p(2:end); sup_flow_rate];
% sup_temp_p = [sup_temp_p(2:end); sup_temp];
% sup_humd_ratio_p = [sup_humd_ratio_p(2:end); sup_humd_ratio];
% power_p = [power_p(2:end); power];
% 
% % Smooth output
% sup_flow_rate = mean(sup_flow_rate_p);
% sup_temp = mean(sup_temp_p);
% sup_humd_ratio = mean(sup_humd_ratio_p);
% power = mean(power_p);
% 
% % Update the hisotry array with the smoothed value
% sup_flow_rate_p(end) = sup_flow_rate;
% sup_temp_p(end) = sup_temp;
% sup_humd_ratio_p(end) = sup_humd_ratio;
% power_p(end) = power;

% Store debug data
debug.error = error;
debug.acc_error = acc_error;
debug.sen_load = sen_load;
debug.lat_load = lat_load;
debug.comp_spd = comp_spd;

end

